# Project Instructions

Architecture is enforced by **Dart Sentinel** (`analyzer.yaml`). The AI agent has access to Sentinel via MCP.

## Architecture

- **utils**: `lib/src/utils/**` → (no deps)
- **core**: `lib/src/core/**, lib/src/config/**` → utils
- **analysis**: `lib/src/analysis/**` → core, utils
- **rules**: `lib/src/rules/**` → core, utils
- **output**: `lib/src/output/**` → core
- **mcp**: `lib/src/mcp/**` → core, rules, analysis, utils

## Import Restrictions
- Rules must be independent — don't import other rule files.
- Output formatters must not depend on rule implementations.
- Utils must be pure algorithms — no I/O or internal dependencies.
- Rules must not use dart:io — use ProjectContext for file data.

## Thresholds
- Cyclomatic complexity: warning 10, error 20
- Lines per file: warning 300, error 600
- Lines per method: warning 50, error 100
- Max parameters: warning 5, error 7
- Max nesting: warning 4, error 6
- Build method LOC: warning 30, error 60
- Build method branches: warning 3, error 6
- Methods per class: warning 15, error 30
- Weighted methods per class: warning 30, error 80
- Lines per class: warning 300, error 600

## Workflow — MANDATORY for every task

1. **Before writing code**: call `get_architecture` to read layer boundaries.
2. **Before adding an import**: call `check_import` to verify it's allowed.
3. **After creating/modifying a file**: call `analyze_file` to check for violations.
4. Fix ALL issues before moving on — treat violations as compile errors.
5. **Before a big refactor**: call `impact_analysis` to understand blast radius.

## MCP Tools (dart-sentinel server)

| Tool | When to use |
|------|-------------|
| `get_architecture` | Before any architectural decision |
| `check_import` | Before adding any cross-layer import |
| `analyze_file` | After every file create/edit |
| `analyze` | Full project scan |
| `impact_analysis` | Before refactoring |
| `dependency_map` | Visualize module structure |
| `generate_model_scaffold` | Create model with copyWith, toMap, fromMap, ==, hashCode |
| `generate_model_update` | Add fields to existing model |
| `generate_test_scaffold` | Generate test stubs for a file |
| `scan_hardcoded_strings` | Find hardcoded UI strings |
| `l10n_status` | Check translation coverage |
| `generate_l10n` | Write ARB translation files |
| `migrations` | Track banned-symbol migration progress |

## Code Quality

- Dispose all resources (StreamSubscription, TextEditingController, AnimationController)
- No empty catch blocks — handle, rethrow, or document why
- No `setState`/`context` after `await` without `mounted` check
- No generic names (`data`, `result`, `value`, `temp`, `item`)
- No commented-out code blocks
- No magic numbers — extract to named constants
- No duplicate if/else branches

**Treat Sentinel violations as compile errors — never ignore them.**
