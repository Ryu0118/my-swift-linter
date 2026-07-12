import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Enforces two rules for `some View`-returning computed properties and functions.
///
/// **Pattern A — `return` is forbidden**
/// Using `return` inside a `some View` computed property or function body is always a violation,
/// regardless of whether `@ViewBuilder` is present.
/// Fix-It: removes the `return` keyword.
///
/// **Pattern B — `@ViewBuilder` is required**
/// When a `some View` computed property or function body contains any of the following at the top level
/// without `@ViewBuilder`, a violation is reported:
/// - `let`/`var` declarations
/// - `if` expressions
/// - `switch` expressions
///
/// Without `@ViewBuilder`, `if`/`switch` are interpreted as plain Swift expressions,
/// meaning both branches must return the exact same concrete type — which defeats the
/// purpose of `some View`. Adding `@ViewBuilder` lets the result builder compose the views
/// from each branch naturally, and eliminates the need for `return`.
/// Fix-It: inserts `@ViewBuilder` before the `var` keyword (properties) or `func` keyword (functions).
///
/// **Exception**: `var body: some View` and `func body(content:) -> some View` are excluded
/// because `View.body` and `ViewModifier.body(content:)` already have an implicit
/// `@ViewBuilder` from their protocol requirements.
struct SwiftUIViewPropertyArgs: Codable {
    var severity: Severity = .error
}

let swiftUIViewPropertyRule = ParameterizedRule(
    id: "swiftui-view-property",
    defaultArguments: SwiftUIViewPropertyArgs(),
) { file, context, args in
    let visitor = SwiftUIViewPropertyVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

private final class SwiftUIViewPropertyVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
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

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isSomeViewFunction(node) else { return .visitChildren }
        guard let body = node.body else { return .visitChildren }

        checkReturnStatements(in: body.statements)

        if !hasViewBuilderAttributeOnFunction(node) {
            checkViewBuilderRequiredForFunction(for: node, statements: body.statements)
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
                severity: severity,
                fixIts: [
                    FixIt.replace(
                        message: SimpleFixItMessage("Remove `return`"),
                        oldNode: returnKeyword,
                        newNode: returnKeyword.with(\.tokenKind, .identifier("")).with(\.trailingTrivia, []),
                    ),
                ],
            )
        }
    }

    // MARK: - Pattern B: @ViewBuilder requirement

    private func checkViewBuilderRequired(for node: VariableDeclSyntax, statements: CodeBlockItemListSyntax) {
        guard needsViewBuilder(statements) else { return }

        // Insert `@ViewBuilder` before the declaration's first token (including modifiers like
        // `private`), not before `var` itself — inserting at `bindingSpecifier` would produce
        // `private @ViewBuilder var`, which is invalid Swift (attribute must precede modifiers).
        let firstToken = node.modifiers.first?.name ?? node.bindingSpecifier
        context.reportWithFix(
            on: node,
            message: "Add `@ViewBuilder` when a `some View` computed property uses "
                + "`let`/`var`, `if`, or `switch` at the top level. `return` is then unnecessary.",
            severity: severity,
            fixIts: [
                FixIt.replace(
                    message: SimpleFixItMessage("Add `@ViewBuilder`"),
                    oldNode: firstToken,
                    newNode: firstToken.with(
                        \.leadingTrivia,
                        firstToken.leadingTrivia + viewBuilderPrefix(precedingIndent: firstToken.leadingTrivia),
                    ),
                ),
            ],
        )
    }

    private func checkViewBuilderRequiredForFunction(
        for node: FunctionDeclSyntax,
        statements: CodeBlockItemListSyntax,
    ) {
        guard needsViewBuilder(statements) else { return }

        // Same rationale as the property case above: insert before the first token of the
        // declaration (modifiers included), not before `func` — `private @ViewBuilder func`
        // is invalid Swift.
        let firstToken = node.modifiers.first?.name ?? node.funcKeyword
        context.reportWithFix(
            on: node,
            message: "Add `@ViewBuilder` when a `some View` function uses "
                + "`let`/`var`, `if`, or `switch` at the top level. `return` is then unnecessary.",
            severity: severity,
            fixIts: [
                FixIt.replace(
                    message: SimpleFixItMessage("Add `@ViewBuilder`"),
                    oldNode: firstToken,
                    newNode: firstToken.with(
                        \.leadingTrivia,
                        firstToken.leadingTrivia + viewBuilderPrefix(precedingIndent: firstToken.leadingTrivia),
                    ),
                ),
            ],
        )
    }

    /// Builds the trivia to append after the declaration's existing leading trivia (which already
    /// carries the newline/indent from the previous line): `@ViewBuilder`, then a newline, then
    /// the same indentation the declaration already has — so the original modifier/keyword that
    /// follows lands correctly indented on its own line below `@ViewBuilder`.
    private func viewBuilderPrefix(precedingIndent: Trivia) -> Trivia {
        let indent = precedingIndent.pieces.last(where: { $0.isSpaceOrTab }).map { Trivia(pieces: [$0]) } ?? []
        return Trivia(pieces: [.unexpectedText("@ViewBuilder")]) + .newlines(1) + indent
    }

    private func needsViewBuilder(_ statements: CodeBlockItemListSyntax) -> Bool {
        statements.contains { stmt in
            if stmt.item.is(VariableDeclSyntax.self) { return true }
            if let exprStmt = stmt.item.as(ExpressionStmtSyntax.self) {
                return exprStmt.expression.is(IfExprSyntax.self)
                    || exprStmt.expression.is(SwitchExprSyntax.self)
            }
            return false
        }
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
            if typeText.hasPrefix("some "), typeText.contains("View") {
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
                    rightBrace: accessor.rightBrace,
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

    /// Returns `true` when the function returns `some View` (or `some <X>View`).
    ///
    /// `func body(content:)` is excluded because it is the `ViewModifier.body(content:)`
    /// protocol witness, which already carries an implicit `@ViewBuilder` from the
    /// protocol requirement (mirrors the `var body` exclusion for `View`).
    private func isSomeViewFunction(_ node: FunctionDeclSyntax) -> Bool {
        guard let returnType = node.signature.returnClause?.type else { return false }
        let typeText = returnType.description.trimmingCharacters(in: .whitespaces)
        guard typeText.hasPrefix("some "), typeText.contains("View") else { return false }
        if isViewModifierBody(node) { return false }
        return true
    }

    /// Returns `true` when the function is the `ViewModifier.body(content:)` witness:
    /// named `body` with a single parameter labeled `content`.
    private func isViewModifierBody(_ node: FunctionDeclSyntax) -> Bool {
        guard node.name.text == "body" else { return false }
        let parameters = node.signature.parameterClause.parameters
        guard parameters.count == 1, let parameter = parameters.first else { return false }
        return parameter.firstName.text == "content"
    }

    private func hasViewBuilderAttributeOnFunction(_ node: FunctionDeclSyntax) -> Bool {
        node.attributes.contains { attr in
            guard case let .attribute(attrSyntax) = attr else { return false }
            return attrSyntax.attributeName.description.trimmingCharacters(in: .whitespaces) == "ViewBuilder"
        }
    }
}
