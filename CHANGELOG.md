# Changelog

## 0.4.0

### Breaking behavior changes

- Metric limits are now exclusive: a value **equal** to the limit passes and
  only values **above** it are reported, matching the `(limit: N)` in the
  message (`complexity`, `class-metrics`, `build-complexity`, and the
  analyzer plugin).
- `rules: <name>: off` now really disables the rule. Previously `off` was
  silently parsed as `warning`. An invalid severity is a fatal config error
  (exit code 2) instead of silently becoming `warning`.

### New

- `dart_sentinel init` — detects the `lib/` structure, recommends a template,
  writes `analyzer.yaml` and runs `setup-hooks` (`--template`, `--force`,
  `--no-hooks`). Templates ship inside the package.
- `dart_sentinel doctor` — checks Dart version, PATH, `analyzer.yaml`, Claude
  Code hooks and the `pubspec.yaml` conflict below.
- `dart_sentinel rules` — lists every rule, its category and whether the
  project turns it off or changes its severity.
- `flutter_official` template (`ui/`, `data/`, `domain/`, `routing/`).
- `analyzer.yaml` validation: unknown top-level keys and unknown rule names
  warn with a "did you mean" suggestion; layers that match no file and `lib/`
  folders outside every layer warn too.
- `setup-hooks` and `doctor` flag `dart_sentinel` listed in `dependencies` /
  `dev_dependencies` — it is a global tool.
- `ai_slop.no_equal_arguments.ignore` extends the built-in list of symmetric
  constructors.

### Fixes

- `-f json` prints only JSON on stdout; banner and progress go to stderr.
- `unused-code` ignores `main()` and `@pragma('vm:entry-point')`, and counts an
  extension as used when any of its members is called.
- `dispose-check` recognizes Riverpod `ref.onDispose(...)` (tear-off or closure).
- `generic-naming` skips constants, fields, named parameters, constructor
  parameters and `@override` parameters.
- `no-equal-arguments` skips `EdgeInsets.fromLTRB`, `Offset`, `Size` and other
  symmetric constructors.
- `untested-files` accepts tests outside the mirrored path (widget, golden)
  and under `integration_test/`.
- `misused-dependencies` exempts annotation runtimes (`json_annotation`,
  `freezed_annotation`, ...) when `build_runner` is present.
- `--help`, `generate-ai-config` output and the AI templates tell agents to
  install with `dart pub global activate dart_sentinel`, run `dart_sentinel`,
  and never add it to `pubspec.yaml`.
- Tests for these rules with good/bad fixtures (`test/rules/`, `test/helpers/`).

## 0.3.0

- Add Claude Code hook integration — enforcement now runs automatically
  inside a session instead of depending on the model calling MCP tools:
  - `dart_sentinel hook-edit` — PostToolUse hook, blocks on error-severity
    violations in the file just edited
  - `dart_sentinel hook-stop` — Stop hook, full-project scan + Ratchet
    baseline check, with a pass/fail summary
  - `dart_sentinel setup-hooks` — writes/merges both hooks into
    `.claude/settings.json` in one command
- Fix `complexity` (file-LOC check) never firing: it counted lines via the
  AST unparser (`toSource()`), which collapses all formatting — now counts
  real source lines via `ProjectContext.fileContents`.
- Fix 5 `curly_braces_in_flow_control_structures` lint issues and 4
  formatting/unused-import issues flagged by `dart pub` scoring.
- Loosen the `analyzer` dependency's upper bound so `dart pub get` resolves
  to a newer compatible release by default (analyzer 14.x introduces a
  breaking AST API change unrelated to this release — not adopted yet).

## 0.2.1

- Fix dangling library doc comment in bin/dart_sentinel.dart
- Fix unbraced if statement in redundant_comments_rule.dart
- Reduce package size (exclude tool/analyzer_plugin from publication)

## 0.2.0

- 35 rules across 8 categories (arch, dead, metrics, lint, slop, models, testing, pub)
- New rules: unused-code, class-metrics (NOM/WMC/LOC), avoid-global-state, no-magic-number, no-equal-then-else, avoid-commented-out-code, no-equal-arguments, avoid-self-compare, avoid-returning-widgets, flutter-anti-patterns, lazy-null-check, untested-files, test-coverage, test-quality, pubspec, misused-dependencies, model-missing-methods
- Model code generation (generate_model_scaffold, generate_model_update MCP tools)
- Test scaffold generation (generate_test_scaffold MCP tool)
- `--changed-only` flag for CI (filters to git-changed files)
- `--no-cache` flag
- File hash cache for incremental analysis
- `generate-ai-config` command (generates .vscode/mcp.json, copilot-instructions, cursorrules, CLAUDE.md)
- L10n scanner: find hardcoded strings and check ARB translation coverage
- Architecture self-validation (dogfooding fixes)

## 0.1.0

- Initial release
- 18 lint/architecture rules (dead-files, dead-exports, banned-imports, layer-dependency, feature-isolation, import-cycles, complexity, build-complexity, dispose-check, async-safety, empty-catch, dead-todos, generic-naming, redundant-comments, verbose-logging, single-method-class, passthrough-function, banned-symbols)
- IDE plugin with real-time diagnostics and quick fixes
- MCP server for AI agent integration
- CLI with JSON, Markdown, and console output
- Change impact analysis and dependency map
- Ratchet mode for CI baseline enforcement
- Architecture templates for 12 popular Flutter patterns
