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

    @Test("error for mismatched @Test description and func name", arguments: [
        ("user can log in", "fetchData"),
        ("returns nil value", "computeSum"),
        ("back rolled be can transaction applied re a", "aReappliedTransactionCanBeRolledBackAgain"),
    ])
    func mismatchedDescriptionAndName(description: String, funcName: String) {
        let source = """
        import Testing
        struct MyTests {
            @Test("\(description)")
            func \(funcName)() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error message includes both description and func name")
    func errorMessageContainsDescriptionAndName() {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("user can log in"))
        #expect(diagnostics[0].message.contains("fetchData"))
    }

    @Test("multiple mismatched @Test functions each produce an error")
    func multipleViolations() {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in")
            func fetchData() {}
            @Test("returns nil value")
            func computeSum() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("error when @Test at file scope has mismatched description")
    func topLevelMismatch() {
        let source = """
        import Testing
        @Test("user can log in")
        func fetchData() {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when description string comes after a trait argument")
    func descriptionAfterTraitArgument() {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized, "user can log in")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when @Test description matches but is on a parameterized test with wrong name")
    func parameterizedTestMismatch() {
        let source = """
        import Testing
        struct MyTests {
            @Test("user can log in", arguments: [1, 2, 3])
            func fetchData(_ value: Int) {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - No violations (@Test) — must NOT fire

    @Test("no error for matching pairs", arguments: [
        // The motivating example: hyphen in "re-applied" normalizes away on both sides.
        ("A re-applied transaction can be rolled back again", "aReappliedTransactionCanBeRolledBackAgain"),
        ("claudeHookOutput blocks when outOfSync", "claudeHookOutputBlocksWhenOutOfSync"),
        ("user's data is fetched", "userSDataIsFetched"),
        ("test 3 cases are handled", "test3CasesAreHandled"),
    ])
    func matchingPairs(description: String, funcName: String) {
        let source = """
        import Testing
        struct MyTests {
            @Test("\(description)")
            func \(funcName)() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error on matching parameterized test with arguments label")
    func parameterizedTestMatch() {
        let source = """
        import Testing
        struct MyTests {
            @Test("handles all edge cases", arguments: [1, 2, 3])
            func handlesAllEdgeCases(_ value: Int) {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has no string description (bare attribute)")
    func noDescription() {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has only trait arguments and no string description")
    func traitOnlyNoDescription() {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized)
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test description contains interpolation")
    func interpolatedDescription() {
        let source = """
        import Testing
        struct MyTests {
            @Test("value is \\(42)")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when description is entirely non-ASCII (normalizes to empty, skipped)")
    func nonASCIIDescriptionSkipped() {
        // Japanese descriptions normalize to an empty string; the rule cannot
        // meaningfully compare them, so it must skip rather than flag.
        let source = """
        import Testing
        struct MyTests {
            @Test("ログインできる")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("non-test function with similar description is ignored")
    func nonTestFunctionIgnored() {
        let source = """
        struct MyType {
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("empty file produces no diagnostics")
    func emptyFile() {
        let diagnostics = rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("empty string description is skipped without error")
    func emptyStringDescription() {
        let source = """
        import Testing
        struct MyTests {
            @Test("")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Violations (@Suite)

    @Test("error when @Suite description is unrelated to type name, with both names in the message")
    func suiteDescriptionUnrelatedToTypeName() {
        let source = """
        import Testing
        @Suite("completely unrelated description")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].message.contains("completely unrelated description"))
        #expect(diagnostics[0].message.contains("TransactionManagerTests"))
    }

    @Test("error when type is named exactly 'Tests' and description is unrelated")
    func bareTestsTypeNameStillChecked() {
        // Stripping the "Tests" suffix leaves an empty base name; the rule must
        // fall back to the full type name instead of matching everything via
        // contains("") == true.
        let source = """
        import Testing
        @Suite("completely unrelated description")
        struct Tests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when nested @Suite type has unrelated description")
    func nestedSuiteMismatch() {
        let source = """
        import Testing
        struct OuterTests {
            @Suite("completely unrelated")
            struct InnerTests {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("@Suite and @Test mismatches in the same type each produce an error")
    func suiteAndTestBothMismatch() {
        let source = """
        import Testing
        @Suite("completely unrelated")
        struct TransactionManagerTests {
            @Test("also unrelated")
            func fetchData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - No violations (@Suite)

    @Test("no error when @Suite extension has qualified type name and description names the last component")
    func suiteExtensionQualifiedName() {
        // "Foo.BarTests" must compare against "Bar", not "FooBar".
        let source = """
        import Testing
        @Suite("Bar: integration scenarios")
        extension Foo.BarTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description contains the type name (minus Tests suffix)")
    func suiteDescriptionContainsTypeName() {
        let source = """
        import Testing
        @Suite("TransactionManager: rollback and commit behavior")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description normalizes to match type name")
    func suiteDescriptionNormalizesToTypeName() {
        let source = """
        import Testing
        @Suite("transaction manager")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when type named 'Tests' has description containing 'Tests'")
    func bareTestsTypeNameWithMatchingDescription() {
        let source = """
        import Testing
        @Suite("Tests: shared linter fixtures")
        struct Tests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has no description argument")
    func suiteNoDescription() {
        let source = """
        import Testing
        @Suite
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite has only trait arguments")
    func suiteTraitOnly() {
        let source = """
        import Testing
        @Suite(.serialized)
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description contains interpolation")
    func suiteInterpolatedDescription() {
        let source = """
        import Testing
        @Suite("TransactionManager \\(version)")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite description is entirely non-ASCII (skipped)")
    func suiteNonASCIIDescriptionSkipped() {
        let source = """
        import Testing
        @Suite("トランザクション管理のテスト")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
