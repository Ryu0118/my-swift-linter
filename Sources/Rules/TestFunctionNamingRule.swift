import SwiftASTLint
import SwiftSyntax

/// Detects `@Test` functions whose name is a backtick-quoted natural-language phrase
/// (e.g. `` func `foo does bar`() `` ) and requires using lowerCamelCase with the
/// description moved into `@Test("…")` instead.
///
/// **Triggers when:**
/// - A function is annotated with `@Test` (with or without arguments)
/// - The function name contains spaces (i.e. is backtick-quoted as a sentence)
///
/// **Does NOT trigger when:**
/// - The function name is a backtick-escaped Swift keyword (no spaces, e.g. `` `default` ``)
/// - The function has no `@Test` attribute
let testFunctionNamingRule = Rule(id: "test-function-naming") { file, context in
    let visitor = TestFunctionNamingVisitor(context: context)
    visitor.walk(file)
}

// MARK: - Visitor

private final class TestFunctionNamingVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes) else { return .visitChildren }
        let rawName = node.name.text
        guard nameContainsSpaces(rawName) else { return .visitChildren }

        context.report(
            on: node,
            message: """
            @Test function name "\(rawName)" uses a backtick-quoted phrase. \
            Use lowerCamelCase and move the description into @Test("…") instead.
            """,
            severity: .error
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attr) = element else { return false }
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return name.name.text == "Test"
        }
    }

    /// Returns true when the identifier text (as stored by SwiftSyntax, without backticks)
    /// contains at least one space — which means it was written as a backtick-quoted phrase.
    /// Single-word backtick escapes like `` `default` `` have no spaces and are excluded.
    private func nameContainsSpaces(_ name: String) -> Bool {
        name.contains(" ")
    }
}
