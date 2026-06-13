# my-swift-linter

A collection of general-purpose Swift lint rules built on [swift-ast-lint](https://github.com/Ryu0118/swift-ast-lint).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Ryu0118/my-swift-linter/main/install.sh | bash
```

### Nest ([mtj0928/nest](https://github.com/mtj0928/nest))

```bash
nest install Ryu0118/my-swift-linter
```

### Mise ([jdx/mise](https://github.com/jdx/mise))

```bash
mise use -g ubi:Ryu0118/my-swift-linter
```

### Build from source

Requires Swift 6.2+ and macOS 15+.

```bash
git clone https://github.com/Ryu0118/my-swift-linter.git
cd my-swift-linter
swift build -c release
```

## Rules

| Rule ID | Default Severity | Configurable | Description |
|---------|-----------------|:------------:|-------------|
| `deep-nesting` | warning / error | ✓ | Flags control flow nesting — warning at depth ≥ `warning_depth` (default: 3), error at depth ≥ `error_depth` (default: 5) |
| `single-large-type-per-file` | warning / error | ✓ | Flags files with two or more large public/package types — warning at ≥ `warning_lines` lines (default: 50), error at ≥ `error_lines` lines (default: 100) |
| `property-declaration-ordering` | warning | ✓ | Properties must be grouped by property wrapper, then by access modifier |
| `function-access-modifier-grouping` | warning | ✓ | Functions must be grouped by access modifier (open → public → … → private) |
| `swiftui-view-property` | error | ✓ | `return` is forbidden in `some View` properties; `@ViewBuilder` is required when the body contains top-level `let`/`var`/`if`/`switch` |
| `branch-assignment-to-tuple` | warning | ✓ | Detects uninitialized `let` declarations followed by an `if`/`switch` that assigns every variable in every branch — collapse into an expression-form `let` |
| `no-top-level-function` | error | ✓ | Forbids file-scope `func` declarations regardless of access modifier — move helpers onto a type, into an extension, or inside a namespace `enum` |
| `return-if-expression` | warning | ✓ | Detects multi-branch `if`/`else` blocks where every branch contains a single `return <expr>` — collapse into `return if { … } else { … }` |
| `return-switch-expression` | warning | ✓ | Detects `switch` blocks where every case contains a single `return <expr>` — collapse into `return switch { … }` |
| `use-url-file-path` | warning | ✓ | Flags deprecated `URL(fileURLWithPath:)` initializer — use `URL(filePath:)` (iOS 16+ / macOS 13+) instead |
| `missing-docs` | error | ✓ | Flags declarations missing a doc comment — configurable minimum access level and ignore patterns |
| `meaningful-suite-description` | error | ✓ | Flags `@Suite` descriptions that are identical to the type name (or the name minus a `Tests`/`Test`/`Spec` suffix) — write a description that explains what the suite tests |
| `test-function-naming` | error | ✓ | Flags `@Test` functions whose name is a backtick-quoted phrase — use lowerCamelCase and move the description into `@Test("…")` |

### deep-nesting

Emits an error when control flow constructs (`if`, `guard`, `for`, `while`, `switch`, `do`) are nested beyond `max_depth`. Depth resets at function, initializer, accessor, and closure boundaries.

```swift
// ❌ error (default max_depth: 3)
func process() {
    if a {
        for b in list {
            if c {
                if d { /* depth 4 */ }
            }
        }
    }
}

// ✅ extract into a helper
func process() {
    if a {
        for b in list {
            handleItem(b)
        }
    }
}
```

**Configuration**

```yaml
rules:
  deep-nesting:
    args:
      warning_depth: 3   # default
      error_depth: 5     # default
```

### single-large-type-per-file

Emits an error when two or more `public`/`package` types (enum, struct, class, actor) each exceeding `min_lines` lines appear in the same file.

```swift
// ❌ error — two large types in one file
public struct NetworkClient { /* 60 lines */ }
public struct CacheManager  { /* 55 lines */ }

// ✅ split into separate files
```

**Configuration**

```yaml
rules:
  single-large-type-per-file:
    args:
      warning_lines: 50    # default
      error_lines: 100     # default
```

### property-declaration-ordering

Properties within a type must be sorted first by property wrapper (alphabetically, unwrapped properties last), then by access modifier within each wrapper group.

**Configuration**

```yaml
rules:
  property-declaration-ordering:
    args:
      severity: error   # default: warning
```

```swift
// ❌ warning
struct MyView: View {
    var title: String
    @State private var isLoading = false
    @Binding var isPresented: Bool
}

// ✅
struct MyView: View {
    @Binding var isPresented: Bool
    @State private var isLoading = false
    var title: String
}
```

A Fix-It is provided to reorder automatically.

### function-access-modifier-grouping

Function declarations within a type must be grouped in descending access order: `open → public → package → internal → fileprivate → private`. `init`, `deinit`, and `subscript` are excluded.

**Configuration**

```yaml
rules:
  function-access-modifier-grouping:
    args:
      severity: error   # default: warning
```

```swift
// ❌ warning
struct Service {
    private func helper() {}
    public func fetch() {}
}

// ✅
struct Service {
    public func fetch() {}
    private func helper() {}
}
```

A Fix-It is provided to reorder automatically.

### swiftui-view-property

**Pattern A — `return` is forbidden** in `some View` computed properties, with or without `@ViewBuilder`.

**Pattern B — `@ViewBuilder` is required** when the body contains top-level `let`/`var` declarations, `if` expressions, or `switch` expressions.

`var body: some View` is exempt because `View.body` already has an implicit `@ViewBuilder` from the protocol.

```swift
// ❌ error — Pattern A
private var label: some View {
    return Text("Hello")
}

// ❌ error — Pattern B: top-level if without @ViewBuilder
private var content: some View {
    if isLoading {
        ProgressView()
    } else {
        Text("Done")
    }
}

// ✅
@ViewBuilder
private var content: some View {
    if isLoading {
        ProgressView()
    } else {
        Text("Done")
    }
}
```

Fix-Its are provided: remove `return` for Pattern A, insert `@ViewBuilder` for Pattern B.

**Configuration**

```yaml
rules:
  swiftui-view-property:
    args:
      severity: warning   # default: error
```

### branch-assignment-to-tuple

Detects the pattern of declaring one or more uninitialized `let` variables followed by an `if`/`switch` whose every branch only contains simple assignments to those variables. The whole block can be collapsed into an expression-form `let` binding (with a tuple when several variables are involved).

```swift
// ❌ warning — single variable
let hoge: Int
if let x {
    hoge = x
} else {
    hoge = y
}

// ✅
let hoge = if let x { x } else { y }

// ❌ warning — multiple variables
let days: Int
let pages: Int
if let duration {
    days = duration.days
    pages = duration.numPages
} else {
    days = period.days
    pages = period.pages
}

// ✅
let (days, pages) = if let duration {
    (duration.days, duration.numPages)
} else {
    (period.days, period.pages)
}
```

No Fix-It is provided because branch-level side effects may prevent a mechanical rewrite.

**Configuration**

```yaml
rules:
  branch-assignment-to-tuple:
    args:
      severity: error   # default: warning
```

### no-top-level-function

Forbids file-scope (top-level) `func` declarations. Top-level functions hide ownership and become module-wide globals reachable from any file. Move helpers onto an existing type, into an `extension`, or wrap them in a namespace `enum`.

```swift
// ❌ error — top-level func, even private ones
private func cacheKey(for id: String) -> String { ... }

// ✅ — namespaced helper
enum CacheKey {
    static func make(for id: String) -> String { ... }
}

// ✅ — extension on the caller type
extension UserRepository {
    fileprivate func cacheKey(for id: String) -> String { ... }
}
```

Functions inside a `struct`/`class`/`actor`/`enum`/`protocol`/`extension`, and nested functions inside another function body, are not flagged. No Fix-It is provided because choosing the right home is a judgement call.

**Configuration**

```yaml
rules:
  no-top-level-function:
    args:
      severity: warning   # default: error
```

### return-if-expression

Detects when consecutive `return` statements cover all branches of an `if`/`else-if*/else` chain and suggests collapsing them into a single `return if … { expr } else { expr }`.

Triggers only when:
- The chain terminates in a plain `else { … }` (not `else if`)
- Every branch body contains exactly one `return <expr>` (non-bare `return`)

```swift
// ❌ warning
func label(_ n: Int) -> String {
    if n < 0 {
        return "negative"
    } else if n == 0 {
        return "zero"
    } else {
        return "positive"
    }
}

// ✅ (auto-fixed)
func label(_ n: Int) -> String {
    return if n < 0 { "negative" } else if n == 0 { "zero" } else { "positive" }
}
```

A Fix-It is provided.

**Configuration**

```yaml
rules:
  return-if-expression:
    args:
      severity: error   # default: warning
```

### use-url-file-path

`URL(fileURLWithPath:)` was deprecated in iOS 16 / macOS 13. Use the replacement initializer `URL(filePath:)` which accepts a `String`, `FilePath`, or other typed path.

```swift
// ❌ warning
let url = URL(fileURLWithPath: path)
let url = URL(fileURLWithPath: path, relativeTo: base)
let url = .init(fileURLWithPath: path)

// ✅
let url = URL(filePath: path)
```

No Fix-It is provided because the replacement may require a `FilePath` import.

**Configuration**

```yaml
rules:
  use-url-file-path:
    args:
      severity: error   # default: warning
```

### meaningful-suite-description

`@Suite` accepts a description string to document what the test suite covers. Writing just the type name (or type name minus a `Tests`/`Test`/`Spec` suffix) adds no value over the default synthesised label.

```swift
// ❌ error — description is just the type name
@Suite("CheckRunner")
struct CheckRunnerTests { … }

// ❌ error — exact match
@Suite("MyFeature")
struct MyFeature { … }

// ✅ — describes what the suite verifies
@Suite("meaningful-suite-description: detects @Suite descriptions that duplicate the type name")
struct MeaningfulSuiteDescriptionRuleTests { … }

// ✅ — trait-only, no description
@Suite(.serialized)
struct CheckRunnerTests { … }
```

Applies to `struct`, `class`, `actor`, and `extension`. No Fix-It is provided — choosing a meaningful description requires human judgement.

**Configuration**

```yaml
rules:
  meaningful-suite-description:
    args:
      severity: warning   # default: error
```

### test-function-naming

`@Test` functions whose name is a backtick-quoted natural-language phrase add no value over a proper `@Test("…")` description string, and make it impossible to call the function directly. Use lowerCamelCase for the function name and put the human-readable description in the `@Test` label.

```swift
// ❌ error
@Test
func `claudeHookOutput blocks when outOfSync with default message`() {}

// ❌ error — description present but name is still a quoted phrase
@Test("claudeHookOutput blocks when outOfSync with default message")
func `claudeHookOutput blocks when outOfSync with default message`() {}

// ✅
@Test("claudeHookOutput blocks when outOfSync with default message")
func claudeHookOutputBlocksWhenOutOfSyncWithDefaultMessage() {}
```

Backtick-escaped Swift keywords with no spaces (e.g. `` func `default`() ``) are not flagged. No Fix-It is provided because choosing a camelCase name requires human judgement.

**Configuration**

```yaml
rules:
  test-function-naming:
    args:
      severity: warning   # default: error
```

### missing-docs

Flags declarations with explicit access level at or above `min_access_level` that are missing a doc comment (`///` or `/** */`).

Applies to: `struct`, `class`, `actor`, `enum`, `protocol`, `typealias`, `func`, `init`, `subscript`, and `var`/`let` declarations.

```swift
// ❌ error (default min_access_level: package)
public struct NetworkClient {
    public func fetch() {}
}

// ✅
/// Handles HTTP network requests.
public struct NetworkClient {
    /// Fetches data from the given URL.
    public func fetch() {}
}
```

**Configuration**

```yaml
rules:
  missing-docs:
    args:
      min_access_level: public   # default: package
      severity: warning          # default: error
      ignore_patterns:
        - kinds: [var, let]
          modifiers: [static]
          names: [liveValue, previewValue, testValue]
```

**`ignore_patterns`**

Each entry in `ignore_patterns` suppresses violations for declarations that match all specified fields. Omitting a field is a wildcard (matches anything).

| Field | Type | Match | Description |
|-------|------|-------|-------------|
| `kinds` | `[String]` | OR | Declaration kind: `"var"`, `"let"`, `"func"`, `"init"`, `"subscript"`, `"struct"`, `"class"`, `"actor"`, `"enum"`, `"protocol"`, `"typealias"` |
| `modifiers` | `[String]` | AND | All listed modifiers must be present: `"static"`, `"class"`, `"override"`, `"final"` |
| `names` | `[String]` | OR | Exact declaration name |

```yaml
# Suppress doc-comment requirement for TCA DependencyKey boilerplate
ignore_patterns:
  - kinds: [var, let]
    modifiers: [static]
    names: [liveValue, previewValue, testValue]

# Suppress for all static vars named "shared" regardless of type
  - kinds: [var]
    modifiers: [static]
    names: [shared]

# Suppress for any declaration named "placeholder" (wildcard kinds/modifiers)
  - names: [placeholder]
```

## Usage

### Run the linter

```bash
swift run --package-path /path/to/my-swift-linter swift-ast-lint /path/to/your/Sources
```

### Apply auto-fixes

```bash
swift run --package-path /path/to/my-swift-linter swift-ast-lint /path/to/your/Sources --fix
```

### Configure via YAML

Place a `.swift-ast-lint.yml` in the root of your project:

```yaml
rules:
  deep-nesting:
    args:
      warning_depth: 3
      error_depth: 5
    include:
      - "Sources/**"
    exclude:
      - "**/*Generated.swift"
  single-large-type-per-file:
    args:
      warning_lines: 50
      error_lines: 100
```

## Requirements

- Swift 6.2+
- macOS 15+

## License

MIT
