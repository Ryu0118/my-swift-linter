@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct DeepNestingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "deep-nesting"))
    }

    // MARK: - Violation tests

    @Test("error at depth 3 (default threshold)")
    func atWarningThreshold() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true { let _ = 0 }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error at depth 5")
    func atErrorThreshold() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true {
                        if true {
                            if true { let _ = 0 }
                        }
                    }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("depths 3 and 4 both produce errors by default")
    func betweenThresholds() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true {
                        if true { let _ = 0 }
                    }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    // MARK: - False positive tests

    @Test("no violation at depth 2 (below warning threshold)")
    func belowWarningThreshold() async {
        let source = """
        func foo() {
            if true {
                if true { let _ = 0 }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("flat control flow at same level does not accumulate depth")
    func flatSameLevel() async {
        let source = """
        func foo() {
            if true { let _ = 0 }
            if true { let _ = 0 }
            if true { let _ = 0 }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("depth resets between separate functions")
    func depthResetsBetweenFunctions() async {
        let source = """
        func foo() {
            if true { if true { let _ = 0 } }
        }
        func bar() {
            if true { if true { let _ = 0 } }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("depth resets inside closures")
    func depthResetsInClosures() async {
        let source = """
        func foo() {
            if true {
                if true {
                    let closure = {
                        if true { let _ = 0 }
                    }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Parameterized: all control flow types

    @Test("detects all control flow types at warning depth", arguments: [
        "if true { let _ = 0 }",
        "for _ in [] { let _ = 0 }",
        "while true { let _ = 0 }",
        "switch 0 { default: let _ = 0 }",
        "do { let _ = 0 }",
    ])
    func allControlFlowTypes(statement: String) async {
        let source = """
        func foo() {
            if true { for _ in [1] { \(statement) } }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty, "Expected violation for: \(statement)")
    }

    // MARK: - YAML args override

    @Test("YAML warning threshold lowers to 2 — depth 2 produces warning")
    func yamlWarningOverride() async {
        let source = """
        func foo() {
            if true {
                if true { let _ = 0 }
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "warning_depth: 2\nerror_depth: 4\n")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("YAML error threshold lowers to 3 — depth 3 produces error")
    func yamlErrorOverride() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true { let _ = 0 }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "warning_depth: 2\nerror_depth: 3\n")
        #expect(diagnostics.count == 2)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("YAML thresholds raised — no violation at depth 3")
    func yamlThresholdsRaised() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true { let _ = 0 }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "warning_depth: 10\nerror_depth: 15\n")
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("message includes current depth and threshold")
    func messageContent() async {
        let source = """
        func foo() {
            if true {
                if true {
                    if true { let _ = 0 }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("3"))
    }
}
