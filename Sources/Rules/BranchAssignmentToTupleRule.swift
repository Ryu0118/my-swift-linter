import SwiftASTLint
import SwiftSyntax

/// Detects the pattern of declaring one or more uninitialized `let` variables followed by an
/// `if/else` or `switch` that assigns every variable in every branch.
///
/// All cases can be collapsed into a single `let` binding using an `if`/`switch` expression:
///
/// ```swift
/// // ❌ single variable
/// let hoge: Int
/// if let x {
///     hoge = x
/// } else {
///     hoge = y
/// }
/// // ✅
/// let hoge = if let x { x } else { y }
///
/// // ❌ multiple variables
/// let days: Int
/// let pages: Int
/// if let duration {
///     days = duration.days
///     pages = duration.numPages
/// } else {
///     days = period.days
///     pages = period.pages
/// }
/// // ✅
/// let (days, pages) = if let duration {
///     (duration.days, duration.numPages)
/// } else {
///     (period.days, period.pages)
/// }
/// ```
///
/// **Detection conditions (all must hold):**
/// 1. One or more consecutive uninitialized `let` declarations with explicit type annotations.
/// 2. The immediately following statement is an `if/else` (2 branches) or a `switch`.
/// 3. Every branch contains *only* simple assignments (`name = expr`) to the declared variables.
/// 4. Every declared variable is assigned in every branch.
///
/// Fix-It is intentionally omitted; branch-level side-effects may prevent a mechanical rewrite.
let branchAssignmentToTupleRule = Rule(id: "branch-assignment-to-tuple") { file, context in
    let visitor = BranchAssignmentToTupleVisitor(context: context)
    visitor.walk(file)
}

// MARK: - Visitor

private final class BranchAssignmentToTupleVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        check(statements: node.statements)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        check(statements: node.statements)
        return .visitChildren
    }

    // MARK: - Core detection

    /// Scans a statement list for the pattern starting at each position.
    private func check(statements: CodeBlockItemListSyntax) {
        let items = Array(statements)
        var index = 0
        while index < items.count {
            let runStart = index
            var declaredNames: [String] = []

            while index < items.count,
                  let varDecl = items[index].item.as(VariableDeclSyntax.self),
                  isUninitializedLetDecl(varDecl)
            {
                declaredNames.append(contentsOf: bindingNames(varDecl))
                index += 1
            }

            guard declaredNames.count >= 1 else {
                index += 1
                continue
            }
            guard index < items.count else { break }

            checkFollowingBranch(
                items: items,
                runStart: runStart,
                nameSet: Set(declaredNames),
                followingItem: items[index]
            )
        }
    }

    /// Checks whether the statement after the `let` run is a matching if/else or switch,
    /// and reports a warning if so.
    ///
    /// - Parameters:
    ///   - items: All statements in the enclosing block.
    ///   - runStart: Index of the first `let` in the run.
    ///   - nameSet: Names declared by the `let` run.
    ///   - followingItem: The statement immediately after the run.
    private func checkFollowingBranch(
        items: [CodeBlockItemSyntax],
        runStart: Int,
        nameSet: Set<String>,
        followingItem: CodeBlockItemSyntax
    ) {
        let matches: Bool
        if let ifNode = ifExpr(from: followingItem), isIfElse(ifNode) {
            matches = allBranchesAssignOnly(nameSet, inIf: ifNode)
        } else if let switchNode = switchStmt(from: followingItem) {
            matches = allCasesAssignOnly(nameSet, inSwitch: switchNode)
        } else {
            matches = false
        }
        guard matches else { return }
        context.report(
            on: items[runStart],
            message: "Collapse `let` declarations and branch assignment into a single "
                + "`let x = if ... { ... } else { ... }` binding. "
                + "For multiple variables use `let (a, b) = if ... { (x, y) } else { (p, q) }`.",
            severity: .warning
        )
    }

    // MARK: - Declaration helpers

    /// Returns `true` when `varDecl` is a `let` with no initializer and at least one
    /// explicit type annotation — i.e. `let x: Int` but not `let x = 0` or `let x`.
    private func isUninitializedLetDecl(_ node: VariableDeclSyntax) -> Bool {
        guard node.bindingSpecifier.tokenKind == .keyword(.let) else { return false }
        return node.bindings.allSatisfy { binding in
            binding.initializer == nil && binding.typeAnnotation != nil
        }
    }

    /// Returns the bound identifier names for every binding in a variable declaration.
    private func bindingNames(_ node: VariableDeclSyntax) -> [String] {
        node.bindings.compactMap { binding in
            binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        }
    }

    // MARK: - If/else branch analysis

    /// Extracts an `IfExprSyntax` from a statement item.
    /// `if` in statement position is parsed as ExpressionStmtSyntax(.stmt) wrapping IfExprSyntax.
    private func ifExpr(from item: CodeBlockItemSyntax) -> IfExprSyntax? {
        // statement context: CodeBlockItemSyntax.Item is .stmt(StmtSyntax)
        if let stmt = item.item.as(StmtSyntax.self),
           let exprStmt = stmt.as(ExpressionStmtSyntax.self)
        {
            return exprStmt.expression.as(IfExprSyntax.self)
        }
        // expression context (if used as rhs of assignment etc.)
        if let expr = item.item.as(ExprSyntax.self) {
            return expr.as(IfExprSyntax.self)
        }
        return nil
    }

    /// Returns `true` when the `if` has exactly one `else` clause that is a plain block
    /// (not another `if`, so no `else if` chains).
    private func isIfElse(_ node: IfExprSyntax) -> Bool {
        guard let elseBody = node.elseBody else { return false }
        if case .codeBlock = elseBody { return true }
        return false
    }

    /// Returns `true` when every branch of `if/else` assigns *only* to `names` and covers
    /// all of them.
    private func allBranchesAssignOnly(_ names: Set<String>, inIf node: IfExprSyntax) -> Bool {
        guard case let .codeBlock(elseBlock) = node.elseBody else { return false }
        return branchAssignsOnly(names, stmts: node.body.statements)
            && branchAssignsOnly(names, stmts: elseBlock.statements)
    }

    // MARK: - Switch branch analysis

    private func switchStmt(from item: CodeBlockItemSyntax) -> SwitchExprSyntax? {
        if let stmt = item.item.as(StmtSyntax.self),
           let exprStmt = stmt.as(ExpressionStmtSyntax.self)
        {
            return exprStmt.expression.as(SwitchExprSyntax.self)
        }
        if let expr = item.item.as(ExprSyntax.self) {
            return expr.as(SwitchExprSyntax.self)
        }
        return nil
    }

    /// Returns `true` when every non-`default` case (and any `default`) in the switch assigns
    /// *only* to `names` and covers all of them, with no fallthrough.
    private func allCasesAssignOnly(_ names: Set<String>, inSwitch node: SwitchExprSyntax) -> Bool {
        let cases = node.cases
        guard !cases.isEmpty else { return false }
        for switchCase in cases {
            guard let caseItem = switchCase.as(SwitchCaseSyntax.self) else { return false }
            if !branchAssignsOnly(names, stmts: caseItem.statements) { return false }
        }
        return true
    }

    // MARK: - Branch statement analysis

    /// Returns `true` when `stmts` contains *only* simple assignments to every name in
    /// `names` (exactly once each, no extras, no other statements).
    private func branchAssignsOnly(_ names: Set<String>, stmts: CodeBlockItemListSyntax) -> Bool {
        var assigned: Set<String> = []
        for stmt in stmts {
            // In statement context, assignments appear as ExpressionStmtSyntax inside .stmt
            let expression: ExprSyntax?
            if let stmtSyntax = stmt.item.as(StmtSyntax.self) {
                expression = stmtSyntax.as(ExpressionStmtSyntax.self)?.expression
            } else {
                expression = stmt.item.as(ExprSyntax.self)
            }
            guard let expression, let lhsName = assignedName(from: expression)
            else { return false }

            guard names.contains(lhsName) else { return false }
            guard !assigned.contains(lhsName) else { return false }
            assigned.insert(lhsName)
        }
        return assigned == names
    }

    /// Extracts the LHS variable name from a simple assignment expression (`name = expr`).
    /// Handles both `InfixOperatorExprSyntax` (Swift 5.9+ AST) and the legacy
    /// `SequenceExprSyntax` form.
    private func assignedName(from expr: ExprSyntax) -> String? {
        // Swift 5.9+ parses `a = b` as InfixOperatorExprSyntax
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           infix.operator.is(AssignmentExprSyntax.self),
           let lhsIdent = infix.leftOperand.as(DeclReferenceExprSyntax.self)
        {
            return lhsIdent.baseName.text
        }
        // Fallback: SequenceExprSyntax with [lhs, AssignmentExpr, rhs]
        if let seq = expr.as(SequenceExprSyntax.self) {
            let elements = Array(seq.elements)
            if elements.count == 3,
               let lhsIdent = elements[0].as(DeclReferenceExprSyntax.self),
               elements[1].is(AssignmentExprSyntax.self)
            {
                return lhsIdent.baseName.text
            }
        }
        return nil
    }
}
