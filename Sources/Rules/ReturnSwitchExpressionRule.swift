import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Detects `switch` statements where every case contains a single `return <expr>`
/// and suggests collapsing them into a single `return switch ...` expression.
///
/// **Triggers when ALL of:**
/// 1. A statement-position `switch` expression exists.
/// 2. Every switch case is a regular `case`/`default` case.
/// 3. Every case body contains exactly one `return <expr>` with a non-nil expression.
///
/// **Does NOT trigger when:**
/// - A case has `return` with no expression.
/// - Any case has more than one statement.
/// - The switch is already the RHS of a `return` statement.
///
/// **Auto-fix:** Rewrites to `return switch value { case ...: expr }`.
struct ReturnSwitchExpressionArgs: Codable {
    var severity: Severity = .error
}

let returnSwitchExpressionRule = ParameterizedRule(
    id: "return-switch-expression",
    defaultArguments: ReturnSwitchExpressionArgs(),
) { file, context, args in
    let visitor = ReturnSwitchExpressionVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class ReturnSwitchExpressionVisitor: SyntaxVisitor {
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
            guard let switchExpr = extractStatementLevelSwitchExpr(from: item) else { continue }
            guard qualifies(switchExpr) else { continue }

            let fixed = buildReturnSwitchExpr(switchExpr: switchExpr)
            let fixedItem = item
                .with(\.item, .stmt(StmtSyntax(fixed)))

            context.reportWithFix(
                on: item,
                message: "Collapse switch-case returns into a `return switch` expression.",
                severity: severity,
                fixIts: [
                    FixIt.replace(
                        message: SimpleFixItMessage(
                            "Replace with `return switch ... { expr }`",
                        ),
                        oldNode: item,
                        newNode: fixedItem,
                    ),
                ],
            )
        }
    }

    private func extractStatementLevelSwitchExpr(from item: CodeBlockItemSyntax) -> SwitchExprSyntax? {
        if let stmt = item.item.as(StmtSyntax.self) {
            if stmt.is(ReturnStmtSyntax.self) { return nil }
            if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                return exprStmt.expression.as(SwitchExprSyntax.self)
            }
        }
        return nil
    }

    private func qualifies(_ node: SwitchExprSyntax) -> Bool {
        guard !node.cases.isEmpty else { return false }

        for switchCase in node.cases {
            guard let caseItem = switchCase.as(SwitchCaseSyntax.self) else { return false }
            guard isSingleReturnCase(caseItem.statements) else { return false }
        }
        return true
    }

    private func isSingleReturnCase(_ stmts: CodeBlockItemListSyntax) -> Bool {
        let items = Array(stmts)
        guard items.count == 1 else { return false }
        guard let stmt = items[0].item.as(StmtSyntax.self),
              let ret = stmt.as(ReturnStmtSyntax.self),
              ret.expression != nil
        else { return false }
        return true
    }

    // MARK: - Fix-it construction

    private func buildReturnSwitchExpr(switchExpr: SwitchExprSyntax) -> ReturnStmtSyntax {
        let rewritten = stripReturnsFromCases(switchExpr)
            .with(\.leadingTrivia, .space)
        let returnKeyword = TokenSyntax.keyword(.return)
            .with(\.leadingTrivia, [])
            .with(\.trailingTrivia, [])
        return ReturnStmtSyntax(
            returnKeyword: returnKeyword,
            expression: ExprSyntax(rewritten),
        )
    }

    private func stripReturnsFromCases(_ node: SwitchExprSyntax) -> SwitchExprSyntax {
        let strippedCases = node.cases.map { switchCase -> SwitchCaseListSyntax.Element in
            guard let caseItem = switchCase.as(SwitchCaseSyntax.self) else { return switchCase }
            return SwitchCaseListSyntax.Element(stripReturnFromCase(caseItem))
        }
        return node.with(\.cases, SwitchCaseListSyntax(strippedCases))
    }

    private func stripReturnFromCase(_ switchCase: SwitchCaseSyntax) -> SwitchCaseSyntax {
        guard let firstItem = switchCase.statements.first,
              let stmt = firstItem.item.as(StmtSyntax.self),
              let ret = stmt.as(ReturnStmtSyntax.self),
              let expr = ret.expression
        else { return switchCase }

        let exprWithTrivia = expr
            .with(\.leadingTrivia, firstItem.leadingTrivia + ret.returnKeyword.trailingTrivia)
            .with(\.trailingTrivia, firstItem.trailingTrivia)

        let newItem = CodeBlockItemSyntax(item: .expr(exprWithTrivia))
            .with(\.leadingTrivia, [])

        return switchCase.with(\.statements, CodeBlockItemListSyntax([newItem]))
    }
}
