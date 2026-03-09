# Dart Sentinel — VS Code Extension

Visual companion for the Dart Sentinel static analysis tool. Reads the cached analysis report and:

1. **Shows issues in the Problems tab** — errors, warnings, and info appear as native VS Code diagnostics on the correct file and line
2. **Dashboard webview** — a SonarQube-style visual overview with health score, severity breakdown, issues-by-rule table, and top offender files
3. **Status bar** — live error/warning count, click to open dashboard
4. **Auto-reload** — watches `.dart_sentinel/report.json` and refreshes diagnostics when the report is updated

## How It Works

```
┌─────────────────┐     ┌──────────────────────┐     ┌────────────────────┐
│  dart_sentinel   │     │  .dart_sentinel/      │     │  VS Code Extension │
│  CLI tool        │ ──▶ │  report.json (cache)  │ ──▶ │  Problems + Panel  │
│  (dart run ...)  │     │                      │     │                    │
└─────────────────┘     └──────────────────────┘     └────────────────────┘
```

## Setup

### 1. Run analysis (generates the report cache)

From your Dart/Flutter project:

```bash
# If dart_sentinel is a dev dependency:
dart run dart_sentinel

# Or from the dart_sentinel source:
dart run bin/analyze.dart -p /path/to/your/project
```

This creates `.dart_sentinel/report.json` in the project root.

### 2. Install the extension

```bash
cd vscode_extension
npm install
npm run compile
```

Then in VS Code: **Extensions → ... → Install from VSIX** or press F5 to launch an Extension Development Host.

### 3. Use it

- **Ctrl+Shift+P → "Dart Sentinel: Run Analysis"** — runs the CLI and reloads diagnostics
- **Ctrl+Shift+P → "Dart Sentinel: Open Dashboard"** — opens the visual dashboard
- **Ctrl+Shift+P → "Dart Sentinel: Clear Diagnostics"** — clears all issues from the Problems tab
- Issues appear automatically when `.dart_sentinel/report.json` is created or updated

## Configuration

In VS Code settings (`settings.json`):

```json
{
  "dartSentinel.autoAnalyze": true,
  "dartSentinel.reportPath": ".dart_sentinel/report.json",
  "dartSentinel.analyzeOnSave": false,
  "dartSentinel.category": "all"
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `autoAnalyze` | `true` | Auto-load diagnostics when report.json changes |
| `reportPath` | `.dart_sentinel/report.json` | Path to report file (relative to workspace) |
| `analyzeOnSave` | `false` | Re-run analysis on Dart file save |
| `category` | `all` | Default rule category: `all`, `arch`, `dead`, `metrics`, `lint` |

## For Any Repository

Add `.dart_sentinel/` to your project's `.gitignore` — the report is local cache, not committed:

```gitignore
.dart_sentinel/
```

Add `dart_sentinel` as a dev dependency in any repo:

```yaml
dev_dependencies:
  dart_sentinel:
    git:
      url: https://github.com/LuanCesarDC/dart-sentinel.git
```

Then create an `analyzer.yaml` in the project root to customize rules, thresholds, and exclusions per-repo. See `example/analyzer.yaml` for the full template.
