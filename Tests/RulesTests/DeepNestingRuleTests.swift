@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("deep-nesting: detects control flow nested beyond max depth via AST")
struct DeepNestingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "deep-nesting"))
    }

    // MARK: - Violation tests

    @Test("error at depth 3 with default max 3")
    func atThreshold() async {
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

    @Test("error at depth 4 exceeds default max 3")
    func aboveThreshold() async {
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
        // depth 3 and depth 4 both trigger
        #expect(diagnostics.count == 2)
    }

    // MARK: - False positive tests

    @Test("no error at depth 2 with default max 3")
    func belowThreshold() async {
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

    @Test("detects all control flow types at depth 3", arguments: [
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

    @Test("YAML args override max depth", arguments: [
        ("max_depth: 2\n", 1),
        ("max_depth: 10\n", 0),
    ])
    func yamlOverride(yaml: String, expectedCount: Int) async {
        let source = """
        func foo() {
            if true {
                if true { let _ = 0 }
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: yaml)
        #expect(diagnostics.count == expectedCount)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("message includes depth and max")
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
        #expect(diagnostics[0].message.contains("max"))
    }
}
