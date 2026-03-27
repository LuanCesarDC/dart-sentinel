# Project Instructions — Dart Sentinel

## Architecture Enforcement

This project's architecture is enforced deterministically by **Dart Sentinel**.
All rules are defined in `analyzer.yaml` at the project root — that is the single source of truth.

Before writing or modifying Dart code:

1. **Read the architecture**: Call `get_architecture` from the dart-sentinel MCP server to understand layers, banned imports, and feature isolation rules.
2. **Check imports**: Before adding any cross-layer import, call `check_import` to verify it's allowed.
3. **After code generation**: Call `analyze_file` on every new or modified file. Fix ALL reported violations before considering the task complete.

## Key Rules

- **Layer boundaries** are enforced — UI cannot import Data, Services cannot import UI, etc.
- **Feature isolation** is enforced — features cannot import from other features. Use shared/core layers.
- **Banned symbols** are enforced — use design system components (e.g. `AppButton` instead of `ElevatedButton`).
- **Model classes** in model paths must have `toMap`, `fromMap`, `copyWith`, `==`, `hashCode`, and `toString`.
- **Dispose** all StreamSubscriptions, TextEditingControllers, AnimationControllers.
- **No empty catch blocks** — always handle, rethrow, or document why it's safe to ignore.
- **No setState/context usage after await** without a `mounted` check.

## Treat Violations as Errors

Dart Sentinel violations are **blocking** — equivalent to compile errors.
Do not return code that has Sentinel violations. Always fix them first.

## Available MCP Tools

| Tool | When to use |
|------|-------------|
| `get_architecture` | Before any architectural decision |
| `check_import` | Before adding any import |
| `analyze_file` | After creating or modifying any file |
| `analyze` | For full project scan |
| `impact_analysis` | Before refactoring to understand blast radius |
| `dependency_map` | To visualize module structure |
| `generate_test_scaffold` | When creating service/repository classes |
