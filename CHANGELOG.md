# Changelog

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
