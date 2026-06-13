import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Detects deprecated URL initializers that use `fileURLWithPath` labels
/// and suggests migrating to `URL(filePath:)` / `URL(filePath:directoryHint:)`.
struct UseURLFilePathArgs: Codable {
    var severity: Severity = .warning
}

let useURLFilePathRule = ParameterizedRule(
    id: "use-url-file-path",
    defaultArguments: UseURLFilePathArgs(),
) { file, context, args in
    let visitor = UseURLFilePathVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class UseURLFilePathVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isURLInit(node), let deprecatedLabel = deprecatedFirstLabel(node) else {
            return .visitChildren
        }

        let replacement = deprecatedLabel == "fileURLWithPath" ? "filePath" : "filePath"
        let hint = deprecatedLabel == "fileURLWithPath:isDirectory:"
            ? " Use `URL(filePath:directoryHint:)` instead."
            : " Use `URL(filePath:)` instead."

        if let fixed = buildFixed(node: node, firstLabel: deprecatedLabel) {
            context.reportWithFix(
                on: node,
                message: "Deprecated `URL(\(deprecatedLabel):)` initializer.\(hint)",
                severity: severity,
                fixIts: [
                    FixIt.replace(
                        message: SimpleFixItMessage("Replace with `URL(\(replacement):)`"),
                        oldNode: node,
                        newNode: fixed,
                    ),
                ],
            )
        } else {
            context.report(
                on: node,
                message: "Deprecated `URL(\(deprecatedLabel):)` initializer.\(hint)",
                severity: severity,
            )
        }

        return .visitChildren
    }

    // MARK: - Detection helpers

    private func isURLInit(_ node: FunctionCallExprSyntax) -> Bool {
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text == "URL"
        }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "init"
        {
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                return base.baseName.text == "URL"
            }
            // `.init(fileURLWithPath:)` with implicit base — no type info available,
            // but this label is unique to URL's deprecated initializer so flag it.
            if memberAccess.base == nil {
                return true
            }
        }
        return false
    }

    /// Returns the deprecated label name if this call uses `fileURLWithPath` as first argument label.
    private func deprecatedFirstLabel(_ node: FunctionCallExprSyntax) -> String? {
        let args = Array(node.arguments)
        guard let first = args.first,
              let label = first.label?.text,
              label == "fileURLWithPath"
        else { return nil }

        let hasIsDirectory = args.count >= 2 && args[1].label?.text == "isDirectory"
        return hasIsDirectory ? "fileURLWithPath:isDirectory:" : "fileURLWithPath"
    }

    // MARK: - Fix-it construction

    private func buildFixed(node: FunctionCallExprSyntax, firstLabel _: String) -> FunctionCallExprSyntax? {
        var newArgs = Array(node.arguments)
        guard !newArgs.isEmpty else { return nil }

        // Replace first label: fileURLWithPath → filePath
        let firstArg = newArgs[0]
        guard let oldLabel = firstArg.label else { return nil }
        let newLabel = oldLabel.with(\.tokenKind, .identifier("filePath"))
        newArgs[0] = firstArg.with(\.label, newLabel)

        // Replace second label: isDirectory → directoryHint (if present)
        if newArgs.count >= 2, let secondLabel = newArgs[1].label, secondLabel.text == "isDirectory" {
            let newSecondLabel = secondLabel.with(\.tokenKind, .identifier("directoryHint"))
            newArgs[1] = newArgs[1].with(\.label, newSecondLabel)
        }

        let newArgList = LabeledExprListSyntax(newArgs)
        return node.with(\.arguments, newArgList)
    }
}
