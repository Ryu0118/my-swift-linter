import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Enforces two rules for `some View`-returning computed properties.
///
/// **Pattern A — `return` is forbidden**
/// Using `return` inside a `some View` computed property body is always a violation,
/// regardless of whether `@ViewBuilder` is present.
/// Fix-It: removes the `return` keyword.
///
/// **Pattern B — `@ViewBuilder` is required**
/// When a `some View` computed property body contains any of the following at the top level
/// without `@ViewBuilder`, a violation is reported:
/// - `let`/`var` declarations
/// - `if` expressions
/// - `switch` expressions
///
/// Without `@ViewBuilder`, `if`/`switch` are interpreted as plain Swift expressions,
/// meaning both branches must return the exact same concrete type — which defeats the
/// purpose of `some View`. Adding `@ViewBuilder` lets the result builder compose the views
/// from each branch naturally, and eliminates the need for `return`.
/// Fix-It: inserts `@ViewBuilder` before the `var` keyword.
///
/// **Exception**: `var body: some View` is excluded because `View.body` already has
/// an implicit `@ViewBuilder` from the protocol requirement.
let swiftUIViewPropertyRule = Rule(id: "swiftui-view-property") { file, context in
    let visitor = SwiftUIViewPropertyVisitor(context: context)
    visitor.walk(file)
}

private final class SwiftUIViewPropertyVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isSomeViewComputedProperty(node) else { return .visitChildren }
        guard let body = computedPropertyBody(node) else { return .visitChildren }

        checkReturnStatements(in: body.statements)

        if !hasViewBuilderAttribute(node) {
            checkViewBuilderRequired(for: node, statements: body.statements)
        }

        return .visitChildren
    }

    // MARK: - Pattern A: return detection

    private func checkReturnStatements(in statements: CodeBlockItemListSyntax) {
        for stmt in statements {
            guard let returnStmt = stmt.item.as(ReturnStmtSyntax.self) else { continue }
            let returnKeyword = returnStmt.returnKeyword
            context.reportWithFix(
                on: returnStmt,
                message: "Do not use `return` in a `some View` computed property. "
                    + "If you need top-level `let`/`var`, `if`, or `switch`, add `@ViewBuilder`.",
                severity: .error,
                fixIts: [
                    FixIt.replace(
                        message: SimpleFixItMessage("Remove `return`"),
                        oldNode: returnKeyword,
                        newNode: returnKeyword.with(\.tokenKind, .identifier("")).with(\.trailingTrivia, [])
                    ),
                ]
            )
        }
    }

    // MARK: - Pattern B: @ViewBuilder requirement

    private func checkViewBuilderRequired(for node: VariableDeclSyntax, statements: CodeBlockItemListSyntax) {
        let needsViewBuilder = statements.contains { stmt in
            if stmt.item.is(VariableDeclSyntax.self) { return true }
            // if/switch appear as IfExprSyntax/SwitchExprSyntax wrapped in ExpressionStmtSyntax
            if let exprStmt = stmt.item.as(ExpressionStmtSyntax.self) {
                return exprStmt.expression.is(IfExprSyntax.self)
                    || exprStmt.expression.is(SwitchExprSyntax.self)
            }
            return false
        }
        guard needsViewBuilder else { return }

        let varKeyword = node.bindingSpecifier
        context.reportWithFix(
            on: node,
            message: "Add `@ViewBuilder` when a `some View` computed property uses "
                + "`let`/`var`, `if`, or `switch` at the top level. `return` is then unnecessary.",
            severity: .error,
            fixIts: [
                FixIt.replace(
                    message: SimpleFixItMessage("Add `@ViewBuilder`"),
                    oldNode: varKeyword,
                    newNode: varKeyword.with(
                        \.leadingTrivia,
                        varKeyword.leadingTrivia + [.unexpectedText("@ViewBuilder ")]
                    )
                ),
            ]
        )
    }

    // MARK: - Helpers

    /// Returns `true` when the node is a `some View`-returning computed property.
    ///
    /// `var body` is excluded because `View.body` has an implicit `@ViewBuilder`
    /// from the protocol requirement.
    private func isSomeViewComputedProperty(_ node: VariableDeclSyntax) -> Bool {
        guard node.bindingSpecifier.tokenKind == .keyword(.var) else { return false }
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            if pattern.identifier.text == "body" { return false }
            guard let typeAnnotation = binding.typeAnnotation else { continue }
            let typeText = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
            if typeText.hasPrefix("some ") && typeText.contains("View") {
                return true
            }
        }
        return false
    }

    /// Returns the implicit getter body of a computed property, or `nil` for explicit getter syntax.
    private func computedPropertyBody(_ node: VariableDeclSyntax) -> CodeBlockSyntax? {
        for binding in node.bindings {
            if let accessor = binding.accessorBlock,
               case let .getter(stmts) = accessor.accessors
            {
                return CodeBlockSyntax(
                    leftBrace: accessor.leftBrace,
                    statements: stmts,
                    rightBrace: accessor.rightBrace
                )
            }
        }
        return nil
    }

    private func hasViewBuilderAttribute(_ node: VariableDeclSyntax) -> Bool {
        node.attributes.contains { attr in
            guard case let .attribute(attrSyntax) = attr else { return false }
            return attrSyntax.attributeName.description.trimmingCharacters(in: .whitespaces) == "ViewBuilder"
        }
    }
}
