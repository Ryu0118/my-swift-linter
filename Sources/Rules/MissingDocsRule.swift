import SwiftASTLint
import SwiftSyntax

// MARK: - IgnorePattern

/// A pattern that suppresses missing-docs violations for matching declarations.
///
/// All fields are optional; omitting a field is a wildcard (matches anything).
/// - `kinds`: OR match — declaration must be one of the listed kinds.
/// - `modifiers`: AND match — declaration must have ALL listed modifiers.
/// - `names`: OR match — declaration name must be one of the listed names.
struct IgnorePattern: Codable {
    /// Declaration kind: "var", "let", "func", "init", "subscript",
    /// "struct", "class", "actor", "enum", "protocol", "typealias"
    var kinds: [String]?
    /// Modifier keywords that must ALL be present, e.g. ["static"].
    var modifiers: [String]?
    /// Declaration names to match (exact), e.g. ["liveValue", "previewValue"].
    var names: [String]?

    func matches(kind: String, modifiers: Set<String>, name: String) -> Bool {
        if let kinds, !kinds.contains(kind) { return false }
        if let requiredModifiers = self.modifiers, !requiredModifiers.allSatisfy({ modifiers.contains($0) }) {
            return false
        }
        if let names, !names.contains(name) { return false }
        return true
    }
}

// MARK: - Args

struct MissingDocsArgs: Codable {
    /// Minimum access level that requires a doc comment.
    /// Valid values: "open", "public", "package", "internal", "fileprivate", "private"
    var minAccessLevel: String = "package"
    var severity: Severity = .error
    /// Patterns for declarations to skip, regardless of access level.
    var ignorePatterns: [IgnorePattern] = []

    enum CodingKeys: String, CodingKey {
        case minAccessLevel = "min_access_level"
        case severity
        case ignorePatterns = "ignore_patterns"
    }

    init(minAccessLevel: String = "package", severity: Severity = .error, ignorePatterns: [IgnorePattern] = []) {
        self.minAccessLevel = minAccessLevel
        self.severity = severity
        self.ignorePatterns = ignorePatterns
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minAccessLevel = try container.decodeIfPresent(String.self, forKey: .minAccessLevel) ?? "package"
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .error
        ignorePatterns = try container.decodeIfPresent([IgnorePattern].self, forKey: .ignorePatterns) ?? []
    }
}

// MARK: - Rule

let missingDocsRule = ParameterizedRule(
    id: "missing-docs",
    defaultArguments: MissingDocsArgs(),
) { file, context, args in
    let threshold = AccessLevel(rawValue: args.minAccessLevel) ?? .public
    let visitor = MissingDocsVisitor(
        context: context,
        threshold: threshold,
        severity: args.severity,
        ignorePatterns: args.ignorePatterns
    )
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
    let ignorePatterns: [IgnorePattern]

    init(context: LintContext, threshold: AccessLevel, severity: Severity, ignorePatterns: [IgnorePattern]) {
        self.context = context
        self.threshold = threshold
        self.severity = severity
        self.ignorePatterns = ignorePatterns
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "struct",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "class",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "actor",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "enum",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "protocol",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "typealias",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    // MARK: Function / init / subscript

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "func",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        check(kind: "init", modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: "init")
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            kind: "subscript",
            modifiers: node.modifiers,
            trivia: node.leadingTrivia,
            node: Syntax(node),
            name: "subscript"
        )
        return .visitChildren
    }

    // MARK: Variable

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.bindings.first?.pattern.trimmedDescription ?? "variable"
        let kind = node.bindingSpecifier.tokenKind == .keyword(.var) ? "var" : "let"
        check(kind: kind, modifiers: node.modifiers, trivia: node.leadingTrivia, node: Syntax(node), name: name)
        return .visitChildren
    }

    // MARK: Core check

    private func check(
        kind: String,
        modifiers: DeclModifierListSyntax,
        trivia: Trivia,
        node: Syntax,
        name: String,
    ) {
        guard let level = explicitAccessLevel(from: modifiers) else { return }
        guard level >= threshold else { return }
        guard !hasDocComment(trivia) else { return }

        let modifierSet = modifierKeywords(from: modifiers)
        guard !ignorePatterns.contains(where: { $0.matches(kind: kind, modifiers: modifierSet, name: name) }) else {
            return
        }

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

    /// Extracts modifier keywords (static, class, override, final) as a Set of strings.
    private func modifierKeywords(from modifiers: DeclModifierListSyntax) -> Set<String> {
        Set(modifiers.compactMap { modifier -> String? in
            switch modifier.name.tokenKind {
            case .keyword(.static): "static"
            case .keyword(.class): "class"
            case .keyword(.override): "override"
            case .keyword(.final): "final"
            default: nil
            }
        })
    }
}
