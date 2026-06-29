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

    // MARK: - Violations (underscore-separated names)

    @Test("error when @Test function name is underscore-separated")
    func underscoreSeparatedName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func あいうえお_かきくけこ_() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when @Test function name has a single underscore separator")
    func singleUnderscoreName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func decode_returnsValue() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - Violations (test prefix)

    @Test("error when @Test function name starts with lowercase test prefix")
    func lowercaseTestPrefix() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func testHogeFuga() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when @Test function name is exactly 'test'")
    func exactlyTest() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func test() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when @Test function name is a lowercase word starting with test (e.g. testing)")
    func lowercaseWordStartingWithTest() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func testing() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - Dedup (a name matching multiple patterns reports once)

    @Test("a name matching multiple patterns produces only one diagnostic")
    func multiplePatternsReportOnce() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `test case`() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - No violations (must NOT fire)

    @Test("no error when test appears in the middle of a lowerCamelCase name")
    func testInMiddleOfName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func validateTestInput() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when underscore-separated name has no @Test attribute")
    func underscoreNonTestFunction() async {
        let source = """
        struct MyType {
            func some_helper_function() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when test-prefixed name has no @Test attribute")
    func testPrefixNonTestFunction() async {
        let source = """
        struct MyType {
            func testHelper() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
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

    // MARK: - YAML args (partial overrides must decode without resetting other fields)

    @Test("partial args YAML overrides severity to warning")
    func severityOverrideToWarning() async {
        let source = """
        import Testing
        struct MyTests {
            @Test func testHogeFuga() {}
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "severity: warning\n")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("check_test_prefix=false disables only the test-prefix pattern")
    func disableTestPrefixToggle() async {
        let source = """
        import Testing
        struct MyTests {
            @Test func testHogeFuga() {}
            @Test func decode_returnsValue() {}
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "check_test_prefix: false\n")
        // test-prefix suppressed; underscore pattern still fires.
        #expect(diagnostics.count == 1)
    }

    @Test("check_underscores=false disables only the underscore pattern")
    func disableUnderscoreToggle() async {
        let source = """
        import Testing
        struct MyTests {
            @Test func testHogeFuga() {}
            @Test func decode_returnsValue() {}
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "check_underscores: false\n")
        // underscore suppressed; test-prefix still fires.
        #expect(diagnostics.count == 1)
    }

    @Test("check_spaces=false disables only the spaces pattern")
    func disableSpacesToggle() async {
        let source = """
        import Testing
        struct MyTests {
            @Test func `does a thing`() {}
            @Test func testHogeFuga() {}
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "check_spaces: false\n")
        // backtick-phrase suppressed; test-prefix still fires.
        #expect(diagnostics.count == 1)
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
