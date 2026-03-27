# AI Integration Instructions — Dart Sentinel

This is a generic template for integrating Dart Sentinel with any AI coding assistant.
Copy the relevant sections to your AI tool's instruction file.

## Architecture Enforcement

This project uses **Dart Sentinel** for deterministic architecture enforcement.
All rules are defined in `analyzer.yaml` at the project root. That file is the **single source of truth**
for layer boundaries, banned imports, feature isolation, metrics thresholds, and model configuration.

## Workflow

1. **Before writing code**: Read the architecture definition from `analyzer.yaml` or call `get_architecture` via MCP.
2. **Before adding imports**: Verify the import is allowed by calling `check_import` via MCP.
3. **After writing code**: Run `analyze_file` on every new or modified file. Fix ALL reported violations.

## Rules Summary

### Architecture
- **Layer boundaries**: Layers are defined with allowed dependencies. Violating imports will be flagged.
- **Feature isolation**: Features cannot import from other features. Use shared/core layers for shared code.
- **Banned symbols**: Certain symbols (e.g., raw Flutter widgets) are banned in favor of design system components.
- **Import cycles**: Circular import dependencies are flagged.

### Code Quality
- **Complexity**: Cyclomatic complexity < 10 (warning), < 20 (error) per method.
- **File size**: < 300 lines (warning), < 600 lines (error).
- **Method size**: < 50 lines (warning), < 100 lines (error).
- **Parameters**: < 4 (warning), < 7 (error) per method.
- **Nesting**: < 4 levels (warning), < 6 levels (error).

### Safety
- Dispose all resources (StreamSubscription, TextEditingController, AnimationController).
- No `setState`/`context` usage after `await` without `mounted` check.

### AI Slop Detection
- No empty catch blocks — handle, rethrow, or document.
- No generic names (`data`, `result`, `value`, `temp`).
- No redundant comments that restate code.
- No single-method classes that should be functions.
- No passthrough functions.

### Models
- Classes in model paths must include: `toMap`, `fromMap`, `copyWith`, `==`, `hashCode`, `toString`.
- Method names are configurable (e.g., `toFirestore`, `toJson`).

## MCP Tools Reference

| Tool | Description |
|------|-------------|
| `get_architecture` | Returns full architecture definition (layers, banned imports, feature isolation) |
| `check_import` | Checks if a specific import is allowed from a specific file |
| `analyze_file` | Analyzes a single file for all violations |
| `analyze` | Runs full project analysis (optionally filtered by category) |
| `impact_analysis` | Computes blast radius of file changes |
| `dependency_map` | Generates dependency graph (text or Mermaid) |
| `migrations` | Tracks banned-symbol migration progress |
| `generate_test_scaffold` | Generates test skeleton for a given source file |

## Enforcement Policy

Treat Dart Sentinel violations as **blocking** — equivalent to compile errors.
Do not return code that has violations. Always fix them before completing a task.
