@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct MissingDocsIgnorePatternsRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "missing-docs"))
    }

    // MARK: - Full match: kinds + modifiers + names

    @Test("no error for static var/let matching all three fields")
    func ignorePatternFullMatch() async {
        let argsYAML = """
        ignore_patterns:
          - kinds: [var, let]
            modifiers: [static]
            names: [liveValue, previewValue, testValue]
        """
        let sources = [
            "public static var liveValue: Int = 0",
            "public static let liveValue: Int = 0",
            "public static var previewValue: Int = 0",
            "public static var testValue: Int = 0",
        ]
        for source in sources {
            let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
            #expect(diagnostics.isEmpty, "Expected no violation for: \(source)")
        }
    }

    // MARK: - Modifier mismatch

    @Test("error fires when modifier does not match ignore_pattern")
    func ignorePatternModifierMismatch() async {
        // non-static var liveValue should still fire
        let source = "public var liveValue: Int = 0"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Name mismatch

    @Test("error fires when name does not match ignore_pattern")
    func ignorePatternNameMismatch() async {
        let source = "public static var someOther: Int = 0"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Kind mismatch

    @Test("error fires when kind does not match ignore_pattern")
    func ignorePatternKindMismatch() async {
        let source = "public static func liveValue() {}"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Wildcard fields

    @Test("ignore_pattern with only names matches any kind and modifier")
    func ignorePatternNamesOnly() async {
        let source = "public func liveValue() {}"
        let argsYAML = "ignore_patterns:\n  - names: [liveValue]\n"
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(diagnostics.isEmpty)
    }

    @Test("ignore_pattern with only kinds matches any name and modifier")
    func ignorePatternKindsOnly() async {
        let source = "public var anything: Int = 0"
        let argsYAML = "ignore_patterns:\n  - kinds: [var]\n"
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Empty list

    @Test("empty ignore_patterns does not suppress violations")
    func emptyIgnorePatterns() async {
        let source = "public func foo() {}"
        let argsYAML = "ignore_patterns: []\n"
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }
}
