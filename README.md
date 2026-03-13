# Dart Sentinel

Static analysis, metrics, and architecture enforcement tool for Dart/Flutter projects.

## Installation

Add to your project's `pubspec.yaml`:

```yaml
dev_dependencies:
  dart_sentinel:
    git:
      url: https://github.com/LuanCesarDC/dart-sentinel
```

Or via local path (for development):

```yaml
dev_dependencies:
  dart_sentinel:
    path: ../dart_sentinel
```

Then:

```bash
dart pub get
```

## Usage

```bash
# Run all rules
dart run dart_sentinel

# Architecture rules only
dart run dart_sentinel -o arch

# Dead code only
dart run dart_sentinel -o dead

# Metrics only
dart run dart_sentinel -o metrics

# Lint rules only
dart run dart_sentinel -o lint

# JSON output (for CI)
dart run dart_sentinel -f json

# Markdown output (for PR comments)
dart run dart_sentinel -f markdown

# Specify project path
dart run dart_sentinel -p /path/to/project
```

## Configuration

Create an `analyzer.yaml` file at the root of your project:

```yaml
# Files to exclude (globs)
exclude:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "**/*.gr.dart"

# Entrypoints (auto-detected if not specified)
entrypoints:
  - lib/main.dart
  - lib/main_partner_mobile.dart

# Extra directories to scan
extra_scan_dirs:
  - integration_test
  - bin

# Severity per rule
rules:
  dead-files: warning
  banned-imports: error
  banned-symbols: warning
  complexity: warning
  dispose-check: warning
  empty-catch: warning
  generic-naming: warning
  dead-todos: info
  verbose-logging: info

# Architecture rules
architecture:
  banned_imports:
    - paths: ["lib/features/**/viewmodel/**"]
      deny: ["package:cloud_firestore/**"]
      message: "ViewModels must not access Firestore directly -- use Services."

  banned_symbols:
    - paths: ["lib/apps/**", "lib/features/**"]
      deny: ["ElevatedButton", "TextButton", "OutlinedButton"]
      suggest: "AppButton"
      message: "Use AppButton from your design system instead of raw Flutter buttons."
    - paths: ["lib/apps/**", "lib/features/**"]
      deny: ["showDialog", "AlertDialog"]
      suggest: "AppDialog.show"
      message: "Use AppDialog.show from your design system."

  layers:
    ui:
      paths: ["lib/features/**", "lib/apps/**"]
      can_depend_on: ["service", "core", "domain"]
    service:
      paths: ["lib/services/**"]
      can_depend_on: ["repository", "core", "domain"]
    repository:
      paths: ["lib/repositories/**"]
      can_depend_on: ["data", "core", "domain"]

  feature_isolation:
    enabled: true
    paths: ["lib/features/*/"]
    allow_shared:
      - "lib/core/**"
      - "lib/domain/**"
      - "lib/services/**"

# Metrics thresholds
metrics:
  cyclomatic_complexity:
    warning: 10
    error: 20
  lines_per_file:
    warning: 300
    error: 600
  lines_per_method:
    warning: 50
    error: 100
  max_parameters:
    warning: 4
    error: 7
  max_nesting:
    warning: 4
    error: 6
  build_method_loc:
    warning: 30
    error: 60
  build_method_branches:
    warning: 3
    error: 6
```

## Rules

### Dead Code
| Rule | Description |
|------|-------------|
| `dead-files` | Detects files unreachable from any entrypoint |
| `dead-exports` | Detects exports that no file imports |

### Architecture
| Rule | Description |
|------|-------------|
| `banned-imports` | Prevents forbidden imports in specific paths |
| `banned-symbols` | Prevents usage of specific symbols/constructors (e.g. enforce Design System) |
| `layer-dependency` | Validates imports respect defined layer boundaries |
| `feature-isolation` | Prevents horizontal coupling between features |
| `import-cycles` | Detects cycles in the import graph |

### Metrics
| Rule | Description |
|------|-------------|
| `complexity` | LOC, cyclomatic complexity, parameters, nesting depth |
| `build-complexity` | LOC and branches in Widget `build()` methods |

### Lint
| Rule | Description |
|------|-------------|
| `dispose-check` | Verifies resources are disposed correctly |
| `async-safety` | Detects `setState`/`context` usage after `await` without `mounted` check |

### AI Slop Detection (`-o slop`)
| Rule | Description |
|------|-------------|
| `empty-catch` | Detects swallowed exceptions: empty catch blocks and catch-and-print-only |
| `dead-todos` | Flags TODO/FIXME/HACK comments without actionable context |
| `generic-naming` | Catches variables/functions with low semantic specificity (`data`, `result`, `handleData`) |
| `redundant-comments` | Detects comments that restate what the code already says |
| `verbose-logging` | Flags excessive consecutive log/print statements |
| `single-method-class` | Suggests plain functions for classes with a single public method |
| `passthrough-function` | Detects functions that only delegate to another with the same arguments |

## CI Integration

### GitHub Actions

```yaml
- name: Run Dart Sentinel
  run: dart run dart_sentinel -f json > lint_report.json

- name: Check for errors
  run: dart run dart_sentinel  # exit code 1 if there are errors
```

### Pre-commit hook

Add to `.githooks/pre-commit`:

```bash
#!/bin/sh
dart run dart_sentinel -o arch
```

## MCP Server (AI Agent Integration)

Dart Sentinel exposes an MCP (Model Context Protocol) server so AI coding assistants like GitHub Copilot, Cursor, and Claude Code can query your architecture rules in real time.

### Setup

**1. Add dart_sentinel as a dev dependency** (if not already):

```yaml
dev_dependencies:
  dart_sentinel:
    git:
      url: https://github.com/LuanCesarDC/dart-sentinel
```

**2. Create `.vscode/mcp.json`** in your project root:

```json
{
  "servers": {
    "dart-sentinel": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "dart_sentinel:mcp_server"]
    }
  }
}
```

That's it. The AI agent will automatically discover the server and use it.

### Available Tools

| Tool | Description |
|------|-------------|
| `analyze` | Run full analysis or filter by category (`arch`, `dead`, `metrics`, `lint`) |
| `analyze_file` | Analyze a single file |
| `check_import` | Check if a specific import is allowed by your architecture rules |
| `get_architecture` | Get the full architecture definition (layers, banned imports) |

### Available Resources

| Resource | Description |
|----------|-------------|
| `sentinel://config` | Current `analyzer.yaml` configuration |
| `sentinel://report` | Latest analysis report (JSON) |
| `sentinel://architecture` | Architecture definition summary |

### How it works

When an AI agent generates code in your project, it can:

1. Call `check_import` before adding an import to verify it doesn't violate architecture rules
2. Call `analyze_file` after generating a file to check for violations
3. Read `sentinel://architecture` to understand your layer boundaries before writing code
4. Call `analyze` to run a full project scan

### CLI

You can also start the MCP server manually:

```bash
dart run dart_sentinel --mcp
# or
dart run dart_sentinel:mcp_server
```

## Programmatic Usage

```dart
import 'package:dart_sentinel/dart_sentinel.dart';

void main() async {
  final context = await ProjectContext.build('/path/to/project');

  final rules = [
    DeadFilesRule(),
    BannedImportsRule(),
    ComplexityRule(),
  ];

  final runner = RuleRunner(rules: rules, config: context.config);
  final issues = runner.runAll(context);

  print(ConsoleOutput.format(issues));
}
```

## Package Structure

```
dart_sentinel/
  bin/
    analyze.dart              # CLI entry point
  lib/
    dart_sentinel.dart        # Package exports
    src/
      config/
        analyzer_config.dart  # YAML configuration
      core/
        issue.dart            # Issue model + Severity
        project_context.dart  # Shared context (graph, AST cache)
        rule.dart             # Base class for rules
        runner.dart           # Rule runner
      rules/
        async_safety_rule.dart
        banned_imports_rule.dart
        build_complexity_rule.dart
        complexity_rule.dart
        dead_exports_rule.dart
        dead_files_rule.dart
        dispose_check_rule.dart
        feature_isolation_rule.dart
        import_cycle_rule.dart
        layer_dependency_rule.dart
      output/
        output.dart           # Console, JSON, Markdown formatters
      utils/
        glob_matcher.dart     # Glob pattern matching
        graph_utils.dart      # Graph algorithms (DFS, Tarjan)
  example/
    analyzer.yaml             # Example configuration
```
