import SwiftASTLint
import SwiftSyntax

struct SingleLargeTypeArgs: Codable {
    /// Line count at which a type is considered large enough to warn. Must be less than or equal to `error_lines`.
    var warningLines: Int = 50
    /// Line count at which a type triggers an error when multiple appear in one file.
    var errorLines: Int = 50

    enum CodingKeys: String, CodingKey {
        case warningLines = "warning_lines"
        case errorLines = "error_lines"
    }
}

/// Flags files that contain two or more large `public`/`package` types.
/// Emits an error by default when each type exceeds `error_lines` lines.
/// Nested types are not counted as top-level declarations.
///
/// Configure via YAML:
/// ```yaml
/// rules:
///   single-large-type-per-file:
///     args:
///       warning_lines: 50
///       error_lines: 50
/// ```
let singleLargeTypePerFileRule = ParameterizedRule(
    id: "single-large-type-per-file",
    defaultArguments: SingleLargeTypeArgs()
) { file, context, args in
    let visitor = LargeTypeCollector(minLines: args.warningLines)
    visitor.walk(file)

    let largeTypes = visitor.largeTypes
    guard largeTypes.count >= 2 else { return }
    for info in largeTypes {
        let severity: Severity = info.lineCount >= args.errorLines ? .error : .warning
        let threshold = info.lineCount >= args.errorLines ? args.errorLines : args.warningLines
        context.report(
            on: info.node,
            message: "\(info.name) is \(info.lineCount) lines."
                + " Only one large (>= \(threshold) lines) public/package type per file is allowed."
                + " Split into separate files.",
            severity: severity
        )
    }
}

private struct LargeTypeInfo {
    let name: String
    let lineCount: Int
    let node: Syntax
}

private final class LargeTypeCollector: SyntaxVisitor {
    let minLines: Int
    var largeTypes: [LargeTypeInfo] = []
    /// Only top-level types are counted; nested types are excluded.
    private var nestingLevel = 0

    init(minLines: Int) {
        self.minLines = minLines
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        nestingLevel -= 1
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        nestingLevel -= 1
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        nestingLevel -= 1
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) {
        nestingLevel -= 1
    }

    // MARK: - Helper

    private func checkType(
        name: String,
        modifiers: DeclModifierListSyntax,
        syntax: Syntax
    ) {
        guard nestingLevel == 0 else { return }
        let isPublicOrPackage = modifiers.contains {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.package)
        }
        guard isPublicOrPackage else { return }
        let lineCount = Self.countLines(syntax)
        guard lineCount >= minLines else { return }
        largeTypes.append(LargeTypeInfo(name: name, lineCount: lineCount, node: syntax))
    }

    private static func countLines(_ node: Syntax) -> Int {
        node.description.components(separatedBy: "\n").count
    }
}
