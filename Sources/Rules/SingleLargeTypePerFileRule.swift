import SwiftASTLint
import SwiftSyntax

struct SingleLargeTypeArgs: Codable {
    var minLines: Int = 50
    enum CodingKeys: String, CodingKey {
        case minLines = "min_lines"
    }
}

/// Emits an error when two or more `public`/`package` types (enum, struct, class, actor)
/// each exceeding `minLines` lines appear in the same file.
/// Nested types are not counted as top-level declarations.
let singleLargeTypePerFileRule = ParameterizedRule(
    id: "single-large-type-per-file",
    defaultArguments: SingleLargeTypeArgs()
) { file, context, args in
    let visitor = LargeTypeCollector(minLines: args.minLines)
    visitor.walk(file)

    let largeTypes = visitor.largeTypes
    if largeTypes.count >= 2 {
        for info in largeTypes {
            context.report(
                on: info.node,
                message: "\(info.name) is \(info.lineCount) lines. Only one large (>= \(args.minLines) lines) public/package type per file is allowed. Split into separate files.",
                severity: .error
            )
        }
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

    override func visitPost(_: StructDeclSyntax) { nestingLevel -= 1 }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) { nestingLevel -= 1 }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) { nestingLevel -= 1 }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(name: node.name.text, modifiers: node.modifiers, syntax: Syntax(node))
        nestingLevel += 1
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) { nestingLevel -= 1 }

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
