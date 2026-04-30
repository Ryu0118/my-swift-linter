@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("no-top-level-function: forbids file-scope func declarations")
struct NoTopLevelFunctionRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "no-top-level-function"))
    }

    // MARK: - Violation tests

    @Test("flags a single top-level func with error severity")
    func singleTopLevelFunc() async {
        let source = """
        func helper() {
            print("hello")
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
    }

    @Test("flags multiple top-level funcs separately")
    func multipleTopLevelFuncs() async {
        let source = """
        func a() {}
        func b() {}
        func c() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 3)
    }

    @Test("flags top-level funcs regardless of access modifier", arguments: [
        "private",
        "fileprivate",
        "internal",
        "public",
    ])
    func allAccessModifiers(modifier: String) async {
        let source = "\(modifier) func helper() {}"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1, "\(modifier) func should be flagged")
    }

    @Test("flags top-level async / throws funcs")
    func asyncThrowsFunc() async {
        let source = "func helper() async throws -> Int { 0 }"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("flags top-level generic funcs")
    func genericFunc() async {
        let source = "func wrap<T>(_ value: T) -> T { value }"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    // MARK: - False positive tests

    @Test("does not flag funcs inside a struct")
    func funcInsideStruct() async {
        let source = """
        struct Foo {
            func helper() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("does not flag funcs inside an extension")
    func funcInsideExtension() async {
        let source = """
        extension Foo {
            func helper() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("does not flag funcs inside a namespace enum")
    func funcInsideEnumNamespace() async {
        let source = """
        enum Helpers {
            static func cacheKey() -> String { "" }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("does not flag funcs inside a class / actor", arguments: [
        "class",
        "actor",
    ])
    func funcInsideClassOrActor(keyword: String) async {
        let source = """
        \(keyword) Foo {
            func helper() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty, "func inside \(keyword) should not be flagged")
    }

    @Test("does not flag funcs inside a protocol")
    func funcInsideProtocol() async {
        let source = """
        protocol Foo {
            func helper()
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("does not flag top-level vars / lets / type decls")
    func topLevelNonFunctionDeclarations() async {
        let source = """
        let constant = 1
        var variable = 2
        struct Foo {}
        enum Bar { case a }
        typealias Baz = Int
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("does not flag nested func inside another func body")
    func nestedFuncInsideFunc() async {
        // The outer func itself is top-level (and gets flagged), but the
        // inner one must NOT produce an additional diagnostic — only top-level
        // statements are inspected.
        let source = """
        struct Foo {
            func outer() {
                func inner() {}
                inner()
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Message content

    @Test("message includes the function name")
    func messageMentionsFunctionName() async {
        let source = "func myUniqueHelper() {}"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.first?.message.contains("myUniqueHelper") == true)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }
}
