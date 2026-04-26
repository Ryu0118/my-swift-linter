import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Emits a warning when property declarations within a type are not grouped
/// (1) by property wrapper and (2) by access modifier.
///
/// Sort priority:
///   1. Property wrapper name alphabetically (unwrapped properties last)
///   2. Access modifier within the same wrapper group (open → public → package → internal → fileprivate → private)
///
/// Relative declaration order within the same group is preserved (stable sort).
/// `var body` is always placed first among computed properties.
/// A Fix-It is provided to reorder automatically.
let propertyDeclarationOrderingRule = Rule(id: "property-declaration-ordering") { file, context in
    let visitor = PropertyDeclarationOrderingVisitor(context: context)
    visitor.walk(file)
}

// MARK: - Sort Key

/// Composite sort key for a property: (wrapper, accessLevel).
private struct PropertySortKey: Comparable {
    /// Wrapper name; empty string means no wrapper (sorted last via "~" sentinel).
    let wrapperName: String
    let accessLevel: AccessLevel

    private var wrapperSortKey: String {
        wrapperName.isEmpty ? "~" : wrapperName
    }

    static func < (lhs: PropertySortKey, rhs: PropertySortKey) -> Bool {
        if lhs.wrapperSortKey != rhs.wrapperSortKey {
            return lhs.wrapperSortKey < rhs.wrapperSortKey
        }
        return lhs.accessLevel < rhs.accessLevel
    }
}

// MARK: - Access Level

private enum AccessLevel: Int, Comparable {
    case open = 0
    case `public` = 1
    case package = 2
    case `internal` = 3
    case `fileprivate` = 4
    case `private` = 5

    static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Visitor

private final class PropertyDeclarationOrderingVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
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

    // MARK: - Check logic

    private func checkMemberBlock(_ memberBlock: MemberBlockSyntax, reportOn typeNode: Syntax) {
        let members = Array(memberBlock.members)
        let (storedIndices, computedIndices) = classifyProperties(members)

        guard hasViolation(members: members, stored: storedIndices, computed: computedIndices) else {
            return
        }

        let sorted = buildSortedMembersWithStoredFirst(
            members: members,
            storedIndices: storedIndices,
            computedIndices: computedIndices
        )
        let newBlock = memberBlock.with(\.members, MemberBlockItemListSyntax(sorted))

        context.reportWithFix(
            on: typeNode,
            message: "Properties should be grouped by wrapper, then access modifier."
                + " Stored before computed. var body must be first computed property.",
            severity: .warning,
            fixIts: [
                FixIt(
                    message: SimpleFixItMessage("Reorder: stored → body → other computed"),
                    changes: [.replace(oldNode: Syntax(memberBlock), newNode: Syntax(newBlock))]
                ),
            ]
        )
    }

    /// Classifies member declarations into stored and computed property index lists.
    private func classifyProperties(
        _ members: [MemberBlockItemSyntax]
    ) -> (stored: [Int], computed: [Int]) {
        var stored: [Int] = []
        var computed: [Int] = []
        for index in members.indices {
            guard let varDecl = members[index].decl.as(VariableDeclSyntax.self) else { continue }
            if isComputedProperty(varDecl) {
                computed.append(index)
            } else {
                stored.append(index)
            }
        }
        return (stored, computed)
    }

    /// Returns `true` when any ordering violation is detected:
    /// - stored properties not grouped by wrapper / access modifier
    /// - stored and computed properties interleaved
    /// - `var body` not first among computed properties
    private func hasViolation(
        members: [MemberBlockItemSyntax],
        stored: [Int],
        computed: [Int]
    ) -> Bool {
        let hasEnough = stored.count >= 2
            || (!stored.isEmpty && !computed.isEmpty)
            || computed.count >= 2
        guard hasEnough else { return false }

        if stored.count >= 2 {
            let keys = stored.map { propertySortKey(of: members[$0].decl) }
            if !isGrouped(keys) { return true }
        }
        if hasStoredComputedMixing(stored: stored, computed: computed) { return true }
        return hasBodyOrderViolation(members: members, computedIndices: computed)
    }

    private func hasStoredComputedMixing(stored: [Int], computed: [Int]) -> Bool {
        let firstStored = stored.first ?? Int.max
        let lastStored = stored.last ?? -1
        let lastComputed = computed.last ?? -1
        let storedAfterComputed = stored.contains { $0 > lastComputed && lastComputed >= 0 }
        let computedBetweenStored = computed.contains { $0 > firstStored && $0 < lastStored }
        return storedAfterComputed || computedBetweenStored
    }

    private func hasBodyOrderViolation(
        members: [MemberBlockItemSyntax],
        computedIndices: [Int]
    ) -> Bool {
        guard computedIndices.count >= 2 else { return false }
        guard let bodyIndex = computedIndices.first(where: { isBodyProperty(members[$0].decl) })
        else { return false }
        return bodyIndex != computedIndices.first
    }

    /// Returns `true` when all equal-key elements are contiguous (no interleaving).
    private func isGrouped(_ keys: [PropertySortKey]) -> Bool {
        guard keys.count >= 2 else { return true }
        if !isFieldGrouped(keys.map(\.wrapperName)) { return false }

        var currentWrapper = keys[0].wrapperName
        var currentLevels: [AccessLevel] = [keys[0].accessLevel]

        for i in 1 ..< keys.count {
            if keys[i].wrapperName == currentWrapper {
                currentLevels.append(keys[i].accessLevel)
            } else {
                if !isFieldGrouped(currentLevels) { return false }
                currentWrapper = keys[i].wrapperName
                currentLevels = [keys[i].accessLevel]
            }
        }
        return isFieldGrouped(currentLevels)
    }

    private func isFieldGrouped<T: Hashable>(_ values: [T]) -> Bool {
        guard values.count >= 2 else { return true }
        var seen = Set<T>()
        var current: T?
        for value in values where value != current {
            if seen.contains(value) { return false }
            seen.insert(value)
            current = value
        }
        return true
    }

    /// Builds the reordered member list: sorted stored properties first, then computed
    /// (with `var body` leading), non-property members stay in their original slots.
    private func buildSortedMembersWithStoredFirst(
        members: [MemberBlockItemSyntax],
        storedIndices: [Int],
        computedIndices: [Int]
    ) -> [MemberBlockItemSyntax] {
        let sortedStored = storedIndices
            .map { (index: $0, member: members[$0], key: propertySortKey(of: members[$0].decl)) }
            .sorted { $0.key < $1.key }
            .map(\.member)

        let computedMembers = sortComputedBodyFirst(members: members, computedIndices: computedIndices)

        let allPropertyIndices = (storedIndices + computedIndices).sorted()
        let reordered = sortedStored + computedMembers

        var result = members
        for (i, originalIndex) in allPropertyIndices.enumerated() {
            result[originalIndex] = reordered[i]
        }
        return result
    }

    private func propertySortKey(of decl: DeclSyntax) -> PropertySortKey {
        PropertySortKey(wrapperName: wrapperName(of: decl), accessLevel: accessLevel(of: decl))
    }

    /// Returns the first property wrapper name, or empty string if none.
    private func wrapperName(of decl: DeclSyntax) -> String {
        guard let varDecl = decl.as(VariableDeclSyntax.self) else { return "" }
        for attribute in varDecl.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let identType = attr.attributeName.as(IdentifierTypeSyntax.self)
            {
                return identType.name.text
            }
        }
        return ""
    }

    /// Returns `true` when the variable has an accessor block (computed property).
    private func isComputedProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.bindings.contains { $0.accessorBlock != nil }
    }

    private func isBodyProperty(_ decl: DeclSyntax) -> Bool {
        guard let varDecl = decl.as(VariableDeclSyntax.self) else { return false }
        return varDecl.bindings.contains { $0.pattern.trimmedDescription == "body" }
    }

    /// Places `var body` first; preserves relative order of remaining computed properties.
    private func sortComputedBodyFirst(
        members: [MemberBlockItemSyntax],
        computedIndices: [Int]
    ) -> [MemberBlockItemSyntax] {
        guard let bodyIdx = computedIndices.first(where: { isBodyProperty(members[$0].decl) })
        else {
            return computedIndices.map { members[$0] }
        }
        let bodyMember = members[bodyIdx]
        let rest = computedIndices.filter { $0 != bodyIdx }.map { members[$0] }
        return [bodyMember] + rest
    }

    /// Returns the access level of a property declaration; defaults to `internal` when unspecified.
    private func accessLevel(of decl: DeclSyntax) -> AccessLevel {
        guard let varDecl = decl.as(VariableDeclSyntax.self) else { return .internal }
        for modifier in varDecl.modifiers {
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
