@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("single-large-type-per-file: detects multiple large public/package types in one file")
struct SingleLargeTypePerFileRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "single-large-type-per-file"))
    }

    // MARK: - Helpers

    private func publicStruct(name: String, lines: Int) -> String {
        var result = "public struct \(name) {\n"
        for i in 0 ..< (lines - 2) { result += "    let prop\(i) = \(i)\n" }
        return result + "}"
    }

    private func packageStruct(name: String, lines: Int) -> String {
        var result = "package struct \(name) {\n"
        for i in 0 ..< (lines - 2) { result += "    let prop\(i) = \(i)\n" }
        return result + "}"
    }

    private func internalStruct(name: String, lines: Int) -> String {
        var result = "struct \(name) {\n"
        for i in 0 ..< (lines - 2) { result += "    let prop\(i) = \(i)\n" }
        return result + "}"
    }

    // MARK: - Violation tests

    @Test("error when two public types each >= 50 lines in one file")
    func twoLargePublicTypes() async {
        let source = publicStruct(name: "Foo", lines: 50) + "\n" + publicStruct(name: "Bar", lines: 50)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("error when two package types each >= 50 lines in one file")
    func twoLargePackageTypes() async {
        let source = packageStruct(name: "Foo", lines: 50) + "\n" + packageStruct(name: "Bar", lines: 50)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("error when mixed public and package large types")
    func mixedPublicPackage() async {
        let source = publicStruct(name: "Foo", lines: 50) + "\n" + packageStruct(name: "Bar", lines: 50)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - False positive tests

    @Test("no error when only one large public type")
    func singleLargeType() async {
        let diagnostics = await rule.lint(source: publicStruct(name: "Foo", lines: 60))
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when two public types but both under 50 lines")
    func twoSmallPublicTypes() async {
        let source = publicStruct(name: "Foo", lines: 10) + "\n" + publicStruct(name: "Bar", lines: 10)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when one is large and one is small")
    func oneLargeOneSmall() async {
        let source = publicStruct(name: "Foo", lines: 60) + "\n" + publicStruct(name: "Bar", lines: 10)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for internal types even if large")
    func twoLargeInternalTypes() async {
        let source = internalStruct(name: "Foo", lines: 60) + "\n" + internalStruct(name: "Bar", lines: 60)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("nested types are not counted as top-level")
    func nestedTypes() async {
        var source = "public struct Outer {\n"
        source += publicStruct(name: "Inner", lines: 50)
        for i in 0 ..< 50 { source += "    let outerProp\(i) = \(i)\n" }
        source += "}"
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - All type kinds

    @Test("detects all type declaration kinds", arguments: [
        ("public enum", "enum"),
        ("public class", "class"),
        ("public actor", "actor"),
        ("public struct", "struct"),
    ])
    func allTypeKinds(keyword: String, kind: String) async {
        func largeType(name: String) -> String {
            var result = "\(keyword) \(name) {\n"
            for i in 0 ..< 50 { result += "    let prop\(i) = \(i)\n" }
            return result + "}"
        }
        let source = largeType(name: "TypeA") + "\n" + largeType(name: "TypeB")
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2, "Expected violation for \(kind) types")
    }

    // MARK: - Boundary

    @Test("no error at 49 lines (below threshold)")
    func belowThreshold() async {
        let source = publicStruct(name: "Foo", lines: 49) + "\n" + publicStruct(name: "Bar", lines: 49)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("error at exactly 50 lines (at threshold)")
    func atThreshold() async {
        let source = publicStruct(name: "Foo", lines: 50) + "\n" + publicStruct(name: "Bar", lines: 50)
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - YAML args override

    @Test("YAML args override min_lines")
    func yamlOverride() async {
        let source = publicStruct(name: "Foo", lines: 20) + "\n" + publicStruct(name: "Bar", lines: 20)
        let diagnostics = await rule.lint(source: source, argsYAML: "min_lines: 15\n")
        #expect(diagnostics.count == 2)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("message includes type name")
    func messageContent() async {
        let source = publicStruct(name: "Foo", lines: 50) + "\n" + publicStruct(name: "Bar", lines: 50)
        let diagnostics = await rule.lint(source: source)
        let messages = diagnostics.map(\.message)
        #expect(messages.contains { $0.contains("Foo") })
        #expect(messages.contains { $0.contains("Bar") })
    }
}
