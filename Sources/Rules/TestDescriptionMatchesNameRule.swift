import SwiftASTLint
import SwiftSyntax

struct TestDescriptionMatchesNameArgs: Codable, Sendable {
    var severity: Severity = .error
}

/// Detects `@Test` functions and `@Suite` types whose display description does not correspond
/// to the function/type name.
///
/// **Matching strategy:** Both the description and the name are *normalized* — all characters
/// other than ASCII letters and digits are removed and the result is lowercased — before
/// comparison.  This tolerates punctuation differences (`re-applied` vs `reapplied`) and
/// camelCase word boundaries without requiring an exact derivation algorithm.
///
/// **For `@Test`:** the normalised description must equal the normalised function name.
///
/// **For `@Suite`:** the normalised description must *contain* the normalised type name
/// (after stripping common suffixes like `Tests`, `Test`, `Spec`).  This allows a description
/// like `"TransactionManager: rollback and commit"` to satisfy a type named
/// `TransactionManagerTests` while still requiring some relationship to the type name.
/// For extensions with qualified names (`extension Foo.BarTests`), only the last path
/// component is compared.
///
/// **Does NOT trigger when:**
/// - The attribute has no string-literal description argument.
/// - The description contains string interpolation.
/// - The description or the name normalises to an empty string (e.g. fully non-ASCII).
let testDescriptionMatchesNameRule = ParameterizedRule(
    id: "test-description-matches-name",
    defaultArguments: TestDescriptionMatchesNameArgs(),
) { file, context, args in
    let visitor = TestDescriptionMatchesNameVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class TestDescriptionMatchesNameVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: @Test — function declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // @Test/@Suite declarations cannot be nested inside function bodies,
        // so there is never anything to check below this node.
        checkTest(node)
        return .skipChildren
    }

    private func checkTest(_ node: FunctionDeclSyntax) {
        guard let description = node.attributes.attribute(named: "Test")?.plainStringArgument else {
            return
        }
        let normDesc = normalize(description)
        guard !normDesc.isEmpty else { return }

        let funcName = node.name.text
        if normDesc != normalize(funcName) {
            context.report(
                on: node,
                message: """
                @Test description "\(description)" does not match function name "\(funcName)". \
                The description should describe exactly what "\(funcName)" tests.
                """,
                severity: severity,
            )
        }
    }

    // MARK: @Suite — type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuite(attributes: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuite(attributes: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkSuite(attributes: node.attributes, typeName: node.name.text, reportNode: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Use only the last path component of qualified names ("Foo.BarTests" -> "BarTests").
        // Computed lazily so extensions without @Suite never pay for the tree print.
        checkSuite(
            attributes: node.attributes,
            typeName: lastPathComponent(of: node.extendedType.trimmedDescription),
            reportNode: Syntax(node),
        )
        return .visitChildren
    }

    // MARK: - Core logic

    private func checkSuite(
        attributes: AttributeListSyntax,
        typeName: @autoclosure () -> String,
        reportNode: Syntax,
    ) {
        guard let description = attributes.attribute(named: "Suite")?.plainStringArgument else {
            return
        }
        let normDesc = normalize(description)
        guard !normDesc.isEmpty else { return }

        let typeName = typeName()
        let baseName = strippedTestSuiteName(typeName)
        let normBase = normalize(baseName)
        guard !normBase.isEmpty else { return }

        if !normDesc.contains(normBase) {
            context.report(
                on: reportNode,
                message: """
                @Suite description "\(description)" does not correspond to type name "\(typeName)". \
                The description should identify what "\(baseName)" covers, \
                e.g. "@Suite(\\"\(baseName): <what this suite tests>\\")".
                """,
                severity: severity,
            )
        }
    }

    // MARK: - Helpers

    /// Keeps only ASCII letters and digits, lowercased. Non-ASCII text normalizes
    /// to an empty string, which callers treat as "cannot compare — skip".
    private func normalize(_ s: String) -> String {
        s.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.lowercased()
    }

    private func lastPathComponent(of qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }
}
