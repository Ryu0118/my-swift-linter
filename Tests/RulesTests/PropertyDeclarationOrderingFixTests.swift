@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("property-declaration-ordering: Fix-It and computed property ordering")
struct PropertyDeclarationOrderingFixTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "property-declaration-ordering"))
    }

    // MARK: - Fix-It tests

    @Test("fix reorders by wrapper then access modifier")
    func fixReordersByWrapperThenAccess() {
        let source = """
        struct Foo {
            @Presents var hoge: Int?
            var fuga: Int
            @Presents var foo: Int?
            @Shared var bar: Int
            var foobar: Int
        }
        """
        let (diagnostics, fixedSource) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        #expect(fixedSource != nil)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let propLines = lines.filter { $0.contains("var") && !$0.starts(with: "struct") }
            #expect(propLines.count == 5)
            #expect(propLines[0].contains("@Presents var hoge"))
            #expect(propLines[1].contains("@Presents var foo"))
            #expect(propLines[2].contains("@Shared var bar"))
            #expect(propLines[3].contains("var fuga"))
            #expect(propLines[4].contains("var foobar"))
        }
    }

    @Test("fix groups access modifiers within same wrapper")
    func fixGroupsAccessWithinWrapper() {
        let source = """
        struct Foo {
            public var a: Int
            var b: Int
            public var c: Int
            private var d: Int
        }
        """
        let (_, fixedSource) = rule.lintAndFix(source: source)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let propLines = lines.filter { $0.contains("var") && !$0.starts(with: "struct") }
            #expect(propLines[0].contains("public var a"))
            #expect(propLines[1].contains("public var c"))
            #expect(propLines[2].contains("var b"))
            #expect(propLines[3].contains("private var d"))
        }
    }

    @Test("fix handles combined wrapper + access modifier disorder")
    func fixCombinedDisorder() {
        let source = """
        struct Foo {
            @Presents public var a: Int?
            var b: Int
            @Presents var c: Int?
            public var d: Int
        }
        """
        let (_, fixedSource) = rule.lintAndFix(source: source)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let propLines = lines.filter { $0.contains("var") && !$0.starts(with: "struct") }
            #expect(propLines[0].contains("@Presents public var a"))
            #expect(propLines[1].contains("@Presents var c"))
            #expect(propLines[2].contains("public var d"))
            #expect(propLines[3].contains("var b"))
        }
    }

    @Test("fix preserves relative order within same group")
    func fixPreservesRelativeOrder() {
        let source = """
        struct Foo {
            var z: Int
            public var b: Int
            var a: Int
            public var x: Int
        }
        """
        let (_, fixedSource) = rule.lintAndFix(source: source)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let propLines = lines.filter { $0.contains("var") && !$0.starts(with: "struct") }
            #expect(propLines[0].contains("public var b"))
            #expect(propLines[1].contains("public var x"))
            #expect(propLines[2].contains("var z"))
            #expect(propLines[3].contains("var a"))
        }
    }

    @Test("fix converges in one pass (no oscillation)")
    func fixConverges() async {
        let source = """
        struct Foo {
            @Presents public var a: Int?
            var b: Int
            @Shared var c: Int
            @Presents var d: Int?
            public var e: Int
            @Shared private var f: Int
        }
        """
        let (diag1, fixed1) = rule.lintAndFix(source: source)
        #expect(diag1.count == 1)
        #expect(fixed1 != nil)
        if let fixed = fixed1 {
            let diag2 = await rule.lint(source: fixed)
            #expect(diag2.isEmpty, "Fix should converge in one pass")
        }
    }

    // MARK: - Computed properties

    @Test("computed view properties after stored are fine")
    func computedViewPropertiesExcluded() async {
        let source = """
        struct MyView: View {
            @State var count: Int
            var body: some View { Text("hello") }
            @ToolbarContentBuilder
            private var toolbarContent: some ToolbarContent {
                ToolbarItem { Button("tap") {} }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("warning when computed property is between stored properties")
    func computedBetweenStored() async {
        let source = """
        struct Foo {
            @State var a: Int
            var computed: String { "hello" }
            @State var b: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("fix moves stored before computed, keeps computed order")
    func fixDoesNotMoveComputed() {
        let source = """
        struct Foo {
            public var a: Int
            var computed: String { "hello" }
            var b: Int
            public var c: Int
        }
        """
        let (diagnostics, fixedSource) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let storedLines = lines.filter {
                $0.contains("var") && !$0.starts(with: "struct") && !$0.contains("computed")
            }
            #expect(storedLines[0].contains("public var a"))
            #expect(storedLines[1].contains("public var c"))
            #expect(storedLines[2].contains("var b"))
        }
    }

    // MARK: - var body ordering

    @Test("warning when computed property appears before var body")
    func computedBeforeBody() async {
        let source = """
        struct MyView: View {
            @State var count: Int
            @ToolbarContentBuilder
            private var toolbarContent: some ToolbarContent {
                ToolbarItem { Button("tap") {} }
            }
            var body: some View { Text("hello") }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("fix moves var body before other computed properties")
    func fixBodyFirst() {
        let source = """
        struct MyView: View {
            @State var count: Int
            var helper: String { "hi" }
            var body: some View { Text("hello") }
        }
        """
        let (diag, fixedSource) = rule.lintAndFix(source: source)
        #expect(diag.count == 1)
        if let fixed = fixedSource {
            let lines = fixed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let computedLines = lines.filter { $0.contains("var helper") || $0.contains("var body") }
            #expect(computedLines[0].contains("var body"))
            #expect(computedLines[1].contains("var helper"))
        }
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("message mentions wrapper and access modifier")
    func messageContent() async {
        let source = """
        struct Foo {
            @State var a: Int
            var b: Int
            @State var c: Int
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        let msg = diagnostics[0].message
        #expect(msg.contains("wrapper"))
        #expect(msg.contains("access modifier"))
    }
}
