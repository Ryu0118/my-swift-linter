@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("property-declaration-ordering: detects ungrouped property wrappers and access modifiers")
struct PropertyDeclarationOrderingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "property-declaration-ordering"))
    }

    // MARK: - Violation: access modifier ungrouped

    @Test("warning when access modifiers are not grouped")
    func ungroupedAccessModifiers() async {
        let source = """
        struct Foo {
            public var a: Int
            var b: Int
            public var c: Int
            private var d: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("warning when same access level is split by another")
    func splitAccessLevel() async {
        let source = """
        struct Foo {
            private var a: Int
            public var b: Int
            private var c: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - Violation: property wrapper ungrouped

    @Test("warning when property wrappers are not grouped")
    func ungroupedWrappers() async {
        let source = """
        struct Foo {
            @Presents var hoge: Int?
            var fuga: Int
            @Presents var foo: Int?
            @Shared var bar: Int
            var foobar: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("warning when different wrappers are interleaved")
    func interleavedWrappers() async {
        let source = """
        struct Foo {
            @Presents var a: Int?
            @Shared var b: Int
            @Presents var c: Int?
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - Violation: both ungrouped

    @Test("warning when both wrapper and access modifier are ungrouped")
    func bothUngrouped() async {
        let source = """
        struct Foo {
            @Presents public var a: Int?
            var b: Int
            @Presents var c: Int?
            public var d: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - False positive tests

    @Test("no warning when already grouped by wrapper then access modifier")
    func alreadyGrouped() async {
        let source = """
        struct Foo {
            @Presents public var a: Int?
            @Presents var c: Int?
            @Shared var bar: Int
            public var d: Int
            var b: Int
            private var e: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when all same access level and no wrappers")
    func allSameLevel() async {
        let source = """
        struct Foo {
            var a: Int
            var b: Int
            var c: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning with single property")
    func singleProperty() async {
        let source = """
        struct Foo {
            var a: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning with no properties")
    func noProperties() async {
        let source = """
        struct Foo {
            func doSomething() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("functions between properties do not affect grouping check")
    func functionsDoNotAffectGrouping() async {
        let source = """
        struct Foo {
            @State var a: Int
            func doSomething() {}
            var b: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning when wrappers grouped with unwrapped at end")
    func wrappersBeforeUnwrapped() async {
        let source = """
        struct Foo {
            @Binding var a: Int
            @State var b: Int
            var c: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning with access modifiers in order without wrappers")
    func accessModifiersInOrder() async {
        let source = """
        struct Foo {
            public var a: Int
            public var b: Int
            var c: Int
            private var d: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - All type declaration kinds

    @Test("detects issue in all type declaration kinds", arguments: [
        "struct Foo {\n    public var a: Int\n    var b: Int\n    public var c: Int\n}",
        "class Foo {\n    public var a: Int\n    var b: Int\n    public var c: Int\n}",
        "enum Foo {\n    public static var a: Int = 0\n"
            + "    static var b: Int = 0\n    public static var c: Int = 0\n}",
        "actor Foo {\n    public var a: Int\n    var b: Int\n    public var c: Int\n}",
    ])
    func allTypeKinds(source: String) async {
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty, "Expected violation")
    }
}
