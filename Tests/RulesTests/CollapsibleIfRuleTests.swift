@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct CollapsibleIfRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "collapsible-if"))
    }

    // MARK: - Violation tests: if-in-if

    @Test("if containing only an else-less if is a violation")
    func ifInIf() async {
        let source = """
        func foo() {
            if condition {
                if other {
                    hoge()
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("if let containing only an else-less if let is a violation")
    func ifLetInIfLet() async {
        let source = """
        func foo() {
            if let x = f() {
                if let y = g() {
                    hoge(x, y)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("triple nested else-less ifs report per mergeable pair")
    func tripleNested() async {
        let source = """
        func foo() {
            if a {
                if b {
                    if c {
                        hoge()
                    }
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - Violation tests: guard containing single if

    @Test("guard body containing only an else-less if is a violation")
    func guardContainingIf() async {
        let source = """
        func foo() {
            guard condition else { return }
            if other {
                hoge()
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - Violation tests: shadowing (still flagged, not auto-mergeable)

    @Test("shadowed optional binding is still flagged as collapsible")
    func shadowedBindingStillFlagged() async {
        let source = """
        func foo() {
            if let x = a {
                if let x = x.child {
                    hoge(x)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("shadow"))
    }

    // MARK: - False positive tests

    @Test("no violation when outer if has multiple statements")
    func outerHasMultipleStatements() async {
        let source = """
        func foo() {
            if condition {
                setup()
                if other {
                    hoge()
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no violation when outer if has an else clause")
    func outerHasElse() async {
        let source = """
        func foo() {
            if condition {
                if other {
                    hoge()
                }
            } else {
                fallback()
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no violation when inner if has an else clause")
    func innerHasElse() async {
        let source = """
        func foo() {
            if condition {
                if other {
                    hoge()
                } else {
                    fallback()
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no violation for flat sibling ifs")
    func flatSiblingIfs() async {
        let source = """
        func foo() {
            if condition {
                hoge()
            }
            if other {
                fuga()
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no violation for labeled outer if")
    func labeledOuterIf() async {
        let source = """
        func foo() {
            outer: if condition {
                if other {
                    break outer
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no violation when inner if is inside a for loop, not a bare if")
    func innerInsideForLoop() async {
        let source = """
        func foo() {
            if condition {
                for item in items {
                    if other {
                        hoge()
                    }
                }
            }
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

    @Test("message mentions merging the conditions")
    func messageContent() async {
        let source = """
        func foo() {
            if condition {
                if other {
                    hoge()
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.lowercased().contains("merge"))
    }

    // MARK: - YAML args override

    @Test("YAML severity override lowers to warning")
    func yamlSeverityOverride() async {
        let source = """
        func foo() {
            if condition {
                if other {
                    hoge()
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "severity: warning\n")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("default severity is error without YAML override")
    func defaultSeverityIsError() async {
        let source = """
        func foo() {
            guard condition else { return }
            if other {
                hoge()
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }
}
