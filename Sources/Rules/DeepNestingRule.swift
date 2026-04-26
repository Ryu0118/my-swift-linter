import SwiftASTLint
import SwiftSyntax

struct DeepNestingArgs: Codable {
    var maxDepth: Int = 3
    enum CodingKeys: String, CodingKey {
        case maxDepth = "max_depth"
    }
}

/// Emits an error when control flow nesting exceeds `maxDepth`.
/// Counted constructs: if / guard / for / while / switch / do.
/// Depth resets at function, initializer, accessor, and closure boundaries.
let deepNestingRule = ParameterizedRule(
    id: "deep-nesting",
    defaultArguments: DeepNestingArgs()
) { file, context, args in
    let visitor = DeepNestingVisitor(maxDepth: args.maxDepth, context: context)
    visitor.walk(file)
}

private final class DeepNestingVisitor: SyntaxVisitor {
    let maxDepth: Int
    let context: LintContext
    private var depth = 0

    init(maxDepth: Int, context: LintContext) {
        self.maxDepth = maxDepth
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
        if depth >= maxDepth {
            context.report(
                on: node,
                message: "Nesting depth is \(depth) (max: \(maxDepth)). Extract into a separate function.",
                severity: .error
            )
        }
    }
}
