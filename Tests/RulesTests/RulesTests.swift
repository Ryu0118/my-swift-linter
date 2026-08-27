@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@Suite("Registered rule metadata")
struct RulesTests {
    @Test("Every registered rule has a non-empty description")
    func everyRuleHasDescription() {
        #expect(!rules.rules.isEmpty)
        #expect(rules.rules.allSatisfy { rule in
            guard let description = rule.description else { return false }
            return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }
}
