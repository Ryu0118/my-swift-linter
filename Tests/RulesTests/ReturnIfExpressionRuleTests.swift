@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct ReturnIfExpressionRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "return-if-expression"))
    }

    // MARK: - Violations

    @Test("warning on simple if/else with return in each branch")
    func simpleIfElse() async {
        let source = """
        func foo(_ x: Bool) -> String {
            if x {
                return "yes"
            } else {
                return "no"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("warning on if/else-if/else chain")
    func ifElseIfElse() async {
        let source = """
        func label(_ n: Int) -> String {
            if n < 0 {
                return "negative"
            } else if n == 0 {
                return "zero"
            } else {
                return "positive"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on three-clause else-if chain")
    func threeElseIf() async {
        let source = """
        func grade(_ s: Int) -> String {
            if s >= 90 {
                return "A"
            } else if s >= 80 {
                return "B"
            } else if s >= 70 {
                return "C"
            } else {
                return "D"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on motivating time-formatting pattern (func)")
    func timeFormattingPatternFunc() async {
        let source = """
        func formatSeconds(_ seconds: Int) -> String {
            if seconds >= 60, seconds % 60 == 0 {
                return "\\(seconds / 60)m"
            } else if seconds >= 60 {
                return "\\(seconds / 60)m \\(seconds % 60)s"
            } else {
                return "\\(seconds)s"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on motivating time-formatting pattern (computed property)")
    func timeFormattingPatternComputedProperty() async {
        let source = """
        struct S {
            var interval: Double = 90
            var label: String {
                let seconds = Int(interval)
                if seconds >= 60, seconds % 60 == 0 {
                    return "\\(seconds / 60)m"
                } else if seconds >= 60 {
                    return "\\(seconds / 60)m \\(seconds % 60)s"
                } else {
                    return "\\(seconds)s"
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on if with conditional binding")
    func conditionalBinding() async {
        let source = """
        func f(_ x: Int?) -> String {
            if let v = x {
                return "some: \\(v)"
            } else {
                return "none"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - False positives (must NOT fire)

    @Test("no warning when terminal else is missing")
    func missingTerminalElse() async {
        let source = """
        func f(_ x: Bool) -> String {
            if x {
                return "yes"
            }
            return "no"
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when a branch has bare return")
    func bareReturn() async {
        let source = """
        func f(_ x: Bool) {
            if x {
                return
            } else {
                return
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when a branch has multiple statements")
    func multiStatementBranch() async {
        let source = """
        func f(_ x: Bool) -> Int {
            if x {
                print("x")
                return 1
            } else {
                return 0
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when if is already on RHS of return")
    func alreadyReturnIfForm() async {
        let source = """
        func f(_ x: Bool) -> String {
            return if x { "yes" } else { "no" }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when else-if chain has no terminal else")
    func elseIfWithoutTerminalElse() async {
        let source = """
        func f(_ x: Int) -> String {
            if x > 0 {
                return "pos"
            } else if x < 0 {
                return "neg"
            }
            return "zero"
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when a branch has no return at all")
    func branchWithoutReturn() async {
        let source = """
        func f(_ x: Bool) -> Int {
            if x {
                let _ = 1
            } else {
                return 0
            }
            return 1
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Fix-it

    @Test("fix-it rewrites simple if/else to return-if-expression")
    func fixSimpleIfElse() async throws {
        let source = """
        func f(_ x: Bool) -> String {
            if x {
                return "yes"
            } else {
                return "no"
            }
        }
        """
        let (diagnostics, fixed) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        let fixedSource = try #require(fixed)
        #expect(fixedSource.contains("return if x"))
        #expect(fixedSource.contains("\"yes\""))
        #expect(fixedSource.contains("\"no\""))
        #expect(!fixedSource.contains("return \"yes\""))
        #expect(!fixedSource.contains("return \"no\""))
    }

    @Test("fix-it rewrites if/else-if/else to return-if-expression")
    func fixIfElseIfElse() async throws {
        let source = """
        func f(_ n: Int) -> String {
            if n < 0 {
                return "negative"
            } else if n == 0 {
                return "zero"
            } else {
                return "positive"
            }
        }
        """
        let (diagnostics, fixed) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        let fixedSource = try #require(fixed)
        #expect(fixedSource.contains("return if n < 0"))
        #expect(fixedSource.contains("\"negative\""))
        #expect(fixedSource.contains("\"zero\""))
        #expect(fixedSource.contains("\"positive\""))
    }

    @Test("fix-it produces valid return-if for motivating time-formatting pattern")
    func fixTimeFormattingPattern() async throws {
        let source = """
        func formatSeconds(_ s: Int) -> String {
            if s >= 60, s % 60 == 0 {
                return "\\(s / 60)m"
            } else if s >= 60 {
                return "\\(s / 60)m \\(s % 60)s"
            } else {
                return "\\(s)s"
            }
        }
        """
        let (diagnostics, fixed) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        let fixedSource = try #require(fixed)
        #expect(fixedSource.contains("return if"))
        #expect(!fixedSource.contains("return \"\\(s / 60)m\""))
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("single-line file with no if produces no diagnostics")
    func singleLine() async {
        let diagnostics = await rule.lint(source: "let x = 1\n")
        #expect(diagnostics.isEmpty)
    }

    @Test("multiple qualifying if/else blocks each produce one warning")
    func multipleBlocks() async {
        let source = """
        func a(_ x: Bool) -> String {
            if x {
                return "a"
            } else {
                return "b"
            }
        }
        func b(_ x: Bool) -> String {
            if x {
                return "c"
            } else {
                return "d"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }
}
