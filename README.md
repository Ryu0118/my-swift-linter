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
| `deep-nesting` | error | ✓ | Flags control flow nesting — error at depth ≥ `error_depth` (default: 3); `warning_depth` can be configured separately |
| `single-large-type-per-file` | error | ✓ | Flags files with two or more large public/package types — error at ≥ `error_lines` lines (default: 50); `warning_lines` can be configured separately |
| `property-declaration-ordering` | error | ✓ | Properties must be grouped by property wrapper, then by access modifier |
| `function-access-modifier-grouping` | error | ✓ | Functions must be grouped by access modifier (open → public → … → private) |
| `swiftui-view-property` | error | ✓ | `return` is forbidden in `some View` properties; `@ViewBuilder` is required when the body contains top-level `let`/`var`/`if`/`switch` |
| `branch-assignment-to-tuple` | error | ✓ | Detects uninitialized `let` declarations followed by an `if`/`switch` that assigns every variable in every branch — collapse into an expression-form `let` |
| `no-top-level-function` | error | ✓ | Forbids file-scope `func` declarations regardless of access modifier — move helpers onto a type, into an extension, or inside a namespace `enum` |
| `return-if-expression` | error | ✓ | Detects multi-branch `if`/`else` blocks where every branch contains a single `return <expr>` — collapse into `return if { … } else { … }` |
| `return-switch-expression` | error | ✓ | Detects `switch` blocks where every case contains a single `return <expr>` — collapse into `return switch { … }` |
| `use-url-file-path` | error | ✓ | Flags deprecated `URL(fileURLWithPath:)` initializer — use `URL(filePath:)` (iOS 16+ / macOS 13+) instead |
| `missing-docs` | error | ✓ | Flags declarations missing a doc comment — configurable minimum access level and ignore patterns |
| `meaningful-suite-description` | error | ✓ | Flags `@Suite` descriptions that are identical to the type name (or the name minus a `Tests`/`Test`/`Spec` suffix) — write a description that explains what the suite tests |
| `test-function-naming` | error | ✓ | Flags `@Test` functions whose name is a backtick-quoted phrase, underscore-separated, or starts with `test` — use lowerCamelCase and move the description into `@Test("…")` |
| `test-description-matches-name` | error | ✓ | Flags `@Test`/`@Suite` descriptions that do not correspond to the function/type name — the description must be the natural-language form of the name |

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
      error_depth: 3     # default
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
      error_lines: 50      # default
```

### property-declaration-ordering

Properties within a type must be sorted first by property wrapper (alphabetically, unwrapped properties last), then by access modifier within each wrapper group.

**Configuration**

```yaml
rules:
  property-declaration-ordering:
    args:
      severity: error   # default
```

```swift
// ❌ error
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
      severity: error   # default
```

```swift
// ❌ error
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

`var body: some View` and `func body(content:) -> some View` are exempt because `View.body` and `ViewModifier.body(content:)` already have an implicit `@ViewBuilder` from their protocol requirements.

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
// ❌ error — single variable
let hoge: Int
if let x {
    hoge = x
} else {
    hoge = y
}

// ✅
let hoge = if let x { x } else { y }

// ❌ error — multiple variables
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
      severity: error   # default
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
// ❌ error
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
      severity: error   # default
```

### return-switch-expression

Detects when every `switch` case contains exactly one `return <expr>` and suggests collapsing the statement into a single `return switch …` expression.

```swift
// ❌ error
func mappedValue(_ input: Input) -> Int {
    switch input {
    case .first:
        return 1
    case .second:
        return 2
    case .third:
        return 3
    }
}

// ✅ (auto-fixed)
func mappedValue(_ input: Input) -> Int {
    return switch input {
    case .first:
        1
    case .second:
        2
    case .third:
        3
    }
}
```

A Fix-It is provided.

**Configuration**

```yaml
rules:
  return-switch-expression:
    args:
      severity: error   # default
```

### use-url-file-path

`URL(fileURLWithPath:)` was deprecated in iOS 16 / macOS 13. Use the replacement initializer `URL(filePath:)` which accepts a `String`, `FilePath`, or other typed path.

```swift
// ❌ error
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
      severity: error   # default
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

`@Test` function names should be lowerCamelCase, with any human-readable description placed in the `@Test("…")` label. This rule flags three naming patterns that obscure intent or are redundant on a `@Test` function:

- **Backtick-quoted phrase** (spaces) — adds no value over a `@Test("…")` description and can't be called directly.
- **Underscore-separated** — not idiomatic Swift naming.
- **`test` prefix** (case-insensitive) — redundant, since the function is already marked `@Test`.

```swift
// ❌ error — backtick-quoted phrase
@Test
func `claudeHookOutput blocks when outOfSync`() {}

// ❌ error — underscore-separated
@Test
func decode_returnsValue() {}

// ❌ error — starts with "test" (redundant on @Test)
@Test
func testClaudeHookOutput() {}

// ✅
@Test("claudeHookOutput blocks when outOfSync")
func claudeHookOutputBlocksWhenOutOfSync() {}
```

Backtick-escaped Swift keywords with no spaces (e.g. `` func `default`() ``) are not flagged, and `test` only triggers as a prefix (`validateTestInput` is fine). A name matching multiple patterns is reported once. No Fix-It is provided because choosing a camelCase name requires human judgement.

**Configuration**

Each pattern can be toggled independently (all default `true`).

```yaml
rules:
  test-function-naming:
    args:
      severity: warning        # default: error
      check_spaces: true        # flag backtick-quoted phrases
      check_underscores: true   # flag underscore-separated names
      check_test_prefix: true   # flag names starting with "test"
```

### test-description-matches-name

A `@Test("…")` description that doesn't match its function name (or a `@Suite("…")` description unrelated to its type name) misleads readers and test reports. This rule verifies the correspondence.

Both sides are normalized before comparing — everything except ASCII letters and digits is removed and the result is lowercased — so punctuation (`re-applied` vs `reapplied`) and camelCase boundaries don't require an exact derivation.

- **`@Test`**: the normalized description must **equal** the normalized function name.
- **`@Suite`**: the normalized description must **contain** the normalized type name after stripping a `Tests`/`Test`/`Spec` suffix. For qualified extension names (`extension Foo.BarTests`), only the last path component is compared.

```swift
// ❌ error — description has nothing to do with the function name
@Test("user can log in")
func fetchData() {}

// ✅ — punctuation and camelCase boundaries normalize away
@Test("A re-applied transaction can be rolled back again")
func aReappliedTransactionCanBeRolledBackAgain() async throws {}

// ❌ error — description unrelated to the type name
@Suite("completely unrelated description")
struct TransactionManagerTests {}

// ✅ — description contains the suite base name
@Suite("TransactionManager: rollback and commit behavior")
struct TransactionManagerTests {}
```

Not flagged: bare attributes (`@Test`), trait-only attributes (`@Test(.serialized)`), interpolated descriptions, and descriptions or names that normalize to an empty string (e.g. fully non-ASCII text). No Fix-It is provided — renaming requires human judgement.

**Configuration**

```yaml
rules:
  test-description-matches-name:
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
| `name_pattern` | `String` | regex | Declaration name must match this regular expression (searched anywhere in the name; anchor with `^`/`$` for prefix/suffix matching) |

`names` and `name_pattern` are alternatives for the same "name" filter: if both are given,
matching either one is sufficient (OR), and the result is then combined with `kinds` /
`modifiers` as usual (AND). An invalid `name_pattern` regex never matches — it fails safe
instead of suppressing violations it shouldn't.

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

# Suppress for any struct whose name ends with "Reducer" (e.g. HomeReducer)
  - kinds: [struct]
    name_pattern: "Reducer$"
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
      error_depth: 3
    include:
      - "Sources/**"
    exclude:
      - "**/*Generated.swift"
  single-large-type-per-file:
    args:
      warning_lines: 50
      error_lines: 50
```

## Requirements

- Swift 6.2+
- macOS 15+

## License

MIT
