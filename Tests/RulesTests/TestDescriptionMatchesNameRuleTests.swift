@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("test-description-matches-name: detects @Test/@Suite descriptions that do not correspond to the function/type name")
struct TestDescriptionMatchesNameRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "test-description-matches-name"))
    }

    // MARK: - Violations (@Test)

    @Test("error when @Test description and func name are unrelated")
    func unrelatedDescriptionAndName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in")
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error message includes both description and func name")
    func errorMessageContainsDescriptionAndName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in")
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("user can log in"))
        #expect(diagnostics[0].message.contains("fetchData"))
    }

    @Test("error when @Test description words are completely reordered")
    func reorderedWords() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("back rolled be can transaction applied re a")
            func aReappliedTransactionCanBeRolledBackAgain() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("multiple mismatched @Test functions each produce an error")
    func multipleViolations() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in")
            func fetchData() {}
            @Test("returns nil value")
            func computeSum() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("error when @Test at file scope has mismatched description")
    func topLevelMismatch() async {
        let source = """
        import Testing
        @Test("user can log in")
        func fetchData() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - No violations (@Test) — must NOT fire

    @Test("no error for motivating example: re-applied with hyphen normalized")
    func motivatingExample() async {
        // The description "A re-applied transaction can be rolled back again"
        // normalizes to "areappliedtransactioncanberolledbackagain"
        // The func name "aReappliedTransactionCanBeRolledBackAgain"
        // normalizes to "areappliedtransactioncanberolledbackagain" — match!
        let source = """
        import Testing
        struct MyTests {
            @Test("A re-applied transaction can be rolled back again")
            func aReappliedTransactionCanBeRolledBackAgain() async throws {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description and func name match (camelCase)")
    func matchingDescriptionAndName() async {
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

    @Test("no error when description uses apostrophe as punctuation")
    func apostropheInDescription() async {
        // "user's data is fetched" -> "usersdataisfetched"
        // "userSDataIsFetched" -> "usersdataisfetched"
        let source = """
        import Testing
        struct MyTests {
            @Test("user's data is fetched")
            func userSDataIsFetched() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has no string description (bare attribute)")
    func noDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has only trait arguments and no string description")
    func traitOnlyNoDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized)
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test description contains interpolation")
    func interpolatedDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("value is \\(42)")
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description contains numbers matching func name")
    func numberInDescriptionAndName() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("test 3 cases are handled")
            func test3CasesAreHandled() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("non-test function with similar description is ignored")
    func nonTestFunctionIgnored() async {
        let source = """
        struct MyType {
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("empty string description is skipped without error")
    func emptyStringDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("")
            func fetchData() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Violations (@Suite)

    @Test("error when @Suite description is unrelated to type name")
    func suiteDescriptionUnrelatedToTypeName() async {
        let source = """
        import Testing
        @Suite("completely unrelated description")
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error message for @Suite includes description and type name")
    func suiteErrorMessageContent() async {
        let source = """
        import Testing
        @Suite("completely unrelated description")
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("completely unrelated description"))
        #expect(diagnostics[0].message.contains("TransactionManagerTests"))
    }

    // MARK: - No violations (@Suite)

    @Test("no error when @Suite description contains the type name (minus Tests suffix)")
    func suiteDescriptionContainsTypeName() async {
        let source = """
        import Testing
        @Suite("TransactionManager: rollback and commit behavior")
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description normalizes to match type name")
    func suiteDescriptionNormalizesToTypeName() async {
        let source = """
        import Testing
        @Suite("transaction manager")
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has no description argument")
    func suiteNoDescription() async {
        let source = """
        import Testing
        @Suite
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has only trait arguments")
    func suiteTraitOnly() async {
        let source = """
        import Testing
        @Suite(.serialized)
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description contains interpolation")
    func suiteInterpolatedDescription() async {
        let source = """
        import Testing
        @Suite("TransactionManager \\(version)")
        struct TransactionManagerTests {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
