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

| Rule ID | Severity | Description |
|---------|----------|-------------|
| `deep-nesting` | warning / error | Flags control flow nesting — warning at depth ≥ `warning` (default: 3), error at depth ≥ `error` (default: 5) |
| `single-large-type-per-file` | warning / error | Flags files with two or more large public/package types — warning at ≥ `warning` lines (default: 50), error at ≥ `error` lines (default: 100) |
| `property-declaration-ordering` | warning | Properties must be grouped by property wrapper, then by access modifier |
| `function-access-modifier-grouping` | warning | Functions must be grouped by access modifier (open → public → … → private) |
| `swiftui-view-property` | error | `return` is forbidden in `some View` properties; `@ViewBuilder` is required when the body contains top-level `let`/`var`/`if`/`switch` |

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
      warning: 3   # default
      error: 5     # default
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
      warning: 50    # default
      error: 100     # default
```

### property-declaration-ordering

Properties within a type must be sorted first by property wrapper (alphabetically, unwrapped properties last), then by access modifier within each wrapper group.

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
      max_depth: 4
    include:
      - "Sources/**"
    exclude:
      - "**/*Generated.swift"
  single-large-type-per-file:
    args:
      min_lines: 100
```

## Requirements

- Swift 6.2+
- macOS 15+

## License

MIT
