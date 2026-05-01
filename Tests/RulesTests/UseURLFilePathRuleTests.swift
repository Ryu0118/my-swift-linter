@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("use-url-file-path: detects deprecated URL(fileURLWithPath:) initializer calls")
struct UseURLFilePathRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "use-url-file-path"))
    }

    // MARK: - Violations

    @Test("warning on URL(fileURLWithPath:)")
    func fileURLWithPath() async {
        let source = """
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("warning on URL(fileURLWithPath:isDirectory:)")
    func fileURLWithPathIsDirectory() async {
        let source = """
        let url = URL(fileURLWithPath: "/tmp/dir", isDirectory: true)
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("warning on explicit URL.init(fileURLWithPath:)")
    func explicitInitForm() async {
        let source = """
        let url = URL.init(fileURLWithPath: "/tmp/file.txt")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on implicit-base .init(fileURLWithPath:)")
    func implicitBaseInitForm() async {
        let source = """
        let hoge: URL = .init(fileURLWithPath: "/tmp/file.txt")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("warning on multiple occurrences")
    func multipleOccurrences() async {
        let source = """
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - Auto-fix

    @Test("fix replaces fileURLWithPath with filePath")
    func fixFileURLWithPath() async {
        let source = """
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        """
        let (diagnostics, fixedSource) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        #expect(fixedSource?.contains("URL(filePath:") == true)
        #expect(fixedSource?.contains("fileURLWithPath") == false)
    }

    @Test("fix replaces fileURLWithPath:isDirectory: with filePath:directoryHint:")
    func fixFileURLWithPathIsDirectory() async {
        let source = """
        let url = URL(fileURLWithPath: "/tmp/dir", isDirectory: true)
        """
        let (diagnostics, fixedSource) = await rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        #expect(fixedSource?.contains("filePath:") == true)
        #expect(fixedSource?.contains("directoryHint:") == true)
        #expect(fixedSource?.contains("fileURLWithPath") == false)
        #expect(fixedSource?.contains("isDirectory") == false)
    }

    // MARK: - No violations

    @Test("no warning on URL(filePath:)")
    func urlFilePath() async {
        let source = """
        let url = URL(filePath: "/tmp/file.txt")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning on URL(filePath:directoryHint:)")
    func urlFilePathDirectoryHint() async {
        let source = """
        let url = URL(filePath: "/tmp/dir", directoryHint: .isDirectory)
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning on URL(string:)")
    func urlString() async {
        let source = """
        let url = URL(string: "https://example.com")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no warning on non-URL type using fileURLWithPath label")
    func otherTypeFileURLWithPath() async {
        let source = """
        let x = SomeOtherType(fileURLWithPath: "/tmp")
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}
