import SwiftASTLint
import SwiftSyntax

/// The rule set applied across the entire project.
public let rules = RuleSet {
    deepNestingRule
    singleLargeTypePerFileRule
    propertyDeclarationOrderingRule
    functionAccessModifierGroupingRule
    swiftUIViewPropertyRule
    branchAssignmentToTupleRule
    noTopLevelFunctionRule
}
