@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct BranchAssignmentToTupleRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "branch-assignment-to-tuple"))
    }

    // MARK: - Violations: if/else

    @Test("error when 2 uninitialized lets are assigned in if/else")
    func twoLetsIfElse() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int
            let pages: Int
            if flag {
                days = 7
                pages = 10
            } else {
                days = 30
                pages = 20
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when 3 uninitialized lets are assigned in if/else")
    func threeLetsIfElse() async {
        let source = """
        func foo(x: Bool) {
            let days: Int
            let pages: Int
            let granularity: String
            if x {
                days = 7
                pages = 10
                granularity = "week"
            } else {
                days = 30
                pages = 20
                granularity = "day"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when lets are in a closure body")
    func letsInClosure() async {
        let source = """
        let result = {
            let a: Int
            let b: Int
            if Bool.random() {
                a = 1
                b = 2
            } else {
                a = 3
                b = 4
            }
            return (a, b)
        }()
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Violations: switch

    @Test("error when 2 uninitialized lets are assigned in switch")
    func twoLetsSwitch() async {
        let source = """
        enum Mode { case fast, slow }
        func foo(mode: Mode) {
            let speed: Int
            let label: String
            switch mode {
            case .fast:
                speed = 100
                label = "fast"
            case .slow:
                speed = 10
                label = "slow"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Non-violations

    @Test("error when single uninitialized let is assigned in if/else (use if expression instead)")
    func singleLetIfElse() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int
            if flag {
                days = 7
            } else {
                days = 30
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when single let uses if let condition")
    func singleLetIfLet() async {
        let source = """
        func foo(x: Int?) {
            let hoge: Int
            if let x {
                hoge = x
            } else {
                hoge = 0
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("no warning when lets are initialized at declaration")
    func initializedLetsNoWarning() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int = 7
            let pages: Int = 10
            if flag {
                _ = days
            } else {
                _ = pages
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when branch contains non-assignment statement")
    func branchWithExtraStatementNoWarning() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int
            let pages: Int
            if flag {
                days = 7
                pages = 10
                print("logged")
            } else {
                days = 30
                pages = 20
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when not all variables are assigned in both branches")
    func incompleteAssignmentNoWarning() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int
            let pages: Int
            if flag {
                days = 7
                pages = 10
            } else {
                days = 30
                // pages not assigned
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when if has no else (single branch)")
    func ifWithoutElseNoWarning() async {
        let source = """
        func foo(flag: Bool) {
            let days: Int
            let pages: Int
            if flag {
                days = 7
                pages = 10
            }
            _ = days
            _ = pages
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when else is another if (else if chain)")
    func elseIfChainNoWarning() async {
        let source = """
        func foo(x: Int) {
            let days: Int
            let pages: Int
            if x == 1 {
                days = 7
                pages = 10
            } else if x == 2 {
                days = 14
                pages = 20
            } else {
                days = 30
                pages = 30
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning for var declarations (only let is targeted)")
    func varDeclNoWarning() async {
        let source = """
        func foo(flag: Bool) {
            var days: Int
            var pages: Int
            if flag {
                days = 7
                pages = 10
            } else {
                days = 30
                pages = 20
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning for unrelated code")
    func unrelatedCodeNoWarning() async {
        let source = """
        func foo() {
            let x = 1
            let y = x + 2
            print(y)
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
