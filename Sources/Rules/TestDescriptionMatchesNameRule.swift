import SwiftASTLint
import SwiftSyntax

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
///
/// **Does NOT trigger when:**
/// - The attribute has no string-literal description argument.
/// - The description contains string interpolation.
/// - The description normalises to an empty string.
struct TestDescriptionMatchesNameArgs: Codable, Sendable {
    var severity: Severity = .error
}

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
        guard hasAttribute(node.attributes, named: "Test") else { return .visitChildren }
        guard let description = extractStringLiteral(from: node.attributes, named: "Test") else {
            return .visitChildren
        }
        let normDesc = normalize(description)
        guard !normDesc.isEmpty else { return .visitChildren }

        let funcName = node.name.text
        let normName = normalize(funcName)

        if normDesc != normName {
            context.report(
                on: node,
                message: """
                @Test description "\(description)" does not match function name "\(funcName)". \
                The description should describe exactly what "\(funcName)" tests.
                """,
                severity: severity,
            )
        }
        return .visitChildren
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
        let typeName = node.extendedType.trimmedDescription
        checkSuite(attributes: node.attributes, typeName: typeName, reportNode: Syntax(node))
        return .visitChildren
    }

    // MARK: - Core logic

    private func checkSuite(attributes: AttributeListSyntax, typeName: String, reportNode: Syntax) {
        guard hasAttribute(attributes, named: "Suite") else { return }
        guard let description = extractStringLiteral(from: attributes, named: "Suite") else { return }
        let normDesc = normalize(description)
        guard !normDesc.isEmpty else { return }

        // Strip common test-suite suffixes to get the base name, then normalize.
        // When stripping leaves nothing (type named exactly "Tests"/"Test"/"Spec"),
        // fall back to the full type name so the comparison stays meaningful.
        var baseName = strippedTypeName(typeName)
        if baseName.isEmpty { baseName = typeName }
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

    /// Returns true when `attributes` contains an attribute with the given simple name.
    private func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attr) = element else { return false }
            guard let id = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return id.name.text == name
        }
    }

    /// Extracts the first plain string-literal argument from the named attribute.
    /// Returns `nil` for interpolated strings, non-string arguments, or missing arguments.
    private func extractStringLiteral(from attributes: AttributeListSyntax, named name: String) -> String? {
        for element in attributes {
            guard case let .attribute(attr) = element else { continue }
            guard let id = attr.attributeName.as(IdentifierTypeSyntax.self),
                  id.name.text == name
            else { continue }
            guard case let .argumentList(args) = attr.arguments else { return nil }
            for arg in args {
                guard let stringLit = arg.expression.as(StringLiteralExprSyntax.self) else { continue }
                let segments = stringLit.segments
                guard segments.count == 1,
                      let first = segments.first,
                      case let .stringSegment(seg) = first
                else { return nil }
                return seg.content.text
            }
            return nil
        }
        return nil
    }

    /// Removes all characters except ASCII letters and digits, then lowercases.
    private func normalize(_ s: String) -> String {
        s.unicodeScalars
            .filter { $0.value < 128 && (isASCIILetter($0.value) || isASCIIDigit($0.value)) }
            .map { Character($0) }
            .map { $0.lowercased() }
            .joined()
    }

    private func isASCIILetter(_ v: UInt32) -> Bool {
        (65...90).contains(v) || (97...122).contains(v)
    }

    private func isASCIIDigit(_ v: UInt32) -> Bool {
        (48...57).contains(v)
    }

    /// Returns the type name with common test-suite suffixes stripped.
    private func strippedTypeName(_ name: String) -> String {
        for suffix in ["Tests", "Test", "Spec"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}
