# my-swift-linter Rule Catalog

All rules default to `error` severity unless noted otherwise. Rules with a `severity` argument accept `error` or `warning`.

Rule descriptions are embedded in the executable. Agents and tools can discover the registered
rules without reading the source by running `my-swift-linter rules` (JSON by default), or use
`my-swift-linter rules --format text` for a human-readable report. The JSON report also includes
default/effective arguments, enabled state, and path filters.

| Rule ID | Default | Fix | Configuration | Detects |
| --- | --- | --- | --- | --- |
| `deep-nesting` | error at depth >= 3 | No | `warning_depth`, `error_depth` | Control-flow nesting in `if`, `guard`, `for`, `while`, `switch`, and `do` blocks beyond configured thresholds. |
| `single-large-type-per-file` | error at lines >= 50 | No | `warning_lines`, `error_lines` | Multiple large `public` or `package` types in one file. |
| `property-declaration-ordering` | error | Yes | `severity` | Type properties not grouped as stored properties, `body`, then other computed properties, with wrapper and access ordering for stored properties. |
| `function-access-modifier-grouping` | error | Yes | `severity` | Functions in a type or extension not grouped by access level: `open`, `public`, `package`, `internal`, `fileprivate`, `private`. |
| `swiftui-view-property` | error | Yes | `severity` | `return` in `some View` properties/functions, or missing `@ViewBuilder` when top-level `let`/`var`/`if`/`switch` appears. |
| `branch-assignment-to-tuple` | error | No | `severity` | Uninitialized `let` declarations immediately assigned in every branch of a following `if`/`switch`. |
| `no-top-level-function` | error | No | `severity` | File-scope `func` declarations. |
| `return-if-expression` | error | Yes | `severity` | Complete `if`/`else if`/`else` chains where every branch only returns one expression. |
| `return-switch-expression` | error | Yes | `severity` | `switch` statements where every case only returns one expression. |
| `use-url-file-path` | error | Yes | `severity` | Deprecated `URL(fileURLWithPath:)` and `URL(fileURLWithPath:isDirectory:)` initializers. |
| `meaningful-suite-description` | error | No | `severity` | `@Suite` descriptions that duplicate the type name or a trivial type-name prefix. |
| `test-function-naming` | error | No | `severity`, `check_spaces`, `check_underscores`, `check_test_prefix` | Swift Testing `@Test` functions with backtick phrase names, underscores, or redundant `test` prefixes. |
| `test-description-duplicates-name` | error | No | `severity` | `@Test` or `@Suite` descriptions that merely restate the function or type name and add no information. |
| `missing-docs` | error | No | `min_access_level`, `severity`, `ignore_patterns` | Explicit declarations at or above the configured access level that lack doc comments. |
| `collapsible-if` | error | No | `severity` | An `if`/`guard` whose body contains only a single else-less nested `if`. |
| `hoist-repeated-instance` | error | No | `severity`, `minimum_occurrences`, `types`, `flag_unconfigured` | A configurable Foundation type constructed and configured identically as a local variable in two or more instance members of the same type. |

## Rule Details

### `deep-nesting`

Counts nested control-flow constructs and reports once nesting reaches `warning_depth` or `error_depth`. Depth resets at functions, initializers, accessors, and closures.

Fix by extracting nested work into helpers, returning early, or flattening conditions.

```yaml
rules:
  deep-nesting:
    args:
      warning_depth: 3
      error_depth: 3
```

### `single-large-type-per-file`

Reports when two or more `public` or `package` `enum`, `struct`, `class`, or `actor` declarations exceed the configured line thresholds in the same file.

Fix by splitting large public/package types into separate files.

```yaml
rules:
  single-large-type-per-file:
    args:
      warning_lines: 50
      error_lines: 50
```

### `property-declaration-ordering`

Requires properties inside types to be grouped predictably. Stored properties are ordered by property wrapper, then by access modifier; `body` is kept before other computed properties.

Fix support: `--fix` can reorder properties automatically.

```yaml
rules:
  property-declaration-ordering:
    args:
      severity: error
```

### `function-access-modifier-grouping`

Requires regular functions within a type or extension to be grouped in descending access order. `init`, `deinit`, and `subscript` are excluded.

Fix support: `--fix` can reorder functions automatically while preserving relative order inside each access group.

```yaml
rules:
  function-access-modifier-grouping:
    args:
      severity: error
```

### `swiftui-view-property`

Checks `some View` computed properties and functions. It flags explicit `return` and requires `@ViewBuilder` when top-level declarations or branch expressions need result-builder composition. `var body: some View` and `func body(content:) -> some View` are exempt because protocol requirements already provide an implicit builder.

Fix support: `--fix` can remove `return` or insert `@ViewBuilder`.

```yaml
rules:
  swiftui-view-property:
    args:
      severity: error
```

### `branch-assignment-to-tuple`

Finds consecutive uninitialized `let` declarations with explicit types followed immediately by an `if`/`else` or `switch` whose branches only assign all declared names.

Fix by rewriting to `let value = if ...` or `let (a, b) = switch ...`. No automatic fix is provided because branch side effects require judgement.

```yaml
rules:
  branch-assignment-to-tuple:
    args:
      severity: error
```

### `no-top-level-function`

Flags file-scope functions, including `private` helpers. Functions inside a type, extension, protocol, or another function are allowed.

Fix by moving helpers onto an existing type, into an extension, or into a namespace enum.

```yaml
rules:
  no-top-level-function:
    args:
      severity: error
```

### `return-if-expression`

Finds `if` chains that terminate with `else` and where every branch contains exactly one non-bare `return <expr>`.

Fix support: `--fix` can collapse the chain into `return if ... { ... } else { ... }`.

```yaml
rules:
  return-if-expression:
    args:
      severity: error
```

### `return-switch-expression`

Finds `switch` statements where every case contains exactly one `return <expr>`.

Fix support: `--fix` can collapse the statement into `return switch ...`.

```yaml
rules:
  return-switch-expression:
    args:
      severity: error
```

### `use-url-file-path`

Flags deprecated file URL initializers. `URL(fileURLWithPath:)` is rewritten to `URL(filePath:)`; `URL(fileURLWithPath:isDirectory:)` is rewritten to `URL(filePath:directoryHint:)`.

Fix support: `--fix` can update supported call forms, including implicit `.init(fileURLWithPath:)`.

```yaml
rules:
  use-url-file-path:
    args:
      severity: error
```

### `meaningful-suite-description`

Flags Swift Testing `@Suite` descriptions that are only the type name, the type name after stripping `Tests`, `Test`, or `Spec`, or the same trivial prefix followed by a dash or colon.

Fix by writing a description that explains what behavior the suite covers, or omit the description when traits are enough.

```yaml
rules:
  meaningful-suite-description:
    args:
      severity: error
```

### `test-function-naming`

Flags `@Test` functions whose names are backtick-quoted phrases with spaces, contain underscores, or start with `test`. Backtick-escaped Swift keywords without spaces are allowed.

Fix by using lowerCamelCase function names and placing human-readable prose in `@Test("...")`.

```yaml
rules:
  test-function-naming:
    args:
      severity: error
      check_spaces: true
      check_underscores: true
      check_test_prefix: true
```

### `test-description-duplicates-name`

Flags Swift Testing descriptions that merely restate the declaration name. Both sides are normalized by keeping Unicode letters/digits (only spaces and punctuation are stripped) and lowercasing, so a description containing non-ASCII letters can never equal an ASCII name and is always treated as meaningful. `@Test` fires when the normalized description equals the function name. `@Suite` fires when it equals the type name with or without a test suffix; a description that names the type and adds detail is allowed.

Fix by removing the redundant description or rewriting it to explain what the declaration verifies.

```yaml
rules:
  test-description-duplicates-name:
    args:
      severity: error
```

### `missing-docs`

Flags explicit declarations at or above `min_access_level` when they lack a `///` or `/** */` doc comment. Supported declarations include types, protocols, typealiases, functions, initializers, subscripts, and `var`/`let`.

`min_access_level` defaults to `package`. If an invalid value is configured, the implementation falls back to `public`.

```yaml
rules:
  missing-docs:
    args:
      min_access_level: package
      severity: error
      ignore_patterns:
        - kinds: [var, let]
          modifiers: [static]
          names: [liveValue, previewValue, testValue]
        - kinds: [struct]
          name_pattern: "Reducer$"
```

Each `ignore_patterns` entry matches all specified fields. Omitted fields are wildcards. `kinds` and `names` are OR lists. `modifiers` is an AND list. `name_pattern` is a regular expression searched in the declaration name; invalid regexes never match.

### `collapsible-if`

Flags an `if` (or `guard`) whose body contains nothing but a single, else-less nested `if` — a nesting level that adds no branching and can be merged into the outer condition list with `,`. Covers plain conditions and `if let`/optional-binding chains, and also `guard ... else { }` immediately followed by a single else-less `if` as the rest of the block.

Not flagged when: either `if` has an `else` clause, the outer body has statements besides the nested `if`, the outer `if` is labeled, or the nested `if` sits inside another construct (e.g. `for`) rather than directly in the body.

Shadowed optional bindings (`if let x = a { if let x = x.child { ... } }`) are still flagged since the nesting is redundant, but the message notes a mechanical merge would redeclare the name — the fix must be done by hand.

No automatic fix (merging condition lists can require manual rewrites when bindings shadow).

```yaml
rules:
  collapsible-if:
    args:
      severity: error
```

### `hoist-repeated-instance`

Flags a local `let`/`var` constructed with a zero-argument initializer (`T()`, `T.init()`, `let x: T = .init()`) of an allowlisted, configurable Foundation type, optionally followed by a run of plain `x.<path> = <rhs>` property assignments (the "configuration prefix"), when the exact same construction and configuration is repeated in two or more **instance** members (`func`, `init`, computed property, `subscript`) of the same `struct`/`class`/`actor` (or a same-file `extension` of it).

Two occurrences are "the same" when the type matches and the configuration prefix has the same set of `(property path, RHS token text)` pairs — order-independent, since assigning to different properties is commutative. A property assigned twice within one prefix, or a config statement guarded by a conditional, disqualifies that occurrence (the prefix stops at the first non-matching statement).

**Default type allowlist:** `JSONDecoder`, `JSONEncoder`, `PropertyListDecoder`, `PropertyListEncoder`, `DateFormatter`, `NumberFormatter`, `DateComponentsFormatter`, `DateIntervalFormatter`, `PersonNameComponentsFormatter`. This list is deliberately closed and was verified empirically against Swift 6 strict concurrency (`swiftc -strict-concurrency=complete`): hoisting a value of one of these types to an instance stored property compiles cleanly. Five related Foundation types are intentionally **excluded** from the default because they are not `Sendable` and hoisting them to a stored property can silently remove the enclosing type's implicit `Sendable` conformance — a behavior change this rule must not recommend: `ISO8601DateFormatter`, `RelativeDateTimeFormatter`, `ByteCountFormatter`, `MeasurementFormatter`, `ListFormatter`. Add any of these back (or any other type) via the `types` YAML key at your own risk.

**Hoistability check.** A configuration's RHS is only treated as a match — and an occurrence is only recorded at all — when the RHS does not reference `self`, a function/closure parameter, a local variable (anywhere in the enclosing member, not just the current block), or another instance property/method declared in the same file. None of those are visible from a stored-property initializer, so a construction that depends on them cannot actually be hoisted; flagging it would recommend code that doesn't compile. A bare identifier that cannot be resolved this way (e.g. a global constant, or an instance member declared in a different file) is still flagged, since the rule has no type-checker — treat this class of diagnostic as a prompt to double-check by hand, not a certainty.

**Escape analysis.** After the configuration prefix, the local variable may only be used as the base of a member-access/subscript chain (a read or a method call). It must not be returned, passed as a bare argument, assigned to another binding, reassigned, or captured by a nested closure or nested function — any of those makes an occurrence unsafe to hoist and disqualifies it.

Not flagged when:
- the two occurrences configure the type differently, or only partially overlap in which properties they set
- the local variable is inside a `static func`/`static var` or a `class func` (static members and `enum` containers/namespaces are out of scope for this version — a `static let` hoist target with a different group key and a `Sendable` caveat is a possible future addition)
- the construction is the pattern this rule itself recommends: a stored `private let x: T = { ...; return x }()`, `lazy var`, or `private let x = T()` — stored-property initializers are never scanned as occurrence sites
- the type isn't in the allowlist, the initializer takes arguments, or the declaration binds more than one name (`let a = T(), b = U()`)
- the container is an `extension` of a type with no primary `struct`/`class`/`actor` declaration in the same file (including a `protocol` extension, since a protocol can never hold a stored property)

**Known overlap:** a `let` inside a `some View` computed property without `@ViewBuilder` can also trip `swiftui-view-property`; both point the same direction (get the `let` out of the property body), so the double report is expected, not a bug.

No automatic fix (synthesizing the stored property, removing N local declarations, and rewriting N call sites is not a single-node mechanical edit).

```yaml
rules:
  hoist-repeated-instance:
    args:
      severity: error
      minimum_occurrences: 2
      flag_unconfigured: true
      types:                 # REPLACES the default list, does not extend it
        - JSONDecoder
        - JSONEncoder
```
