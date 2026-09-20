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

/// Returns `(lhs, rhs)` when `expr` is a plain assignment (`lhs = rhs`), or `(lhs, rhs)` with
/// `isCompound: true` when it's a compound assignment (`lhs += rhs`, etc.) and `allowCompound`
/// is `true`. Returns `nil` otherwise.
///
/// The parser represents `lhs = rhs` in statement position as a `SequenceExprSyntax` with
/// exactly three elements `[lhs, AssignmentExprSyntax, rhs]` — it is not folded into an
/// `InfixOperatorExprSyntax` at this parsing stage — so both shapes must be handled. This same
/// gotcha is independently worked around in `BranchAssignmentToTupleRule.assignedName(from:)`;
/// any future SwiftSyntax parsing-shape change to assignment expressions must be fixed in both
/// places (that file predates this shared helper and has not been migrated onto it).
func assignmentOperands(_ expr: ExprSyntax, allowCompound: Bool = false) -> (lhs: ExprSyntax, rhs: ExprSyntax)? {
    if let infix = expr.as(InfixOperatorExprSyntax.self) {
        if infix.operator.is(AssignmentExprSyntax.self) {
            return (infix.leftOperand, infix.rightOperand)
        }
        if allowCompound, isCompoundAssignmentOperator(infix.operator) {
            return (infix.leftOperand, infix.rightOperand)
        }
        return nil
    }
    if let sequence = expr.as(SequenceExprSyntax.self) {
        // The sequence is flat, not a tree: `f.x = a + 1` parses as five elements
        // `[f.x, =, a, +, 1]`, not three. Assignment has the lowest precedence in Swift, so `=`
        // (or a compound-assignment operator) is always at index 1 in a legal sequence and
        // everything from index 2 onward is the RHS, however many tokens it spans.
        let elements = Array(sequence.elements)
        guard elements.count >= 3 else { return nil }
        let isPlainAssignment = elements[1].is(AssignmentExprSyntax.self)
        let isCompoundAssignment = allowCompound && isCompoundAssignmentOperator(elements[1])
        guard isPlainAssignment || isCompoundAssignment else { return nil }
        let rhs = elements.count == 3
            ? elements[2]
            : ExprSyntax(SequenceExprSyntax(elements: ExprListSyntax(elements[2...])))
        return (elements[0], rhs)
    }
    return nil
}

private func isCompoundAssignmentOperator(_ expr: ExprSyntax) -> Bool {
    guard let binaryOperator = expr.as(BinaryOperatorExprSyntax.self) else { return false }
    let text = binaryOperator.operator.text
    guard text.hasSuffix("=") else { return false }
    return !["==", "!=", "<=", ">="].contains(text)
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
