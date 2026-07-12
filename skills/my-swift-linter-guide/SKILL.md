---
name: my-swift-linter-guide
description: Use when installing, configuring, running, fixing, or explaining my-swift-linter, swift-ast-lint rules, .swift-ast-lint.yml, Swift lint diagnostics, or the my-swift-linter CLI.
---

# my-swift-linter Guide

my-swift-linter is a SwiftASTLint-based linter that packages opinionated Swift rules for source layout, SwiftUI view declarations, Swift Testing naming, documentation, and modern Swift expression style.

## Install

Install the released binary:

```sh
curl -fsSL https://raw.githubusercontent.com/Ryu0118/my-swift-linter/main/install.sh | bash
```

Install with Nest:

```sh
nest install Ryu0118/my-swift-linter
```

Install with mise:

```sh
mise use -g ubi:Ryu0118/my-swift-linter
```

Build from source:

```sh
git clone https://github.com/Ryu0118/my-swift-linter.git
cd my-swift-linter
swift build -c release
```

## Run

Run the installed binary:

```sh
my-swift-linter <paths> --config .swift-ast-lint.yml
```

`<paths>` defaults to `.`. The default config path is `.swift-ast-lint.yml`.

Apply available fixes:

```sh
my-swift-linter <paths> --fix
```

Disable cache or select a cache directory:

```sh
my-swift-linter <paths> --no-cache
my-swift-linter <paths> --cache-path .build/my-swift-linter-cache
```

Run from a source checkout:

```sh
swift run --package-path /path/to/my-swift-linter my-swift-linter /path/to/Sources
```

The command exits with code `2` when lint errors remain.

## Configure

Create `.swift-ast-lint.yml` at the target project root:

```yaml
disabled_rules:
  - missing-docs

rules:
  deep-nesting:
    args:
      warning_depth: 3
      error_depth: 3
    include:
      - "Sources/**"
    exclude:
      - "**/*Generated.swift"

  missing-docs:
    args:
      min_access_level: public
      severity: warning
      ignore_patterns:
        - kinds: [var, let]
          modifiers: [static]
          names: [liveValue, previewValue, testValue]
```

Rule configuration uses `rules.<rule-id>.args` for rule-specific arguments. `include` and `exclude` patterns scope a rule to matching paths. Use `disabled_rules` to turn off rules globally.

## Rules

See [references/rules.md](references/rules.md) for the full rule catalog, defaults, fix support, and configuration keys.
