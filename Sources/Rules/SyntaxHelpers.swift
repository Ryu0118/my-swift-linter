import SwiftSyntax

/// Suffixes commonly appended to test-suite type names.
///
/// Shared by every rule that reasons about suite base names so the rules
/// never disagree about what the "base name" of a suite type is.
let testSuiteNameSuffixes = ["Tests", "Test", "Spec"]

/// Returns the type name with a common test-suite suffix stripped, unless
/// stripping would leave the name empty (e.g. a type named exactly `Tests`).
func strippedTestSuiteName(_ name: String) -> String {
    for suffix in testSuiteNameSuffixes
    where name.hasSuffix(suffix) && name.count > suffix.count {
        return String(name.dropLast(suffix.count))
    }
    return name
}

extension AttributeListSyntax {
    /// Returns the first attribute with the given simple name (e.g. `Test`, `Suite`).
    func attribute(named name: String) -> AttributeSyntax? {
        for element in self {
            guard case let .attribute(attr) = element,
                  let id = attr.attributeName.as(IdentifierTypeSyntax.self),
                  id.name.text == name
            else { continue }
            return attr
        }
        return nil
    }
}

extension AttributeSyntax {
    /// The first plain string-literal argument of the attribute, if any.
    /// Returns `nil` for interpolated strings, non-string arguments, or missing arguments.
    var plainStringArgument: String? {
        guard case let .argumentList(args) = arguments else { return nil }
        for arg in args {
            guard let stringLit = arg.expression.as(StringLiteralExprSyntax.self) else { continue }
            guard stringLit.segments.count == 1,
                  let first = stringLit.segments.first,
                  case let .stringSegment(seg) = first
            else { return nil }
            return seg.content.text
        }
        return nil
    }
}
