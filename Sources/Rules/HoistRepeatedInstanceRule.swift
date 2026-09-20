import SwiftASTLint
import SwiftSyntax

struct HoistRepeatedInstanceArgs: Codable {
    var severity: Severity = .error
    /// Minimum number of equivalent occurrences required before reporting. Values below 2 are
    /// clamped to 2 (a single occurrence can never be "repeated").
    var minimumOccurrences: Int = 2
    /// Closed allowlist of type names this rule looks for. Configuring this REPLACES the
    /// default list entirely rather than extending it.
    ///
    /// The default list is restricted to Foundation types confirmed `Sendable`-clean when
    /// hoisted to an instance stored property under Swift 6 strict concurrency. Types known to
    /// be non-`Sendable` (`ISO8601DateFormatter`, `RelativeDateTimeFormatter`,
    /// `ByteCountFormatter`, `MeasurementFormatter`, `ListFormatter`) are intentionally excluded
    /// — hoisting one of those to a stored property can silently remove a type's implicit
    /// `Sendable` conformance, which is a behavior change this rule must not recommend.
    var types: [String] = HoistRepeatedInstanceArgs.defaultTypes
    /// When `true` (default), a construction with zero configuration statements still counts as
    /// an occurrence (the repeated allocation itself is the problem). Set to `false` to only
    /// flag repeated *configured* construction.
    var flagUnconfigured: Bool = true

    static let defaultTypes = [
        "JSONDecoder",
        "JSONEncoder",
        "PropertyListDecoder",
        "PropertyListEncoder",
        "DateFormatter",
        "NumberFormatter",
        "DateComponentsFormatter",
        "DateIntervalFormatter",
        "PersonNameComponentsFormatter",
    ]

    enum CodingKeys: String, CodingKey {
        case severity
        case minimumOccurrences = "minimum_occurrences"
        case types
        case flagUnconfigured = "flag_unconfigured"
    }

    init(
        severity: Severity = .error,
        minimumOccurrences: Int = 2,
        types: [String] = HoistRepeatedInstanceArgs.defaultTypes,
        flagUnconfigured: Bool = true
    ) {
        self.severity = severity
        self.minimumOccurrences = minimumOccurrences
        self.types = types
        self.flagUnconfigured = flagUnconfigured
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .error
        let rawMinimum = try container.decodeIfPresent(Int.self, forKey: .minimumOccurrences) ?? 2
        minimumOccurrences = max(rawMinimum, 2)
        types = try container.decodeIfPresent([String].self, forKey: .types) ?? Self.defaultTypes
        flagUnconfigured = try container.decodeIfPresent(Bool.self, forKey: .flagUnconfigured) ?? true
    }
}

/// Detects a "configure this utility object" local variable — a `let`/`var` constructed with a
/// zero-argument initializer of an allowlisted type, optionally followed by simple property
/// assignments — that is repeated with equivalent construction and configuration across two or
/// more instance members (functions, initializers, computed properties, subscripts) of the same
/// `struct`/`class`/`actor`.
///
/// Each occurrence re-allocates and re-configures an object that could instead be a single
/// instance stored property, shared across every call:
///
/// ```swift
/// // ❌ constructed and configured identically in two functions
/// struct Foo {
///     func decode(_ data: Data) throws -> Bar {
///         let jsonDecoder = JSONDecoder()
///         jsonDecoder.dateDecodingStrategy = .iso8601
///         return try jsonDecoder.decode(Bar.self, from: data)
///     }
///     func decodeOther(_ data: Data) throws -> Baz {
///         let jsonDecoder = JSONDecoder()
///         jsonDecoder.dateDecodingStrategy = .iso8601
///         return try jsonDecoder.decode(Baz.self, from: data)
///     }
/// }
///
/// // ✅
/// struct Foo {
///     private let jsonDecoder: JSONDecoder = {
///         let decoder = JSONDecoder()
///         decoder.dateDecodingStrategy = .iso8601
///         return decoder
///     }()
///     func decode(_ data: Data) throws -> Bar {
///         try jsonDecoder.decode(Bar.self, from: data)
///     }
///     ...
/// }
/// ```
///
/// Only **instance** members are considered in v1 — `static func`s and enum namespaces are out
/// of scope (a different group key and message would be needed for `static let`).
///
/// Configure via YAML:
/// ```yaml
/// rules:
///   hoist-repeated-instance:
///     args:
///       severity: error
///       minimum_occurrences: 2
///       flag_unconfigured: true
///       types:
///         - JSONDecoder
///         - JSONEncoder
/// ```
let hoistRepeatedInstanceRule = ParameterizedRule(
    id: "hoist-repeated-instance",
    description: "Detects a configurable utility object (e.g. JSONDecoder) constructed and configured identically in two or more instance members of the same type, which should be hoisted to an instance stored property.",
    defaultArguments: HoistRepeatedInstanceArgs()
) { file, context, args in
    let collector = HoistRepeatedInstanceCollector(allowedTypes: Set(args.types))
    collector.walk(file)
    // Only structs/classes/actors (or their extensions) that have a primary declaration in this
    // file can host a hoisted stored property. This must run after `walk` completes, since a
    // primary declaration can appear anywhere in the file relative to its extensions.
    let validRecords = collector.records.filter { collector.primaryTypeNames.contains($0.containerName) }
    report(
        records: validRecords,
        minimumOccurrences: args.minimumOccurrences,
        flagUnconfigured: args.flagUnconfigured,
        severity: args.severity,
        context: context
    )
}

// MARK: - Record

/// One local-variable occurrence that survived every disqualification check.
private struct Occurrence {
    let containerName: String
    let typeName: String
    /// Sorted `(lhsPathText, rhsTokenText)` pairs — order-independent equivalence key.
    let signature: [String: String]
    let declaration: VariableDeclSyntax
}

/// `[String: String]`'s synthesized `Hashable`/`Equatable` conformance is already
/// order-independent over its key-value pairs, so no manual conformance is needed here.
private struct GroupKey: Hashable {
    let containerName: String
    let typeName: String
    let signature: [String: String]
}

// MARK: - Reporting

private func report(
    records: [Occurrence],
    minimumOccurrences: Int,
    flagUnconfigured: Bool,
    severity: Severity,
    context: LintContext
) {
    var groups: [GroupKey: [Occurrence]] = [:]
    for record in records {
        if record.signature.isEmpty, !flagUnconfigured { continue }
        let key = GroupKey(containerName: record.containerName, typeName: record.typeName, signature: record.signature)
        groups[key, default: []].append(record)
    }

    // Dictionary iteration order is not deterministic across runs; collect every diagnostic to
    // emit first, then sort by source position so output order is stable and readable top-to-bottom.
    var pending: [(declaration: VariableDeclSyntax, message: String)] = []
    for (key, occurrences) in groups {
        guard occurrences.count >= minimumOccurrences else { continue }
        let message = message(for: key, count: occurrences.count)
        for occurrence in occurrences {
            pending.append((declaration: occurrence.declaration, message: message))
        }
    }

    pending.sort { $0.declaration.positionAfterSkippingLeadingTrivia < $1.declaration.positionAfterSkippingLeadingTrivia }
    for entry in pending {
        context.report(on: entry.declaration, message: entry.message, severity: severity)
    }
}

private func message(for key: GroupKey, count: Int) -> String {
    let propertyName = lowercasedFirstLetter(key.typeName)
    if key.signature.isEmpty {
        return "\(key.typeName) is constructed with no configuration in \(count) places in `\(key.containerName)`; "
            + "hoist it to a stored property: `private let \(propertyName) = \(key.typeName)()`."
    }
    let properties = key.signature.keys.sorted().joined(separator: ", ")
    return "\(key.typeName) is constructed with identical configuration (\(properties)) in \(count) places in "
        + "`\(key.containerName)`; hoist it to a stored property: `private let \(propertyName): \(key.typeName) = "
        + "{ let \(lowercasedFirstLetter(key.typeName, fallback: "value")) = \(key.typeName)(); ...; "
        + "return \(lowercasedFirstLetter(key.typeName, fallback: "value")) }()`. "
        + "Confirm the configuration does not depend on instance state."
}

/// Converts a type name into a suggested property name: `JSONDecoder` → `jsonDecoder`,
/// `DateFormatter` → `dateFormatter`, `PropertyListDecoder` → `propertyListDecoder`. Lowercases
/// the leading run of uppercase letters, keeping the last one uppercase-turned-lowercase-boundary
/// letter attached to the following word when a lowercase letter follows it (so an acronym
/// prefix like "JSON" splits as "json" + "Decoder", not "jSONDecoder" or "jsondecoder").
private func lowercasedFirstLetter(_ name: String, fallback: String? = nil) -> String {
    let chars = Array(name)
    guard !chars.isEmpty else { return fallback ?? name }

    var uppercaseRunEnd = 0
    while uppercaseRunEnd < chars.count, chars[uppercaseRunEnd].isUppercase {
        uppercaseRunEnd += 1
    }
    guard uppercaseRunEnd > 0 else { return name }

    // A single leading uppercase letter (e.g. "Decoder"): lowercase just that letter.
    if uppercaseRunEnd == 1 {
        return chars[0].lowercased() + String(chars.dropFirst())
    }

    // A multi-letter acronym prefix (e.g. "JSONDecoder"): if a lowercase letter follows the run,
    // the last uppercase letter belongs to the next word ("JSON" + "Decoder" -> "json" + "Decoder").
    let runEndsWithNextWord = uppercaseRunEnd < chars.count
    let lowercaseBoundary = runEndsWithNextWord ? uppercaseRunEnd - 1 : uppercaseRunEnd
    let prefix = String(chars[0..<lowercaseBoundary]).lowercased()
    let suffix = String(chars[lowercaseBoundary...])
    return prefix + suffix
}

// MARK: - Collector

private final class HoistRepeatedInstanceCollector: SyntaxVisitor {
    let allowedTypes: Set<String>
    private(set) var records: [Occurrence] = []

    /// Stack of enclosing struct/class/actor names, plus extensions of them. An extension of a
    /// type with no primary struct/class/actor declaration in this file (including a protocol
    /// extension, since a protocol has no primary decl in `primaryTypeNames`) records
    /// provisionally during the walk and is filtered out afterward once `primaryTypeNames` is
    /// complete — declarations can appear in any order in the file.
    private var containerStack: [String] = []
    /// Names of struct/class/actor primary declarations seen anywhere in the file. Complete only
    /// once the whole file has been walked.
    private(set) var primaryTypeNames: Set<String> = []

    /// Stack of (isStatic, boundNames) for enclosing instance/static members (func/init/subscript/
    /// accessor) — used to disqualify RHS expressions that reference a parameter or local name,
    /// and to exclude static members from v1 scope.
    private var memberStack: [(isStatic: Bool, boundNames: Set<String>)] = []
    /// Parallel stack recording, per `ClosureExprSyntax`, whether `visit` pushed a new
    /// `memberStack` frame for it — a closure encountered with no enclosing member never does.
    private var closurePushedFrame: [Bool] = []

    /// Per-container set of stored/computed property names declared directly in that container's
    /// member block (collected as we go; used for the "bare name matches an instance property"
    /// disqualification).
    private var containerPropertyNames: [String: Set<String>] = [:]

    init(allowedTypes: Set<String>) {
        self.allowedTypes = allowedTypes
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Container tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushContainer(name: node.name.text, isExtension: false)
        collectMemberNames(in: node.memberBlock)
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) { popContainer() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushContainer(name: node.name.text, isExtension: false)
        collectMemberNames(in: node.memberBlock)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) { popContainer() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushContainer(name: node.name.text, isExtension: false)
        collectMemberNames(in: node.memberBlock)
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) { popContainer() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = extendedTypeName(node.extendedType)
        pushContainer(name: name, isExtension: true)
        collectMemberNames(in: node.memberBlock)
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) { popContainer() }

    /// Enums cannot hold stored instance properties (a hoisted `private let` has nowhere to go),
    /// so members declared directly inside an `enum` must not be attributed to any enclosing
    /// struct/class/actor container. Push an empty container name — `scan` already skips
    /// occurrences whose container name is empty.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushContainer(name: "", isExtension: true)
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) { popContainer() }

    /// A `protocol` declaration itself never hosts members with executable bodies that matter
    /// here, but push an empty container defensively for symmetry and in case of default
    /// implementations written directly in the protocol body in future Swift versions.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushContainer(name: "", isExtension: true)
        return .visitChildren
    }

    override func visitPost(_: ProtocolDeclSyntax) { popContainer() }

    private func pushContainer(name: String, isExtension: Bool) {
        if !isExtension { primaryTypeNames.insert(name) }
        containerStack.append(name)
    }

    private func popContainer() {
        containerStack.removeLast()
    }

    private func extendedTypeName(_ type: TypeSyntax) -> String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return type.trimmedDescription
    }

    /// Collects the names of instance stored/computed properties AND instance methods declared
    /// directly in this container's member block — a bare identifier in an RHS expression can
    /// resolve to either, and both are equally unreachable from a stored-property initializer.
    private func collectMemberNames(in memberBlock: MemberBlockSyntax) {
        let containerName = containerStack.last ?? ""
        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard !hasStaticModifier(varDecl.modifiers) else { continue }
                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        containerPropertyNames[containerName, default: []].insert(pattern.identifier.text)
                    }
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                guard !hasStaticModifier(funcDecl.modifiers) else { continue }
                containerPropertyNames[containerName, default: []].insert(funcDecl.name.text)
            }
        }
    }

    // MARK: Member tracking (instance-only; static members are pushed as disqualified scope)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = hasStaticModifier(node.modifiers)
        var names = parameterNames(node.signature.parameterClause)
        if let body = node.body { names.formUnion(allLocalNames(in: body)) }
        pushMember(isStatic: isStatic, boundNames: names)
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) { popMember() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        var names = parameterNames(node.signature.parameterClause)
        if let body = node.body { names.formUnion(allLocalNames(in: body)) }
        pushMember(isStatic: false, boundNames: names)
        return .visitChildren
    }

    override func visitPost(_: InitializerDeclSyntax) { popMember() }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = hasStaticModifier(node.modifiers)
        var names = parameterNames(node.parameterClause)
        names.formUnion(allLocalNames(in: node.accessorBlock))
        pushMember(isStatic: isStatic, boundNames: names)
        return .visitChildren
    }

    override func visitPost(_: SubscriptDeclSyntax) { popMember() }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = memberStack.last?.isStatic ?? isAccessorOfStaticProperty(node)
        var names: Set<String> = []
        if let body = node.body { names.formUnion(allLocalNames(in: body)) }
        pushMember(isStatic: isStatic, boundNames: names)
        return .visitChildren
    }

    private func isAccessorOfStaticProperty(_ node: AccessorDeclSyntax) -> Bool {
        guard let varDecl = nearestAncestor(of: Syntax(node), as: VariableDeclSyntax.self) else { return false }
        return hasStaticModifier(varDecl.modifiers)
    }

    override func visitPost(_: AccessorDeclSyntax) { popMember() }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        // A computed property's getter body without an explicit `get {}` accessor block is
        // reached via the binding's own `.getter`/`.getterEffectAccessor` initializer form.
        if case let .getter(body) = node.accessorBlock?.accessors {
            let isStatic = memberStack.last?.isStatic ?? isPropertyStatic(node)
            pushMember(isStatic: isStatic, boundNames: allLocalNames(in: body))
            walk(Syntax(body))
            popMember()
            return .skipChildren
        }
        return .visitChildren
    }

    /// A `PatternBindingSyntax.initializer` at container scope (not inside any member) is a
    /// stored-property initializer — e.g. `private let x: T = { ... }()` or `lazy var y = {...}()`.
    /// It must never be scanned as an "occurrence site": that is exactly the shape this rule
    /// recommends as the fix, and scanning it would make the rule self-flagging.
    override func visit(_ node: InitializerClauseSyntax) -> SyntaxVisitorContinueKind {
        guard memberStack.isEmpty else { return .visitChildren }
        return .skipChildren
    }

    private func isPropertyStatic(_ node: PatternBindingSyntax) -> Bool {
        guard let varDecl = nearestAncestor(of: Syntax(node), as: VariableDeclSyntax.self) else { return false }
        return hasStaticModifier(varDecl.modifiers)
    }

    /// Walks upward from `node` (exclusive) to find the nearest ancestor of type `T`.
    private func nearestAncestor<T: SyntaxProtocol>(of node: Syntax, as type: T.Type) -> T? {
        var current = node.parent
        while let candidate = current {
            if let match = candidate.as(T.self) { return match }
            current = candidate.parent
        }
        return nil
    }

    private func hasStaticModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    private func parameterNames(_ clause: FunctionParameterClauseSyntax) -> Set<String> {
        Set(clause.parameters.map(\.secondNameOrFirst))
    }

    private func pushMember(isStatic: Bool, boundNames: Set<String>) {
        memberStack.append((isStatic: isStatic, boundNames: boundNames))
    }

    private func popMember() {
        memberStack.removeLast()
    }

    // MARK: Closures — extend bound-name scope, without introducing a new member

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        guard let current = memberStack.last else {
            closurePushedFrame.append(false)
            return .visitChildren
        }
        let closureParamNames = closureParameterNames(node.signature)
        memberStack.append((isStatic: current.isStatic, boundNames: current.boundNames.union(closureParamNames)))
        closurePushedFrame.append(true)
        return .visitChildren
    }

    override func visitPost(_: ClosureExprSyntax) {
        guard closurePushedFrame.removeLast() else { return }
        popMember()
    }

    private func closureParameterNames(_ signature: ClosureSignatureSyntax?) -> Set<String> {
        guard let clause = signature?.parameterClause else { return [] }
        switch clause {
        case let .simpleInput(list):
            return Set(list.map(\.name.text))
        case let .parameterClause(list):
            return Set(list.parameters.map { $0.secondName?.text ?? $0.firstName.text })
        }
    }

    // MARK: Statement-list scanning

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        guard let (isStatic, boundNames) = memberStack.last, !isStatic else { return .visitChildren }
        scan(items: Array(node), boundNames: boundNames)
        return .visitChildren
    }

    private func scan(items: [CodeBlockItemSyntax], boundNames: Set<String>) {
        for index in items.indices {
            guard let varDecl = items[index].item.as(VariableDeclSyntax.self) else { continue }
            guard let candidate = candidate(from: varDecl) else { continue }

            let prefixResult = readConfigurationPrefix(
                variableName: candidate.name,
                items: items,
                startIndex: index + 1,
                boundNames: boundNames
            )
            guard case let .success(signature, prefixEnd) = prefixResult else { continue }

            guard isUseAfterPrefixSafe(
                variableName: candidate.name,
                items: items,
                prefixEnd: prefixEnd
            ) else { continue }

            let containerName = containerStack.last ?? ""
            guard !containerName.isEmpty else { continue }

            records.append(Occurrence(
                containerName: containerName,
                typeName: candidate.typeName,
                signature: signature,
                declaration: varDecl
            ))
        }
    }

    /// Local `let`/`var` names and optional-binding pattern names declared anywhere in this
    /// statement list — used to disqualify RHS expressions that reference a same-scope local.
    /// Every `let`/`var`/optional-binding/closure-parameter identifier declared anywhere within
    /// `node` — used to seed a member's `boundNames` up front so a local declared in one nested
    /// block (e.g. inside an `if`) still disqualifies an RHS reference to it from a sibling block
    /// in the same member. A stored-property initializer cannot see any of these, so any bare
    /// reference to one is a real "cannot hoist" signal, not just a same-block heuristic.
    private func allLocalNames(in node: (some SyntaxProtocol)?) -> Set<String> {
        guard let node else { return [] }
        let collector = LocalNameCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        return collector.names
    }

    // MARK: Candidate detection

    private struct Candidate {
        let name: String
        let typeName: String
    }

    private func candidate(from varDecl: VariableDeclSyntax) -> Candidate? {
        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else { return nil }
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        guard let initializer = binding.initializer else { return nil }
        guard let typeName = zeroArgumentConstructedType(
            expression: initializer.value,
            annotatedType: binding.typeAnnotation?.type
        ) else { return nil }
        guard allowedTypes.contains(typeName) else { return nil }
        return Candidate(name: pattern.identifier.text, typeName: typeName)
    }

    /// Recognizes `T()`, `T.init()`, and `let x: T = .init()`. Only zero-argument calls qualify.
    private func zeroArgumentConstructedType(expression: ExprSyntax, annotatedType: TypeSyntax?) -> String? {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        guard call.arguments.isEmpty, call.trailingClosure == nil else { return nil }

        if let identifier = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return identifier.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            guard member.declName.baseName.tokenKind == .keyword(.`init`) else { return nil }
            if let base = member.base {
                return moduleQualifiedTypeName(base)
            }
            // Implicit member `.init()` — requires the type annotation to resolve the type.
            if let annotatedType, let name = simpleTypeName(annotatedType) {
                return name
            }
        }
        return nil
    }

    private func moduleQualifiedTypeName(_ expression: ExprSyntax) -> String? {
        if let identifier = expression.as(DeclReferenceExprSyntax.self) {
            return identifier.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private func simpleTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    // MARK: Configuration prefix

    private enum PrefixResult {
        case success(signature: [String: String], prefixEnd: Int)
        case disqualified
    }

    /// Reads the maximal run of `x.<path> = <rhs>` statements starting at `startIndex`, where
    /// `x` is `variableName`. Stops at the first statement that isn't this shape. Returns the
    /// index just past the prefix (== startIndex when there is no configuration at all).
    private func readConfigurationPrefix(
        variableName: String,
        items: [CodeBlockItemSyntax],
        startIndex: Int,
        boundNames: Set<String>
    ) -> PrefixResult {
        var signature: [String: String] = [:]
        var index = startIndex

        while index < items.count {
            guard let assignment = simpleAssignment(items[index], base: variableName) else { break }
            guard signature[assignment.path] == nil else { return .disqualified }
            guard isHoistable(rhs: assignment.rhs, boundNames: boundNames) else { return .disqualified }
            signature[assignment.path] = assignment.rhsText
            index += 1
        }

        return .success(signature: signature, prefixEnd: index)
    }

    private struct Assignment {
        let path: String
        let rhs: ExprSyntax
        let rhsText: String
    }

    /// Matches `x.<member path, possibly with subscripts> = <rhs>` as a plain assignment
    /// (compound assignment operators like `+=` are intentionally excluded).
    private func simpleAssignment(_ item: CodeBlockItemSyntax, base variableName: String) -> Assignment? {
        guard let expr = expressionStatement(item) else { return nil }
        guard let (lhs, rhs) = assignmentOperands(expr) else { return nil }
        guard let path = memberPath(lhs, base: variableName) else { return nil }
        let rhsText = tokenText(rhs)
        return Assignment(path: path, rhs: rhs, rhsText: rhsText)
    }

    /// Extracts the dotted/subscript path text (excluding the base) when `expr` is `x.a.b`,
    /// `x.a[b]`, etc., rooted at `base`.
    private func memberPath(_ expr: ExprSyntax, base variableName: String) -> String? {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return nil }
            if let baseRef = base.as(DeclReferenceExprSyntax.self), baseRef.baseName.text == variableName {
                return member.declName.baseName.text
            }
            guard let parentPath = memberPath(base, base: variableName) else { return nil }
            return parentPath + "." + member.declName.baseName.text
        }
        if let subscriptCall = expr.as(SubscriptCallExprSyntax.self) {
            guard let parentPath = memberPath(subscriptCall.calledExpression, base: variableName) else {
                // The subscript is directly on the base: x[...]
                if let baseRef = subscriptCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   baseRef.baseName.text == variableName {
                    return "[" + tokenText(subscriptCall.arguments) + "]"
                }
                return nil
            }
            return parentPath + "[" + tokenText(subscriptCall.arguments) + "]"
        }
        return nil
    }

    private func expressionStatement(_ item: CodeBlockItemSyntax) -> ExprSyntax? {
        if let stmt = item.item.as(StmtSyntax.self), let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
            return exprStmt.expression
        }
        if let expr = item.item.as(ExprSyntax.self) {
            return expr
        }
        return nil
    }

    private func tokenText(_ node: some SyntaxProtocol) -> String {
        node.tokens(viewMode: .sourceAccurate).map(\.text).joined(separator: " ")
    }

    // MARK: Hoistability of an RHS expression

    /// An RHS is safe to lift into a stored-property initializer when it does not reference
    /// `self`, and does not reference any bare name bound as a parameter, local, or closure
    /// parameter in the enclosing member (a stored-property initializer cannot see those).
    private func isHoistable(rhs: ExprSyntax, boundNames: Set<String>) -> Bool {
        var disqualified = false

        class Checker: SyntaxVisitor {
            let boundNames: Set<String>
            let containerPropertyNames: Set<String>
            var disqualified = false

            init(boundNames: Set<String>, containerPropertyNames: Set<String>) {
                self.boundNames = boundNames
                self.containerPropertyNames = containerPropertyNames
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                if node.baseName.tokenKind == .keyword(.`self`) {
                    disqualified = true
                    return .skipChildren
                }
                // Only a *bare* reference counts (not the `.member` name after a MemberAccessExprSyntax,
                // which is a different token position and not visited as this node's parent case).
                if let parent = node.parent, parent.is(MemberAccessExprSyntax.self),
                   parent.as(MemberAccessExprSyntax.self)?.declName.baseName == node.baseName {
                    return .visitChildren
                }
                let name = node.baseName.text
                if boundNames.contains(name) || containerPropertyNames.contains(name) {
                    disqualified = true
                }
                return .visitChildren
            }
        }

        let containerName = containerStack.last ?? ""
        let checker = Checker(boundNames: boundNames, containerPropertyNames: containerPropertyNames[containerName] ?? [])
        checker.walk(rhs)
        disqualified = checker.disqualified
        return !disqualified
    }

    // MARK: Use-after-configuration safety

    /// After the configuration prefix, the only permitted references to `variableName` are as
    /// the base of a member access / member call, and not inside a nested closure or nested
    /// function declaration. Any bare use (return, argument, assignment target/source,
    /// reassignment, capture) disqualifies the whole occurrence.
    private func isUseAfterPrefixSafe(variableName: String, items: [CodeBlockItemSyntax], prefixEnd: Int) -> Bool {
        for index in prefixEnd..<items.count {
            if !isUseSafe(in: items[index], variableName: variableName) { return false }
        }
        return true
    }

    private func isUseSafe(in item: CodeBlockItemSyntax, variableName: String) -> Bool {
        var safe = true

        class Checker: SyntaxVisitor {
            let variableName: String
            var safe = true
            var closureDepth = 0
            var functionDepth = 0

            init(variableName: String) {
                self.variableName = variableName
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                closureDepth += 1
                return .visitChildren
            }

            override func visitPost(_: ClosureExprSyntax) { closureDepth -= 1 }

            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                functionDepth += 1
                return .visitChildren
            }

            override func visitPost(_: FunctionDeclSyntax) { functionDepth -= 1 }

            override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                guard node.baseName.text == variableName else { return .visitChildren }

                if closureDepth > 0 || functionDepth > 0 {
                    safe = false
                    return .skipChildren
                }

                // Climb the member-access/subscript chain rooted at `x` (e.g. `x.userInfo[...]`)
                // to its outermost expression, then check whether THAT is the left side of an
                // assignment — this catches `x.prop = v` (a mutation reachable outside the
                // configuration prefix, which is unsafe to hoist) while still allowing a bare
                // read/call chain like `x.decode(...)`.
                var top: ExprSyntax = ExprSyntax(node)
                while let parent = top.parent {
                    if let member = parent.as(MemberAccessExprSyntax.self), member.base?.id == top.id {
                        top = ExprSyntax(member)
                        continue
                    }
                    if let subscriptCall = parent.as(SubscriptCallExprSyntax.self), subscriptCall.calledExpression.id == top.id {
                        top = ExprSyntax(subscriptCall)
                        continue
                    }
                    break
                }

                // `top`'s enclosing expression is the assignment itself (either
                // `InfixOperatorExprSyntax` or the raw `SequenceExprSyntax` form) when `top` is
                // its LHS — reuse the shared assignment-shape helper, allowing compound
                // assignment (`+=`) too, since either kind mutates a shared property at call
                // time and is unsafe to hoist.
                if let enclosing = top.parent?.parent?.as(ExprSyntax.self),
                   let (lhs, _) = assignmentOperands(enclosing, allowCompound: true),
                   lhs.id == top.id
                {
                    safe = false
                    return .skipChildren
                }

                // Allowed: base of a member access/subscript chain used as a call or read, as
                // long as the chain isn't itself the target of an assignment (checked above) and
                // `x` isn't further embedded as a bare argument or aliased elsewhere.
                if top.id != ExprSyntax(node).id {
                    return .visitChildren
                }

                // Anything else (return, bare argument, assignment RHS/LHS alias, etc.) escapes.
                safe = false
                return .skipChildren
            }
        }

        let checker = Checker(variableName: variableName)
        checker.walk(item)
        safe = checker.safe
        return safe
    }
}

private extension FunctionParameterSyntax {
    var secondNameOrFirst: String {
        (secondName ?? firstName).text
    }
}

/// Collects every `let`/`var`/optional-binding/closure-parameter identifier declared anywhere in
/// the walked subtree.
private final class LocalNameCollector: SyntaxVisitor {
    var names: Set<String> = []

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.identifier.text)
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }

    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }
}
