import SwiftASTLint
import SwiftSyntax

/// Forbids file-scope (top-level) function declarations.
///
/// Top-level functions live outside of any type, extension, or protocol body.
/// This rule treats them as a smell because they hide ownership: they're
/// effectively globals reachable from any file in the module. Move helpers
/// onto an existing type, extract them into a `private extension` of a
/// caller's type, or wrap them in a dedicated namespace `enum`.
///
/// Examples flagged:
/// ```swift
/// func helper() { ... }                  // ← top-level
/// private func cacheKey() -> String { }  // ← top-level (still flagged)
/// ```
///
/// Examples allowed:
/// ```swift
/// extension Foo {
///     func helper() { ... }              // member of Foo
/// }
///
/// enum Helpers {
///     static func cacheKey() -> String { } // namespaced static
/// }
/// ```
let noTopLevelFunctionRule = Rule(id: "no-top-level-function") { file, context in
    for statement in file.statements {
        guard let funcDecl = statement.item.as(FunctionDeclSyntax.self) else { continue }
        context.report(
            on: funcDecl.name,
            message: "Top-level function '\(funcDecl.name.text)' is not allowed. " +
                "Move it onto a type/extension or wrap it in a namespace enum.",
            severity: .error,
        )
    }
}
