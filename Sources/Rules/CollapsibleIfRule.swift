import SwiftASTLint
import SwiftSyntax

/// Flags an `if` (or `guard`) whose body contains nothing but a single, else-less
/// nested `if` — a nesting level that adds no branching of its own and can be
/// merged into the outer condition list.
///
/// Not flagged:
/// - either the outer or inner `if` has an `else` clause (merging would change behavior)
/// - the outer body has statements besides the nested `if`
/// - the outer `if` is labeled (merging would drop the label)
/// - the nested `if` sits inside another control-flow construct (e.g. `for`), not directly in the body
///
/// Optional-binding shadowing (`if let x = a { if let x = x.child { ... } }`) is still
/// flagged, since the nesting is still redundant, but the diagnostic notes that a
/// mechanical merge would produce a redeclaration and must be done by hand.
let collapsibleIfRule = Rule(id: "collapsible-if", description: "Detects an if/guard whose body contains only a single else-less nested if, which can be merged into the outer condition list.") { file, context in
    let visitor = CollapsibleIfVisitor(context: context)
    visitor.walk(file)
}

private final class CollapsibleIfVisitor: SyntaxVisitor {
    let context: LintContext

    init(context: LintContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        check(outerConditions: node.conditions, outerElse: node.elseBody, body: node.body, isLabeled: isLabeled(node))
        return .visitChildren
    }

    /// An `if` reached via `label: if ... { }` has a `LabeledStmtSyntax` as its
    /// grandparent (the `if` sits inside an `ExpressionStmtSyntax` inside the label).
    private func isLabeled(_ node: IfExprSyntax) -> Bool {
        node.parent?.as(ExpressionStmtSyntax.self)?.parent?.as(LabeledStmtSyntax.self) != nil
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        checkGuardFollowedBySingleIf(node)
        return .visitChildren
    }

    /// Handles `guard ... else { ... }` immediately followed by a single, else-less
    /// `if` as the *rest* of the enclosing block — the guard's early-exit condition
    /// and the following if's condition can be merged into one `guard`.
    private func checkGuardFollowedBySingleIf(_ items: CodeBlockItemListSyntax) {
        var iterator = items.makeIterator()
        var previousWasGuard: GuardStmtSyntax?
        while let item = iterator.next() {
            defer {
                previousWasGuard = item.item.as(GuardStmtSyntax.self)
            }
            guard let guardStmt = previousWasGuard else { continue }
            guard let innerIf = item.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) else {
                continue
            }
            guard innerIf.elseBody == nil, !isLabeled(innerIf) else { continue }
            // Only a violation when the if is the sole remaining statement after the guard.
            guard items.index(after: items.firstIndex(of: item)!) == items.endIndex else { continue }

            let shadowed = shadowedNames(outer: guardStmt.conditions, inner: innerIf.conditions)
            let message = collapsibleMessage(shadowed: shadowed, kind: "guard")
            context.report(on: innerIf, message: message, severity: .warning)
        }
    }

    private func check(
        outerConditions: ConditionElementListSyntax,
        outerElse: IfExprSyntax.ElseBody?,
        body: CodeBlockSyntax,
        isLabeled: Bool
    ) {
        guard outerElse == nil else { return }
        guard !isLabeled else { return }
        guard body.statements.count == 1 else { return }
        guard let onlyStatement = body.statements.first else { return }
        guard let innerIf = onlyStatement.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) else {
            return
        }
        guard innerIf.elseBody == nil else { return }

        let shadowed = shadowedNames(outer: outerConditions, inner: innerIf.conditions)
        context.report(on: innerIf, message: collapsibleMessage(shadowed: shadowed, kind: "if"), severity: .warning)
    }

    private func collapsibleMessage(shadowed: String?, kind: String) -> String {
        let base = "This \(kind) only wraps a single nested if with no else branch; merge the conditions with `,`."
        guard let shadowed else { return base }
        return base
            + " Note: `\(shadowed)` is bound in both conditions (shadowing), so a mechanical merge"
            + " would redeclare it — rename or restructure by hand."
    }

    private func shadowedNames(outer: ConditionElementListSyntax, inner: ConditionElementListSyntax) -> String? {
        let outerNames = boundNames(in: outer)
        let innerNames = boundNames(in: inner)
        return outerNames.first { innerNames.contains($0) }
    }

    private func boundNames(in conditions: ConditionElementListSyntax) -> Set<String> {
        var names: Set<String> = []
        for condition in conditions {
            if let binding = condition.condition.as(OptionalBindingConditionSyntax.self),
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                names.insert(pattern.identifier.text)
            }
        }
        return names
    }
}
