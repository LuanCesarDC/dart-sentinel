# Example Project — Dart Sentinel

This example project demonstrates all violations that Dart Sentinel can detect.

## How to run

```bash
cd example
dart pub get
dart run dart_sentinel
```

## Files

### Slop / Lint rules (IDE plugin + CLI)

| File | Rule | Description |
|------|------|-------------|
| `lib/src/empty_catch.dart` | `empty_catch` | Swallowed exceptions |
| `lib/src/dead_todo.dart` | `dead_todo` | TODOs without context |
| `lib/src/generic_naming.dart` | `generic_naming` | Low-specificity names |
| `lib/src/redundant_comment.dart` | `redundant_comment` | Comments that restate code |
| `lib/src/verbose_logging.dart` | `verbose_logging` | Too many consecutive prints |
| `lib/src/single_method_class.dart` | `single_method_class` | Classes that should be functions |
| `lib/src/passthrough_function.dart` | `passthrough_function` | Functions that only delegate |
| `lib/src/lazy_null_check.dart` | `lazy_null_check` | Lazy `x ?? ""` null coalescing |
| `lib/src/complexity.dart` | `complexity` | High complexity, nesting, params |

### Architecture rules (CLI only)

| File | Rule | Description |
|------|------|-------------|
| `lib/src/layer_dependency.dart` | `layer_dependency` + `banned_imports` | Import violations between layers |
| `lib/src/feature_isolation.dart` | `feature_isolation` | Cross-feature imports |
| `lib/src/banned_symbols.dart` | `banned_symbols` | Design system enforcement |
| `lib/src/dead_code.dart` | `dead_files` + `dead_exports` | Unreachable code |
| `lib/src/import_cycle.dart` | `import_cycle` | Circular dependencies |
