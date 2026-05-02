import SwiftASTLint
import SwiftSyntax

/// Detects `@Suite` attributes whose description string is identical to the type name (or
/// the type name with a trailing "Tests" suffix stripped), which adds no documentation value.
///
/// **Triggers when:**
/// - A `struct`, `class`, `actor`, or `extension` is annotated with `@Suite("…")`
/// - The description equals the type name (e.g. `@Suite("Foo") struct Foo`)
/// - Or the description equals the type name minus a "Tests" suffix
///   (e.g. `@Suite("CheckRunner") struct CheckRunnerTests`)
///
/// **Does NOT trigger when:**
/// - `@Suite` has no string argument (trait-only usage)
/// - The description string contains interpolation
/// - The description is a meaningful sentence different from the type name
let meaningfulSuiteDescriptionRule = Rule(id: "meaningful-suite-description") { file, context in
    let visitor = MeaningfulSuiteDescriptionVisitor(context: context)
    visitor.walk(file)
}

// MARK: - Visitor

private final class MeaningfulSuiteDescriptionVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuiteAttribute(in: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuiteAttribute(in: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuiteAttribute(in: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.extendedType.trimmedDescription
        checkSuiteAttribute(in: node.attributes, typeName: typeName, reportNode: Syntax(node))
        return .visitChildren
    }

    // MARK: - Core check

    private func checkSuiteAttribute(
        in attributes: AttributeListSyntax,
        typeName: String,
        reportNode: Syntax
    ) {
        for attribute in attributes {
            guard case let .attribute(attr) = attribute else { continue }
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self),
                  name.name.text == "Suite"
            else { continue }
            guard let description = extractStringLiteral(from: attr) else { continue }
            guard isRedundant(description: description, typeName: typeName) else { continue }

            context.report(
                on: reportNode,
                message: """
                @Suite description "\(description)" is identical to the type name and provides no value. \
                Describe what this suite tests instead, e.g. "@Suite(\\"meaningful-suite-description: detects …\\")".
                """,
                severity: .error
            )
        }
    }

    /// Returns the plain string value if the first string-literal argument has no interpolation,
    /// otherwise returns `nil`.
    private func extractStringLiteral(from attribute: AttributeSyntax) -> String? {
        guard case let .argumentList(args) = attribute.arguments else { return nil }
        for arg in args {
            guard let stringLit = arg.expression.as(StringLiteralExprSyntax.self) else { continue }
            // Only handle single-segment plain strings — skip interpolated ones
            let segments = stringLit.segments
            guard segments.count == 1,
                  case let .stringSegment(seg) = segments.first!
            else { return nil }
            return seg.content.text
        }
        return nil
    }

    /// Returns true when the description is trivially derived from the type name.
    private func isRedundant(description: String, typeName: String) -> Bool {
        // Collect the type name and its de-suffixed variants to check against
        var candidates = [typeName]
        for suffix in ["Tests", "Test", "Spec"] where typeName.hasSuffix(suffix) {
            candidates.append(String(typeName.dropLast(suffix.count)))
        }

        let separators = [" \u{2014} ", " \u{2013} ", " - ", ": "]
        for candidate in candidates {
            if description == candidate { return true }
            if separators.contains(where: { description.hasPrefix(candidate + $0) }) { return true }
        }
        return false
    }
}
