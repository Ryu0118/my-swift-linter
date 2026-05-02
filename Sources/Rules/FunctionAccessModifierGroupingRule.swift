import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Emits a warning when function declarations within a type are not grouped by access modifier.
///
/// Expected order: open → public → package → internal (implicit) → fileprivate → private
///
/// Relative declaration order within the same access level is preserved (stable sort).
/// A Fix-It is provided to reorder automatically.
/// init / deinit / subscript are excluded; only regular `func` declarations are checked.
struct FunctionAccessModifierGroupingArgs: Codable {
    var severity: Severity = .warning
}

let functionAccessModifierGroupingRule = ParameterizedRule(
    id: "function-access-modifier-grouping",
    defaultArguments: FunctionAccessModifierGroupingArgs(),
) { file, context, args in
    let visitor = FunctionAccessGroupingVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Access Level

private enum FuncAccessLevel: Int, Comparable {
    case open = 0
    case `public` = 1
    case package = 2
    case `internal` = 3
    case `fileprivate` = 4
    case `private` = 5

    static func < (lhs: FuncAccessLevel, rhs: FuncAccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Visitor

private final class FunctionAccessGroupingVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    // MARK: - Check

    private func checkMemberBlock(
        _ memberBlock: MemberBlockSyntax,
        reportOn typeNode: Syntax,
    ) {
        let members = Array(memberBlock.members)
        let funcIndices = members.indices.filter { members[$0].decl.as(FunctionDeclSyntax.self) != nil }
        guard funcIndices.count >= 2 else { return }

        let levels = funcIndices.map { accessLevel(of: members[$0].decl) }
        guard !isGrouped(levels) else { return }

        let sorted = buildSorted(members: members, funcIndices: funcIndices)
        let newBlock = memberBlock.with(\.members, MemberBlockItemListSyntax(sorted))

        context.reportWithFix(
            on: typeNode,
            message: "Functions should be grouped by access modifier"
                + " (open → public → package → internal → fileprivate → private).",
            severity: severity,
            fixIts: [
                FixIt(
                    message: SimpleFixItMessage("Group functions by access modifier"),
                    changes: [.replace(oldNode: Syntax(memberBlock), newNode: Syntax(newBlock))],
                ),
            ],
        )
    }

    // MARK: - Grouping check

    private func isGrouped(_ levels: [FuncAccessLevel]) -> Bool {
        guard levels.count >= 2 else { return true }
        var seen = Set<FuncAccessLevel>()
        var current: FuncAccessLevel?
        for level in levels where level != current {
            if seen.contains(level) { return false }
            seen.insert(level)
            current = level
        }
        return true
    }

    // MARK: - Sort

    /// Stable-sorts function declarations by access level, preserving non-function member positions.
    private func buildSorted(
        members: [MemberBlockItemSyntax],
        funcIndices: [Int],
    ) -> [MemberBlockItemSyntax] {
        let sortedFuncs = funcIndices
            .map { (index: $0, member: members[$0], level: accessLevel(of: members[$0].decl)) }
            .sorted { $0.level < $1.level }
            .map(\.member)

        var result = members
        for (idx, originalIndex) in funcIndices.enumerated() {
            result[originalIndex] = sortedFuncs[idx]
        }
        return result
    }

    // MARK: - Access level extraction

    /// Returns the access level of a function declaration; defaults to `internal` when unspecified.
    private func accessLevel(of decl: DeclSyntax) -> FuncAccessLevel {
        guard let funcDecl = decl.as(FunctionDeclSyntax.self) else { return .internal }
        for modifier in funcDecl.modifiers {
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
        return .internal
    }
}
