import SwiftASTLint
import SwiftSyntax

struct DeepNestingArgs: Codable {
    /// Nesting depth at which a warning is emitted. Must be less than `error_depth`.
    var warningDepth: Int = 3
    /// Nesting depth at which an error is emitted.
    var errorDepth: Int = 5

    enum CodingKeys: String, CodingKey {
        case warningDepth = "warning_depth"
        case errorDepth = "error_depth"
    }
}

/// Emits a warning or error when control flow nesting exceeds a threshold.
/// Counted constructs: if / guard / for / while / switch / do.
/// Depth resets at function, initializer, accessor, and closure boundaries.
///
/// Configure via YAML:
/// ```yaml
/// rules:
///   deep-nesting:
///     args:
///       warning_depth: 3
///       error_depth: 5
/// ```
let deepNestingRule = ParameterizedRule(
    id: "deep-nesting",
    defaultArguments: DeepNestingArgs()
) { file, context, args in
    let visitor = DeepNestingVisitor(warningDepth: args.warningDepth, errorDepth: args.errorDepth, context: context)
    visitor.walk(file)
}

private final class DeepNestingVisitor: SyntaxVisitor {
    let warningDepth: Int
    let errorDepth: Int
    let context: LintContext
    private var depth = 0

    init(warningDepth: Int, errorDepth: Int, context: LintContext) {
        self.warningDepth = warningDepth
        self.errorDepth = errorDepth
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Nesting nodes

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: IfExprSyntax) {
        depth -= 1
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: GuardStmtSyntax) {
        depth -= 1
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: ForStmtSyntax) {
        depth -= 1
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: WhileStmtSyntax) {
        depth -= 1
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: SwitchExprSyntax) {
        depth -= 1
    }

    override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind {
        incrementAndCheck(node)
        return .visitChildren
    }

    override func visitPost(_: DoStmtSyntax) {
        depth -= 1
    }

    // MARK: - Depth reset boundaries

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let saved = depth
        depth = 0
        if let body = node.body { walk(Syntax(body)) }
        depth = saved
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let saved = depth
        depth = 0
        if let body = node.body { walk(Syntax(body)) }
        depth = saved
        return .skipChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        let saved = depth
        depth = 0
        if let body = node.body { walk(Syntax(body)) }
        depth = saved
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let saved = depth
        depth = 0
        walk(Syntax(node.statements))
        depth = saved
        return .skipChildren
    }

    // MARK: - Helper

    private func incrementAndCheck(_ node: some SyntaxProtocol) {
        depth += 1
        if depth >= errorDepth {
            context.report(
                on: node,
                message: "Nesting depth is \(depth) (error threshold: \(errorDepth))."
                    + " Extract into a separate function.",
                severity: .error
            )
        } else if depth >= warningDepth {
            context.report(
                on: node,
                message: "Nesting depth is \(depth) (warning threshold: \(warningDepth))."
                    + " Consider extracting into a separate function.",
                severity: .warning
            )
        }
    }
}
