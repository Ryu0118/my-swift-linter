@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("test-description-duplicates-name: flags @Test/@Suite descriptions that merely restate the function/type name")
struct TestDescriptionDuplicatesNameRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "test-description-duplicates-name"))
    }

    // MARK: - Violations (@Test) — description is a pure restatement of the name

    @Test("error when @Test description merely restates the func name", arguments: [
        ("success with all selected shows empty", "successWithAllSelectedShowsEmpty"),
        ("handles all edge cases", "handlesAllEdgeCases"),
        ("returns nil value", "returnsNilValue"),
        // Hyphen/punctuation differences normalize away on both sides -> still a restatement.
        ("A re-applied transaction can be rolled back again", "aReappliedTransactionCanBeRolledBackAgain"),
    ])
    func restatedDescriptionAndName(description: String, funcName: String) {
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
            @Test("handles all edge cases")
            func handlesAllEdgeCases() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("handles all edge cases"))
        #expect(diagnostics[0].message.contains("handlesAllEdgeCases"))
    }

    @Test("multiple restating @Test functions each produce an error")
    func multipleViolations() {
        let source = """
        import Testing
        struct MyTests {
            @Test("fetches data")
            func fetchesData() {}
            @Test("computes sum")
            func computesSum() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("error when @Test at file scope restates the name")
    func topLevelRestatement() {
        let source = """
        import Testing
        @Test("fetches data")
        func fetchesData() {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when a restating description follows a trait argument")
    func descriptionAfterTraitArgument() {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized, "fetches data")
            func fetchesData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when a parameterized test restates the name")
    func parameterizedTestRestatement() {
        let source = """
        import Testing
        struct MyTests {
            @Test("handles all edge cases", arguments: [1, 2, 3])
            func handlesAllEdgeCases(_ value: Int) {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - No violations (@Test) — description adds meaning or is non-ASCII

    @Test("no error when @Test description is a meaningful explanation, not a restatement", arguments: [
        // Meaningful English that differs from the identifier.
        ("user can log in", "fetchData"),
        ("Malformed JSON should fail gracefully", "decodesInvalidPayload"),
        // Japanese description: preserved by normalize, can never equal the ASCII name.
        ("ログインできる", "canLogIn"),
        // Japanese + ASCII digits/acronym: normalize keeps the Japanese, so no false match.
        ("既知の入力に対する正しいSHA256ハッシュを生成する", "sha256"),
        ("UTF-8文字列のSHA256ハッシュを正しく生成する", "sha256HandlesUTF8Strings"),
    ])
    func meaningfulDescription(description: String, funcName: String) {
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

    @Test("no error when description is entirely non-ASCII (preserved, cannot equal ASCII name)")
    func nonASCIIDescriptionAllowed() {
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

    @Test("non-test function with a name-like description is ignored")
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

    // MARK: - Violations (@Suite) — description restates the type name verbatim

    @Test("error when @Suite description restates the type name minus the Tests suffix")
    func suiteDescriptionRestatesBaseName() {
        let source = """
        import Testing
        @Suite("transaction manager")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].message.contains("transaction manager"))
        #expect(diagnostics[0].message.contains("TransactionManagerTests"))
    }

    @Test("error when @Suite description restates the full type name including the suffix")
    func suiteDescriptionRestatesFullName() {
        let source = """
        import Testing
        @Suite("Transaction Manager Tests")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when a nested @Suite type restates its name")
    func nestedSuiteRestatement() {
        let source = """
        import Testing
        struct OuterTests {
            @Suite("inner")
            struct InnerTests {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("@Suite and @Test restatements in the same type each produce an error")
    func suiteAndTestBothRestate() {
        let source = """
        import Testing
        @Suite("transaction manager")
        struct TransactionManagerTests {
            @Test("fetches data")
            func fetchesData() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("error when a @Suite extension with a qualified name restates the last component")
    func suiteExtensionQualifiedRestatement() {
        // "Foo.BarTests" compares against "Bar", not "FooBar".
        let source = """
        import Testing
        @Suite("bar")
        extension Foo.BarTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - No violations (@Suite) — description adds detail or is non-ASCII

    @Test("no error when @Suite description names the type and adds detail")
    func suiteDescriptionAddsDetail() {
        let source = """
        import Testing
        @Suite("TransactionManager: rollback and commit behavior")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Suite extension description adds detail beyond the last component")
    func suiteExtensionAddsDetail() {
        let source = """
        import Testing
        @Suite("Bar: integration scenarios")
        extension Foo.BarTests {}
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

    @Test("no error when @Suite description is entirely non-ASCII (preserved, cannot equal ASCII name)")
    func suiteNonASCIIDescriptionAllowed() {
        let source = """
        import Testing
        @Suite("トランザクション管理のテスト")
        struct TransactionManagerTests {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
