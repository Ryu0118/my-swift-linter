import SwiftASTLint
import SwiftSyntax

struct TestDescriptionDuplicatesNameArgs: Codable, Sendable {
    var severity: Severity = .error
}

/// Detects `@Test` functions and `@Suite` types whose display description is merely a
/// mechanical restatement of the function/type name and therefore adds no information.
///
/// A description exists to explain *what* a test verifies in words a human reads more easily
/// than the identifier. When the description is just the camelCase name spelled out with spaces
/// (`successWithAllSelectedShowsEmpty` → `"success with all selected shows empty"`), it duplicates
/// the name and should either be removed or rewritten as a meaningful explanation.
///
/// **Matching strategy:** Both the description and the name are *normalized* — Unicode letters
/// and digits are kept, everything else (spaces, punctuation) is removed, and the result is
/// lowercased — before comparison. This tolerates punctuation and camelCase word boundaries
/// (`re-applied` vs `reapplied`) while preserving non-ASCII content so that a description
/// containing Japanese (or any non-ASCII letters) can never normalize to an ASCII-only name.
///
/// **For `@Test`:** the rule fires when the normalized description *equals* the normalized
/// function name — i.e. the description is a pure restatement of the name with no added meaning.
///
/// **For `@Suite`:** the rule fires when the normalized description equals the normalized type
/// name, either with common test suffixes (`Tests`, `Test`, `Spec`) stripped or intact. A
/// description that names the type *and adds detail* (`"TransactionManager: rollback and commit"`)
/// contributes information and is allowed. For extensions with qualified names
/// (`extension Foo.BarTests`), only the last path component is compared.
///
/// **Does NOT trigger when:**
/// - The attribute has no string-literal description argument.
/// - The description contains string interpolation.
/// - The description or the name normalizes to an empty string.
/// - The description is a meaningful explanation that differs from the name — including any
///   description containing non-ASCII letters, which by construction cannot equal an ASCII name.
let testDescriptionDuplicatesNameRule = ParameterizedRule(
    id: "test-description-duplicates-name",
    defaultArguments: TestDescriptionDuplicatesNameArgs(),
) { file, context, args in
    let visitor = TestDescriptionDuplicatesNameVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class TestDescriptionDuplicatesNameVisitor: SyntaxVisitor {
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
        if normDesc == normalize(funcName) {
            context.report(
                on: node,
                message: """
                @Test description "\(description)" is just a restatement of function name "\(funcName)". \
                Remove the description or rewrite it to explain what "\(funcName)" verifies.
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
        let normFull = normalize(typeName)
        guard !normFull.isEmpty else { return }

        let baseName = strippedTestSuiteName(typeName)
        let normBase = normalize(baseName)

        // Fire only when the description restates the type name verbatim, with or without the
        // test suffix. A description that names the type *and adds detail* is longer than either
        // normalization and is therefore allowed.
        if normDesc == normFull || (!normBase.isEmpty && normDesc == normBase) {
            context.report(
                on: reportNode,
                message: """
                @Suite description "\(description)" is just a restatement of type name "\(typeName)". \
                Remove the description or add detail about what "\(baseName)" covers, \
                e.g. "@Suite(\\"\(baseName): <what this suite tests>\\")".
                """,
                severity: severity,
            )
        }
    }

    // MARK: - Helpers

    /// Keeps Unicode letters and digits, lowercased, dropping spaces and punctuation.
    /// Non-ASCII letters are preserved, so a description containing them can never
    /// normalize to an ASCII-only identifier and thus never falsely counts as a restatement.
    private func normalize(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    private func lastPathComponent(of qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }
}
