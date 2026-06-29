import SwiftASTLint
import SwiftSyntax

/// Detects `@Test` functions whose name violates Swift Testing naming conventions.
///
/// Three independently-toggleable patterns are checked (all enabled by default):
/// - **Spaces** — a backtick-quoted natural-language phrase
///   (e.g. `` func `foo does bar`() `` ). Use lowerCamelCase and move the
///   description into `@Test("…")` instead.
/// - **Underscores** — an underscore-separated name
///   (e.g. `func あいうえお_かきくけこ_()` or `func decode_returnsValue()`).
/// - **Test prefix** — a name beginning with `test` (case-insensitive), which is
///   redundant on a `@Test` function (e.g. `func testHogeFuga()`, `func testing()`).
///
/// **Triggers when:**
/// - A function is annotated with `@Test` (with or without arguments), AND
/// - Its name matches at least one enabled pattern.
///
/// A name matching multiple patterns is reported exactly once (the first match wins,
/// in the order spaces → underscores → test-prefix).
///
/// **Does NOT trigger when:**
/// - The function name is a backtick-escaped Swift keyword (no spaces, e.g. `` `default` ``)
/// - `test` appears only in the middle of a name (e.g. `validateTestInput`)
/// - The function has no `@Test` attribute
struct TestFunctionNamingArgs: Codable {
    var severity: Severity = .error
    /// Flag backtick-quoted names that contain spaces.
    var checkSpaces: Bool = true
    /// Flag names that contain an underscore.
    var checkUnderscores: Bool = true
    /// Flag names that begin with `test` (case-insensitive).
    var checkTestPrefix: Bool = true

    enum CodingKeys: String, CodingKey {
        case severity
        case checkSpaces = "check_spaces"
        case checkUnderscores = "check_underscores"
        case checkTestPrefix = "check_test_prefix"
    }

    init(
        severity: Severity = .error,
        checkSpaces: Bool = true,
        checkUnderscores: Bool = true,
        checkTestPrefix: Bool = true,
    ) {
        self.severity = severity
        self.checkSpaces = checkSpaces
        self.checkUnderscores = checkUnderscores
        self.checkTestPrefix = checkTestPrefix
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .error
        checkSpaces = try container.decodeIfPresent(Bool.self, forKey: .checkSpaces) ?? true
        checkUnderscores = try container.decodeIfPresent(Bool.self, forKey: .checkUnderscores) ?? true
        checkTestPrefix = try container.decodeIfPresent(Bool.self, forKey: .checkTestPrefix) ?? true
    }
}

let testFunctionNamingRule = ParameterizedRule(
    id: "test-function-naming",
    defaultArguments: TestFunctionNamingArgs(),
) { file, context, args in
    let visitor = TestFunctionNamingVisitor(context: context, args: args)
    visitor.walk(file)
}

// MARK: - Visitor

private final class TestFunctionNamingVisitor: SyntaxVisitor {
    let context: LintContext
    let args: TestFunctionNamingArgs

    init(context: LintContext, args: TestFunctionNamingArgs) {
        self.context = context
        self.args = args
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes) else { return .visitChildren }
        let rawName = node.name.text

        // First matching pattern wins, so a name hitting several patterns is reported once.
        if args.checkSpaces, rawName.contains(" ") {
            report(on: node, message: """
            @Test function name "\(rawName)" uses a backtick-quoted phrase. \
            Use lowerCamelCase and move the description into @Test("…") instead.
            """)
        } else if args.checkUnderscores, rawName.contains("_") {
            report(on: node, message: """
            @Test function name "\(rawName)" is underscore-separated. \
            Use lowerCamelCase instead.
            """)
        } else if args.checkTestPrefix, hasTestPrefix(rawName) {
            report(on: node, message: """
            @Test function name "\(rawName)" starts with "test", which is redundant on a @Test function. \
            Drop the prefix and use lowerCamelCase, e.g. "hogeFuga".
            """)
        }
        return .visitChildren
    }

    // MARK: - Helpers

    private func report(on node: FunctionDeclSyntax, message: String) {
        context.report(on: node, message: message, severity: args.severity)
    }

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attr) = element else { return false }
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return name.name.text == "Test"
        }
    }

    /// Returns true when the name begins with `test` (case-insensitive), regardless of what follows.
    /// Matches `testHogeFuga`, `test_foo`, `testing`, and the exact name `test`.
    private func hasTestPrefix(_ name: String) -> Bool {
        name.lowercased().hasPrefix("test")
    }
}
