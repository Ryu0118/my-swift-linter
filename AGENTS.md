# Agent Instructions

## Project

my-swift-linter is a Swift package that builds the `my-swift-linter` executable. It wraps SwiftASTLint with a curated rule set from `Sources/Rules`.

## Commands

- Build: `swift build`
- Test: `swift test`
- Run locally: `swift run my-swift-linter <paths>`
- Apply fixes locally: `swift run my-swift-linter <paths> --fix`
- Check docs sync: `.nest/bin/docsync check --config docsync.yml`

## Rule Changes

When adding, removing, or changing a rule, update:

- `README.md`
- `skills/my-swift-linter-guide/references/rules.md`
- `docsync.yml` checksums

The docsync rules are expected to enforce these updates.

## Skill Distribution

`skills/` is the single source of truth for agent skills. Claude Code, Codex, APM, and `.agents` entries should reference it through symlinks. Do not edit generated or linked copies as if they were independent sources.
