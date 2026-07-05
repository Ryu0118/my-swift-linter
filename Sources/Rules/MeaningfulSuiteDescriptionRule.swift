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
struct MeaningfulSuiteDescriptionArgs: Codable {
    var severity: Severity = .error
}

let meaningfulSuiteDescriptionRule = ParameterizedRule(
    id: "meaningful-suite-description",
    defaultArguments: MeaningfulSuiteDescriptionArgs(),
) { file, context, args in
    let visitor = MeaningfulSuiteDescriptionVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class MeaningfulSuiteDescriptionVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
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
        reportNode: Syntax,
    ) {
        guard let description = attributes.attribute(named: "Suite")?.plainStringArgument else {
            return
        }
        guard isRedundant(description: description, typeName: typeName) else { return }

        context.report(
            on: reportNode,
            message: """
            @Suite description "\(description)" is identical to the type name and provides no value. \
            Describe what this suite tests instead, e.g. "@Suite(\\"meaningful-suite-description: detects …\\")".
            """,
            severity: severity,
        )
    }

    /// Returns true when the description is trivially derived from the type name.
    private func isRedundant(description: String, typeName: String) -> Bool {
        // Collect the type name and its de-suffixed variants to check against
        var candidates = [typeName]
        let stripped = strippedTestSuiteName(typeName)
        if stripped != typeName {
            candidates.append(stripped)
        }

        let separators = [" \u{2014} ", " \u{2013} ", " - ", ": "]
        for candidate in candidates {
            if description == candidate { return true }
            if separators.contains(where: { description.hasPrefix(candidate + $0) }) { return true }
        }
        return false
    }
}
