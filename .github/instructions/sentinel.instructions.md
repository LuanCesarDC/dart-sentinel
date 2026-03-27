---
applyTo: "**/*.dart"
---

# Dart Sentinel — Checks for Dart files

## Active Rules
- **Errors** (block CI): `banned-imports`, `layer-dependency`
- **Warnings**: `import-cycles`, `feature-isolation`, `dead-files`, `dead-exports`, `unused-code`, `complexity`, `build-complexity`, `class-metrics`, `dispose-check`, `async-safety`, `empty-catch`, `generic-naming`, `lazy-null-check`, `no-equal-then-else`, `no-equal-arguments`, `avoid-self-compare`, `avoid-global-state`, `avoid-returning-widgets`, `flutter-anti-patterns`, `test-quality`, `pubspec`
- **Info**: `dead-todos`, `redundant-comments`, `verbose-logging`, `single-method-class`, `passthrough-function`, `avoid-commented-out-code`, `no-magic-number`, `untested-files`, `misused-dependencies`, `model-missing-methods`

## Before writing code
- Call `get_architecture` from dart-sentinel MCP to read layers and constraints.

## Before adding any import
- Call `check_import` with the source file path and the import URI.
- If it returns a violation, find an alternative.

## After creating or modifying any Dart file
- Call `analyze_file` with the file path.
- Fix ALL violations before considering the task done.

### How to fix common violations

| Violation | Fix |
|-----------|-----|
| `layer-dependency` | You imported from a forbidden layer. Move the import or restructure. |
| `banned-imports` | This import is explicitly forbidden. Read the message for the reason. |
| `complexity` | Method too complex. Extract helpers or simplify conditionals. |
| `empty-catch` | Add error handling: `rethrow`, log the error, or add a `// deliberate` comment. |
| `generic-naming` | Rename `data`/`result`/`item` to something domain-specific. |
| `dispose-check` | Add `subscription.cancel()` or `controller.dispose()` in `dispose()`. |
| `async-safety` | Add `if (!mounted) return;` after the `await`. |
| `unused-code` | Remove the unused declaration, or export it if it's public API. |
| `no-magic-number` | Extract `42` to `const _maxRetries = 42;`. |
| `no-equal-then-else` | The if and else branches are identical — remove the conditional. |
| `avoid-global-state` | Move top-level `var` into a class or make it `final`. |

## When creating a model class
- Call `generate_model_scaffold` with class name and fields to get `copyWith`, `toMap`, `fromMap`, `==`, `hashCode`, `toString`.

## When creating tests
- Call `generate_test_scaffold` with the source file path to get test stubs for all public methods.

## When refactoring
- Call `impact_analysis` with the file(s) you plan to change.
- Review the blast radius before making breaking changes.
