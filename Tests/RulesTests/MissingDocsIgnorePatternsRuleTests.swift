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

    // MARK: - namePattern (regex)

    @Test("namePattern suppresses violations for names matching the regex suffix")
    func namePatternSuffixMatch() async {
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            name_pattern: "Reducer$"
        """
        let sources = [
            "public struct HomeReducer {}",
            "public struct AccountListReducer {}",
        ]
        for source in sources {
            let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
            #expect(diagnostics.isEmpty, "Expected no violation for: \(source)")
        }
    }

    @Test("namePattern does not suppress violations for non-matching names")
    func namePatternNoMatch() async {
        let source = "public struct HomeFeature {}"
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            name_pattern: "Reducer$"
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    @Test("namePattern combined with kinds requires both to match")
    func namePatternWithKindMismatch() async {
        // "Reducer$" matches the name, but kind (enum) does not match kinds: [struct]
        let source = "public enum HomeReducer {}"
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            name_pattern: "Reducer$"
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    @Test("namePattern and names are both honored when both are present (OR)")
    func namePatternAndNamesBothPresent() async {
        // "names" allows an exact literal match even when namePattern wouldn't match it,
        // and namePattern allows a regex match even when it isn't in "names".
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            names: [ExactMatch]
            name_pattern: "Reducer$"
        """
        let matchingByName = "public struct ExactMatch {}"
        let matchingByPattern = "public struct HomeReducer {}"
        let matchingNeither = "public struct SomethingElse {}"

        #expect(await rule.lint(source: matchingByName, argsYAML: argsYAML).isEmpty)
        #expect(await rule.lint(source: matchingByPattern, argsYAML: argsYAML).isEmpty)
        #expect(!(await rule.lint(source: matchingNeither, argsYAML: argsYAML).isEmpty))
    }

    @Test("invalid namePattern regex fails safe by not matching (does not crash)")
    func namePatternInvalidRegexFailsSafe() async {
        let source = "public struct HomeReducer {}"
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            name_pattern: "(unclosed"
        """
        let diagnostics = await rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }
}
