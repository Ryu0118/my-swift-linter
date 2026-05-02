import SwiftASTLint
import SwiftSyntax

// MARK: - Args

struct MissingDocsArgs: Codable {
    /// Minimum access level that requires a doc comment.
    /// Valid values: "open", "public", "package", "internal", "fileprivate", "private"
    var minAccessLevel: String = "package"
    var severity: Severity = .warning

    enum CodingKeys: String, CodingKey {
        case minAccessLevel = "min_access_level"
        case severity
    }

    init(minAccessLevel: String = "package", severity: Severity = .warning) {
        self.minAccessLevel = minAccessLevel
        self.severity = severity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minAccessLevel = try container.decodeIfPresent(String.self, forKey: .minAccessLevel) ?? "package"
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .warning
    }
}

// MARK: - Rule

let missingDocsRule = ParameterizedRule(
    id: "missing-docs",
    defaultArguments: MissingDocsArgs(),
) { file, context, args in
    let threshold = AccessLevel(rawValue: args.minAccessLevel) ?? .public
    let visitor = MissingDocsVisitor(context: context, threshold: threshold, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Access level

private enum AccessLevel: String, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open

    private var rank: Int {
        switch self {
        case .private: 0
        case .fileprivate: 1
        case .internal: 2
        case .package: 3
        case .public: 4
        case .open: 5
        }
    }

    static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - Visitor

private final class MissingDocsVisitor: SyntaxVisitor {
    let context: LintContext
    let threshold: AccessLevel
    let severity: Severity

    init(context: LintContext, threshold: AccessLevel, severity: Severity) {
        self.context = context
        self.threshold = threshold
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    // MARK: Function / init / subscript

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: "init")
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: "subscript")
        return .visitChildren
    }

    // MARK: Variable

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.bindings.first?.pattern.trimmedDescription ?? "variable"
        check(modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: name)
        return .visitChildren
    }

    // MARK: Core check

    private func check(
        modifiers: DeclModifierListSyntax,
        trivia: Trivia,
        node: Syntax,
        name: String,
    ) {
        guard let level = explicitAccessLevel(from: modifiers) else { return }
        guard level >= threshold else { return }
        guard !hasDocComment(trivia) else { return }

        context.report(
            on: node,
            message: "\(name) has \(level.rawValue) access but is missing a doc comment.",
            severity: severity,
        )
    }

    /// Returns the explicit access level from the modifier list, or nil if none written.
    private func explicitAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.open): return .open
            case .keyword(.public): return .public
            case .keyword(.package): return .package
            case .keyword(.internal): return .internal
            case .keyword(.fileprivate): return .fileprivate
            case .keyword(.private): return .private
            default: continue
            }
        }
        return nil
    }

    /// Returns true if the trivia contains a doc line comment (`///`) or doc block comment (`/** */`).
    private func hasDocComment(_ trivia: Trivia) -> Bool {
        for piece in trivia {
            switch piece {
            case .docLineComment, .docBlockComment:
                return true
            default:
                continue
            }
        }
        return false
    }
}
