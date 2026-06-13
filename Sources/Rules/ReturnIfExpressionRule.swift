import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Detects consecutive `return` statements inside every branch of an `if/else-if*/else` chain
/// and suggests collapsing them into a single `return if ... { expr } else if ... { expr } else { expr }`.
///
/// **Triggers when ALL of:**
/// 1. A statement-position `if` expression exists.
/// 2. The chain terminates in a plain `else { ... }` block (not `else if`).
/// 3. Every branch body (if-body, every else-if body, final else body) contains exactly one
///    statement, and that statement is a `return <expr>` with a non-nil expression.
///
/// **Does NOT trigger when:**
/// - A branch has `return` with no expression (bare `return`).
/// - Any branch has more than one statement.
/// - The chain has no terminal `else`.
/// - The `if` is already the RHS of a `return` statement.
///
/// **Auto-fix:** Rewrites to `return if ... { <expr> } else if ... { <expr> } else { <expr> }`.
struct ReturnIfExpressionArgs: Codable {
    var severity: Severity = .warning
}

let returnIfExpressionRule = ParameterizedRule(
    id: "return-if-expression",
    defaultArguments: ReturnIfExpressionArgs(),
) { file, context, args in
    let visitor = ReturnIfExpressionVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class ReturnIfExpressionVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
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

    /// implicit getter (computed property without explicit `get`) uses AccessorBlockSyntax directly
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        if case let .getter(stmts) = node.accessors {
            check(statements: stmts)
        }
        return .visitChildren
    }

    // MARK: - Detection

    private func check(statements: CodeBlockItemListSyntax) {
        for item in statements {
            guard let ifExpr = extractStatementLevelIfExpr(from: item) else { continue }
            guard qualifies(ifExpr) else { continue }

            let fixed = buildReturnIfExpr(ifExpr: ifExpr)
            let fixedItem = item
                .with(\.item, .stmt(StmtSyntax(fixed)))

            context.reportWithFix(
                on: item,
                message: "Collapse multi-branch returns into `return if { … } else { … }`.",
                severity: severity,
                fixIts: [
                    FixIt.replace(
                        message: SimpleFixItMessage(
                            "Replace with `return if … { expr } else { expr }`",
                        ),
                        oldNode: item,
                        newNode: fixedItem,
                    ),
                ],
            )
        }
    }

    // MARK: - Qualification check

    /// Extracts an `IfExprSyntax` only when the item is a *statement-position* if expression —
    /// i.e. not the `expression` child of a `ReturnStmtSyntax`.
    private func extractStatementLevelIfExpr(from item: CodeBlockItemSyntax) -> IfExprSyntax? {
        if let stmt = item.item.as(StmtSyntax.self) {
            // ReturnStmt wrapping an if → already a return-if expression, skip
            if stmt.is(ReturnStmtSyntax.self) { return nil }
            if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                return exprStmt.expression.as(IfExprSyntax.self)
            }
        }
        return nil
    }

    /// Returns true when the entire if-chain satisfies the detection conditions.
    private func qualifies(_ node: IfExprSyntax) -> Bool {
        // if-body must be a single-return branch
        guard isSingleReturnBranch(node.body.statements) else { return false }
        // Walk the else chain; must terminate in a plain else-block, all branches single-return
        return elseChainQualifies(node.elseBody)
    }

    /// Recursively validates else-if and final else branches.
    private func elseChainQualifies(_ elseBody: IfExprSyntax.ElseBody?) -> Bool {
        guard let elseBody else { return false }
        switch elseBody {
        case let .codeBlock(block):
            return isSingleReturnBranch(block.statements)
        case let .ifExpr(nestedIf):
            guard isSingleReturnBranch(nestedIf.body.statements) else { return false }
            return elseChainQualifies(nestedIf.elseBody)
        }
    }

    /// A branch qualifies when it contains exactly one `return <expr>` (non-bare).
    private func isSingleReturnBranch(_ stmts: CodeBlockItemListSyntax) -> Bool {
        let items = Array(stmts)
        guard items.count == 1 else { return false }
        guard let stmt = items[0].item.as(StmtSyntax.self),
              let ret = stmt.as(ReturnStmtSyntax.self),
              ret.expression != nil
        else { return false }
        return true
    }

    // MARK: - Fix-it construction

    /// Builds `return <rewrittenIfExpr>`. Leading trivia stays on the enclosing CodeBlockItem.
    private func buildReturnIfExpr(ifExpr: IfExprSyntax) -> ReturnStmtSyntax {
        let rewritten = stripReturnsFromBranches(ifExpr)
            .with(\.leadingTrivia, .space)
        let returnKeyword = TokenSyntax.keyword(.return)
            .with(\.leadingTrivia, [])
            .with(\.trailingTrivia, [])
        return ReturnStmtSyntax(
            returnKeyword: returnKeyword,
            expression: ExprSyntax(rewritten),
        )
    }

    /// Recursively replaces each leaf branch's `return <expr>` with just `<expr>`.
    private func stripReturnsFromBranches(_ node: IfExprSyntax) -> IfExprSyntax {
        let strippedBody = stripReturnFromBlock(node.body)
        let strippedElse: IfExprSyntax.ElseBody? = node.elseBody.map { elseBody in
            switch elseBody {
            case let .codeBlock(block):
                .codeBlock(stripReturnFromBlock(block))
            case let .ifExpr(nested):
                .ifExpr(stripReturnsFromBranches(nested))
            }
        }
        return node
            .with(\.body, strippedBody)
            .with(\.elseBody, strippedElse)
    }

    /// Replaces the single `return <expr>` in `block.statements` with a bare `<expr>`.
    private func stripReturnFromBlock(_ block: CodeBlockSyntax) -> CodeBlockSyntax {
        guard let firstItem = block.statements.first,
              let stmt = firstItem.item.as(StmtSyntax.self),
              let ret = stmt.as(ReturnStmtSyntax.self),
              let expr = ret.expression
        else { return block }

        // Preserve the indentation/leading trivia of the original return statement on the expr.
        let exprWithTrivia = expr
            .with(\.leadingTrivia, firstItem.leadingTrivia + (ret.returnKeyword.trailingTrivia))
            .with(\.trailingTrivia, firstItem.trailingTrivia)

        let newItem = CodeBlockItemSyntax(item: .expr(exprWithTrivia))
            .with(\.leadingTrivia, [])

        let newStatements = CodeBlockItemListSyntax([newItem])
        return block.with(\.statements, newStatements)
    }
}
