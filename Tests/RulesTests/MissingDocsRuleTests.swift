@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct MissingDocsRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "missing-docs"))
    }

    // MARK: - Violations: all declaration kinds with explicit public

    @Test("error when public func lacks doc comment", arguments: [
        "public func foo() {}",
        "public struct Foo {}",
        "public class Foo {}",
        "public actor Foo {}",
        "public enum Foo {}",
        "public protocol Foo {}",
        "public var x: Int = 0",
        "public let x: Int = 0",
        "public typealias Foo = Int",
    ])
    func publicDeclWithoutDoc(declaration: String) async {
        let diagnostics = await rule.lint(source: declaration)
        #expect(!diagnostics.isEmpty, "Expected violation for: \(declaration)")
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("no error when public init has doc comment")
    func publicInitWithDoc() async {
        let source = """
        /// A documented struct.
        public struct Foo {
            /// Creates a Foo.
            public init() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("error when public init in struct lacks doc comment")
    func publicInitMissingDoc() async {
        let source = """
        public struct Foo {
            public init() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty)
    }

    @Test("error when open func lacks doc comment")
    func openFuncWithoutDoc() async {
        let diagnostics = await rule.lint(source: "open func foo() {}")
        #expect(!diagnostics.isEmpty)
    }

    @Test("error when package func lacks doc comment")
    func packageFuncWithoutDoc() async {
        let diagnostics = await rule.lint(source: "package func foo() {}")
        #expect(!diagnostics.isEmpty)
    }

    @Test("error when public subscript lacks doc comment")
    func publicSubscriptWithoutDoc() async {
        let source = """
        public struct Foo {
            public subscript(index: Int) -> Int { index }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - No violations: doc comment present

    @Test("no error when public func has line doc comment")
    func publicFuncWithLineDoc() async {
        let source = """
        /// Does something.
        public func foo() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when public func has block doc comment")
    func publicFuncWithBlockDoc() async {
        let source = """
        /** Does something. */
        public func foo() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when public func has multi-line doc comment")
    func publicFuncWithMultiLineDoc() async {
        let source = """
        /// First line.
        /// Second line.
        public func foo() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when public struct has doc comment")
    func publicStructWithDoc() async {
        let source = """
        /// A documented struct.
        public struct Foo {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - No violations: below threshold

    @Test("no error for internal func with default min_access_level package")
    func internalFuncBelowThreshold() async {
        let diagnostics = await rule.lint(source: "func foo() {}")
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for fileprivate func")
    func fileprivateFuncBelowThreshold() async {
        let diagnostics = await rule.lint(source: "fileprivate func foo() {}")
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for private func")
    func privateFuncBelowThreshold() async {
        let diagnostics = await rule.lint(source: "private func foo() {}")
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for internal struct")
    func internalStructBelowThreshold() async {
        let diagnostics = await rule.lint(source: "internal struct Foo {}")
        #expect(diagnostics.isEmpty)
    }

    // MARK: - No violations: non-doc comment does not count

    @Test("no error when only regular line comment exists (not doc comment)")
    func regularCommentDoesNotCount() async {
        let source = """
        // This is a regular comment, not a doc comment.
        public func foo() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty, "Regular comment should not satisfy doc requirement")
    }

    @Test("no error when only block comment exists (not doc comment)")
    func blockCommentDoesNotCount() async {
        let source = """
        /* regular block comment */
        public func foo() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty, "Block comment should not satisfy doc requirement")
    }

    // MARK: - package access level (key differentiator from SwiftLint)

    @Test("error when package struct lacks doc comment")
    func packageStructWithoutDoc() async {
        let diagnostics = await rule.lint(source: "package struct Foo {}")
        #expect(!diagnostics.isEmpty)
    }

    @Test("no error when package struct has doc comment")
    func packageStructWithDoc() async {
        let source = """
        /// Documented.
        package struct Foo {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - YAML args: min_access_level override

    @Test("YAML min_access_level: package fires for package but not internal")
    func yamlMinPackageFiresForPackage() async {
        let source = "package func foo() {}"
        let diagnostics = await rule.lint(source: source, argsYAML: "min_access_level: package\n")
        #expect(!diagnostics.isEmpty)
    }

    @Test("YAML min_access_level: package does not fire for internal")
    func yamlMinPackageDoesNotFireForInternal() async {
        let source = "internal func foo() {}"
        let diagnostics = await rule.lint(source: source, argsYAML: "min_access_level: package\n")
        #expect(diagnostics.isEmpty)
    }

    @Test("YAML min_access_level: internal fires for explicit internal func")
    func yamlMinInternalFiresForInternal() async {
        let source = "internal func foo() {}"
        let diagnostics = await rule.lint(source: source, argsYAML: "min_access_level: internal\n")
        #expect(!diagnostics.isEmpty)
    }

    @Test("YAML min_access_level: internal does not fire for private")
    func yamlMinInternalDoesNotFireForPrivate() async {
        let source = "private func foo() {}"
        let diagnostics = await rule.lint(source: source, argsYAML: "min_access_level: internal\n")
        #expect(diagnostics.isEmpty)
    }

    @Test("YAML min_access_level: open only fires for open")
    func yamlMinOpenOnlyFiresForOpen() async {
        let publicDiag = await rule.lint(source: "public func foo() {}", argsYAML: "min_access_level: open\n")
        #expect(publicDiag.isEmpty)

        let openDiag = await rule.lint(source: "open func foo() {}", argsYAML: "min_access_level: open\n")
        #expect(!openDiag.isEmpty)
    }

    // MARK: - extension member policy (v1: explicit modifier only)

    @Test("no error for implicit member inside public extension (no explicit modifier)")
    func implicitMemberInPublicExtension() async {
        let source = """
        public extension Foo {
            func bar() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty, "Members without explicit modifier should not trigger (v1 policy)")
    }

    @Test("error for explicitly public member inside public extension")
    func explicitPublicMemberInExtension() async {
        let source = """
        public extension Foo {
            public func bar() {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - enum case: excluded

    @Test("no error for public enum case (excluded from rule)")
    func publicEnumCaseExcluded() async {
        let source = """
        /// A direction.
        public enum Direction {
            case north
            case south
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("multiple public declarations each produce a violation")
    func multipleViolations() async {
        let source = """
        public func foo() {}
        public func bar() {}
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("diagnostic message contains the declaration name")
    func diagnosticMessageContainsName() async {
        let source = "public func myFancyFunction() {}"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("myFancyFunction"))
    }
}
