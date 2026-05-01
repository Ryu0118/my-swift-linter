@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("meaningful-suite-description: detects @Suite descriptions that duplicate the type name")
struct MeaningfulSuiteDescriptionRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "meaningful-suite-description"))
    }

    // MARK: - Violations

    @Test("error when Suite description matches struct name exactly")
    func exactMatchStruct() async {
        let source = """
        import Testing
        @Suite("MyFeature")
        struct MyFeature {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when Suite description equals struct name minus Tests suffix")
    func matchWithTestsSuffix() async {
        let source = """
        import Testing
        @Suite("CheckRunner")
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when Suite description equals struct name minus Test suffix")
    func matchWithTestSuffix() async {
        let source = """
        import Testing
        @Suite("Validator")
        struct ValidatorTest {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when Suite description equals struct name minus Spec suffix")
    func matchWithSpecSuffix() async {
        let source = """
        import Testing
        @Suite("Parser")
        struct ParserSpec {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error on class with redundant Suite description")
    func redundantDescriptionOnClass() async {
        let source = """
        import Testing
        @Suite("NetworkClient")
        class NetworkClientTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error on actor with redundant Suite description")
    func redundantDescriptionOnActor() async {
        let source = """
        import Testing
        @Suite("Cache")
        actor CacheTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error on extension with redundant Suite description")
    func redundantDescriptionOnExtension() async {
        let source = """
        import Testing
        @Suite("Store")
        extension StoreTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("multiple redundant suites in one file each produce an error")
    func multipleViolations() async {
        let source = """
        import Testing
        @Suite("CheckResult")
        struct CheckResultTests {}
        @Suite("CheckRunner")
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - No violations (must NOT fire)

    @Test("no error when description follows rule-id: what it checks pattern")
    func meaningfulRuleStyleDescription() async {
        let source = """
        import Testing
        @Suite("meaningful-suite-description: detects @Suite descriptions that duplicate the type name")
        struct MeaningfulSuiteDescriptionRuleTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description is a human-readable sentence")
    func humanReadableDescription() async {
        let source = """
        import Testing
        @Suite("URL parsing: handles percent-encoded paths and query strings")
        struct URLParserTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has no description argument (trait-only)")
    func noDescriptionArgument() async {
        let source = """
        import Testing
        @Suite(.serialized)
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has no arguments at all")
    func noArguments() async {
        let source = """
        import Testing
        @Suite
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when struct has no @Suite attribute")
    func noSuiteAttribute() async {
        let source = """
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description starts with struct name but is longer")
    func descriptionStartsWithButLonger() async {
        let source = """
        import Testing
        @Suite("CheckRunner: validates sequential execution order")
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description is a partial substring of the type name")
    func partialSubstring() async {
        let source = """
        import Testing
        @Suite("Check")
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description has different casing from type name")
    func differentCasing() async {
        let source = """
        import Testing
        @Suite("checkrunner")
        struct CheckRunnerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when Suite description uses string interpolation")
    func stringInterpolation() async {
        let source = #"""
        import Testing
        let name = "Runner"
        @Suite("Check\(name)")
        struct CheckRunnerTests {}
        """#
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
