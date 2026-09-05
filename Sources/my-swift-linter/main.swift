import Rules
import SwiftASTLint

await Linter.lint(rules, defaultConfigFileName: ".my-swift-linter.yml")
