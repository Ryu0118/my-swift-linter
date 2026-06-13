@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct ReturnSwitchExpressionRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "return-switch-expression"))
    }

    // MARK: - Violations

    @Test("error on switch with return in every case")
    func simpleSwitch() async {
        let source = """
        func mappedValue(_ input: Input) -> Int {
            switch input {
            case .first:
                return 1
            case .second:
                return 2
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error on switch with more than two cases")
    func moreThanTwoCases() async {
        let source = """
        func priority(for status: Status) -> Int {
            switch status {
            case .blocked:
                return 0
            case .ready:
                return 1
            case .done:
                return 2
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error on switch with multiple patterns in one case")
    func multiplePatternsInCase() async {
        let source = """
        func symbol(for direction: Direction) -> String {
            switch direction {
            case .north, .up:
                return "up"
            case .south, .down:
                return "down"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error on switch with where clauses")
    func whereClauses() async {
        let source = """
        func label(for score: Int) -> String {
            switch score {
            case let value where value < 0:
                return "negative"
            case 0:
                return "zero"
            default:
                return "positive"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error on switch with default case")
    func defaultCase() async {
        let source = """
        func label(_ value: Int) -> String {
            switch value {
            case 0:
                return "zero"
            default:
                return "other"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error in computed property")
    func computedProperty() async {
        let source = """
        struct StatusViewModel {
            var title: String {
                switch state {
                case .loading:
                    return "Loading"
                case .ready:
                    return "Ready"
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - False positives

    @Test("no warning when a case has multiple statements")
    func multiStatementCase() async {
        let source = """
        func label(_ value: Int) -> String {
            switch value {
            case 0:
                print("zero")
                return "zero"
            default:
                return "other"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when a case has bare return")
    func bareReturn() async {
        let source = """
        func perform(_ value: Int) {
            switch value {
            case 0:
                return
            default:
                return
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when switch is already returned")
    func alreadyReturnSwitchForm() async {
        let source = """
        func label(_ value: Int) -> String {
            return switch value {
            case 0:
                "zero"
            default:
                "other"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when a case contains a non-return expression")
    func nonReturnCase() async {
        let source = """
        func label(_ value: Int) -> String {
            switch value {
            case 0:
                "zero"
            default:
                return "other"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Fix-it

    @Test("fix-it rewrites switch returns to return-switch-expression")
    func fixSimpleSwitch() async throws {
        let source = """
        func mappedValue(_ input: Input) -> Int {
            switch input {
            case .first:
                return 1
            case .second:
                return 2
            }
        }
        """
        let (diagnostics, fixed) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        let fixedSource = try #require(fixed)
        #expect(fixedSource.contains("return switch input"))
        #expect(fixedSource.contains("case .first:"))
        #expect(fixedSource.contains("case .second:"))
        #expect(!fixedSource.contains("return 1"))
        #expect(!fixedSource.contains("return 2"))
    }

    @Test("fix-it preserves all cases in a larger switch")
    func fixMoreThanTwoCases() async throws {
        let source = """
        func priority(for status: Status) -> Int {
            switch status {
            case .blocked:
                return 0
            case .ready:
                return 1
            case .done:
                return 2
            }
        }
        """
        let (diagnostics, fixed) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        let fixedSource = try #require(fixed)
        #expect(fixedSource.contains("return switch status"))
        #expect(fixedSource.contains("case .blocked:"))
        #expect(fixedSource.contains("case .ready:"))
        #expect(fixedSource.contains("case .done:"))
        #expect(!fixedSource.contains("return 0"))
        #expect(!fixedSource.contains("return 1"))
        #expect(!fixedSource.contains("return 2"))
    }

    @Test("multiple qualifying switches each produce one error")
    func multipleSwitches() async {
        let source = """
        func a(_ value: Int) -> String {
            switch value {
            case 0:
                return "a"
            default:
                return "b"
            }
        }
        func b(_ value: Int) -> String {
            switch value {
            case 0:
                return "c"
            default:
                return "d"
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }
}
