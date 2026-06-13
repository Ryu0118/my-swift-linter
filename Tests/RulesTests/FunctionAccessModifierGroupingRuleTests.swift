@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct FunctionAccessModifierGroupingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "function-access-modifier-grouping"))
    }

    // MARK: - Violation tests

    @Test("error when access modifiers are not grouped")
    func ungroupedAccessModifiers() async {
        let source = """
        struct Foo {
            public func a() {}
            func b() {}
            public func c() {}
            private func d() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when same access level is split by another")
    func splitAccessLevel() async {
        let source = """
        struct Foo {
            private func a() {}
            public func b() {}
            private func c() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("detects in all type kinds", arguments: [
        "struct Foo {\n    public func a() {}\n    func b() {}\n    public func c() {}\n}",
        "class Foo {\n    public func a() {}\n    func b() {}\n    public func c() {}\n}",
        "enum Foo {\n    public func a() {}\n    func b() {}\n    public func c() {}\n}",
        "actor Foo {\n    public func a() {}\n    func b() {}\n    public func c() {}\n}",
        "extension Foo {\n    public func a() {}\n    func b() {}\n    public func c() {}\n}",
    ])
    func allTypeKinds(source: String) async {
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty, "Expected violation")
    }

    // MARK: - False positive tests

    @Test("no warning when already grouped")
    func alreadyGrouped() async {
        let source = """
        struct Foo {
            public func a() {}
            public func b() {}
            func c() {}
            private func d() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when all same access level")
    func allSameLevel() async {
        let source = """
        struct Foo {
            func a() {}
            func b() {}
            func c() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning with single function")
    func singleFunction() async {
        let source = """
        struct Foo {
            func a() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("properties between functions do not affect grouping")
    func propertiesBetweenFunctions() async {
        let source = """
        struct Foo {
            public func a() {}
            var x: Int = 0
            public func b() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("init and deinit are excluded from grouping check")
    func initDeinitExcluded() async {
        let source = """
        class Foo {
            public func a() {}
            init() {}
            public func b() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Fix-It tests

    @Test("fix reorders functions by access modifier")
    func fixReorders() {
        let source = """
        struct Foo {
            public func a() {}
            func b() {}
            public func c() {}
            private func d() {}
        }
        """
        let (diagnostics, fixedSource) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let funcLines = lines.filter { $0.contains("func") && !$0.starts(with: "struct") }
            #expect(funcLines[0].contains("public func a"))
            #expect(funcLines[1].contains("public func c"))
            #expect(funcLines[2].contains("func b"))
            #expect(funcLines[3].contains("private func d"))
        }
    }

    @Test("fix preserves relative order within same access level")
    func fixPreservesRelativeOrder() {
        let source = """
        struct Foo {
            func z() {}
            public func b() {}
            func a() {}
            public func x() {}
        }
        """
        let (_, fixedSource) = rule.lintAndFix(source: source)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let funcLines = lines.filter { $0.contains("func") && !$0.starts(with: "struct") }
            #expect(funcLines[0].contains("public func b"))
            #expect(funcLines[1].contains("public func x"))
            #expect(funcLines[2].contains("func z"))
            #expect(funcLines[3].contains("func a"))
        }
    }

    @Test("fix does not move properties or init")
    func fixDoesNotMoveNonFunctions() {
        let source = """
        struct Foo {
            var x: Int = 0
            func b() {}
            init() {}
            public func a() {}
            func c() {}
        }
        """
        let (_, fixedSource) = rule.lintAndFix(source: source)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(lines[1].contains("var x"))
            #expect(lines[3].contains("init()"))
            let funcLines = lines.filter { $0.contains("func") && !$0.starts(with: "struct") }
            #expect(funcLines[0].contains("public func a"))
            #expect(funcLines[1].contains("func b"))
            #expect(funcLines[2].contains("func c"))
        }
    }

    @Test("fix converges in one pass")
    func fixConverges() async {
        let source = """
        struct Foo {
            public func a() {}
            private func b() {}
            func c() {}
            public func d() {}
            private func e() {}
        }
        """
        let (diag1, fixed1) = rule.lintAndFix(source: source)
        #expect(diag1.count == 1)
        if let fixed = fixed1 {
            let diag2 = await rule.lint(source: fixed)
            #expect(diag2.isEmpty, "Fix should converge in one pass")
        }
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("message mentions access modifier")
    func messageContent() async {
        let source = """
        struct Foo {
            public func a() {}
            func b() {}
            public func c() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("access modifier"))
    }
}
