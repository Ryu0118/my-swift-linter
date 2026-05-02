@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct TestFunctionNamingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "test-function-naming"))
    }

    // MARK: - Violations

    @Test("error when @Test function name is backtick-quoted")
    func backtickQuotedTestFunction() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `claudeHookOutput blocks when outOfSync`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when @Test function has description but name is still backtick-quoted")
    func backtickQuotedWithDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("some description")
            func `claudeHookOutput blocks when outOfSync`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when @Test function at file scope has backtick-quoted name")
    func backtickQuotedTopLevel() async {
        let source = """
        import Testing
        @Test
        func `something happens here`() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("multiple backtick-quoted @Test functions each produce an error")
    func multipleViolations() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `first case`() {}
            @Test
            func `second case`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - No violations (must NOT fire)

    @Test("no error when @Test has lowerCamelCase name and description argument")
    func lowerCamelCaseWithDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("claudeHookOutput blocks when outOfSync")
            func claudeHookOutputBlocksWhenOutOfSync() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has lowerCamelCase name without description")
    func lowerCamelCaseNoDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func claudeHookOutputBlocksWhenOutOfSync() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when backtick-quoted function has no @Test attribute")
    func backtickQuotedNonTestFunction() async {
        let source = """
        struct MyTests {
            func `some helper`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when regular function uses backtick for Swift keyword escaping")
    func backtickKeywordEscaping() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `default`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error on non-test function with lowerCamelCase name")
    func nonTestFunction() async {
        let source = """
        struct MyType {
            func computeValue() -> Int { 42 }
        }
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

    @Test("@Test with only trait arguments and backtick name is still a violation")
    func backtickWithTraitOnly() async {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized)
            func `does something important`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }
}
