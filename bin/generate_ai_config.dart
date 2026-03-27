import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'tool',
      abbr: 't',
      help: 'AI tool to generate config for.',
      allowed: ['copilot', 'cursor', 'claude', 'windsurf', 'all'],
      defaultsTo: 'all',
    )
    ..addOption('project', abbr: 'p', help: 'Path to the project root.')
    ..addFlag('dry-run', negatable: false, help: 'Preview without writing.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help.');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('Usage: dart_sentinel generate-ai-config [options]');
    print('');
    print('Generate AI integration files for your project.');
    print('');
    print(parser.usage);
    return;
  }

  final projectRoot = results['project'] as String? ?? Directory.current.path;
  final tool = results['tool'] as String;
  final dryRun = results['dry-run'] as bool;

  final config = _ProjectConfig.load(projectRoot);

  // Always generate MCP config for the relevant tools
  _generateMcpConfig(projectRoot, tool, dryRun);

  final generators = <String, void Function()>{
    'copilot': () => _generateCopilot(projectRoot, config, dryRun),
    'cursor': () => _generateCursor(projectRoot, config, dryRun),
    'claude': () => _generateClaude(projectRoot, config, dryRun),
    'windsurf': () => _generateWindsurf(projectRoot, config, dryRun),
  };

  if (tool == 'all') {
    for (final gen in generators.values) {
      gen();
    }
  } else {
    generators[tool]!();
  }
}

// ── Project config ──

class _ProjectConfig {
  final List<_Layer> layers;
  final bool hasFeatureIsolation;
  final List<String> sharedPaths;
  final List<_BannedImport> bannedImports;
  final List<_BannedSymbol> bannedSymbols;
  final Map<String, _MetricThreshold> metrics;
  final Map<String, String> rules;
  final String packageName;

  _ProjectConfig({
    required this.layers,
    required this.hasFeatureIsolation,
    required this.sharedPaths,
    required this.bannedImports,
    required this.bannedSymbols,
    required this.metrics,
    required this.rules,
    required this.packageName,
  });

  factory _ProjectConfig.load(String projectRoot) {
    final yaml = _loadYaml(projectRoot);
    final pubspec = _loadPubspec(projectRoot);
    if (yaml == null) {
      return _ProjectConfig(
        layers: [],
        hasFeatureIsolation: false,
        sharedPaths: [],
        bannedImports: [],
        bannedSymbols: [],
        metrics: {},
        rules: {},
        packageName: pubspec ?? 'my_app',
      );
    }

    return _ProjectConfig(
      layers: _parseLayers(yaml),
      hasFeatureIsolation: _parseFeatureIsolation(yaml),
      sharedPaths: _parseSharedPaths(yaml),
      bannedImports: _parseBannedImports(yaml),
      bannedSymbols: _parseBannedSymbols(yaml),
      metrics: _parseMetrics(yaml),
      rules: _parseRules(yaml),
      packageName: pubspec ?? 'my_app',
    );
  }

  bool get hasLayers => layers.isNotEmpty;
  bool get hasBannedSymbols => bannedSymbols.isNotEmpty;
  bool get hasBannedImports => bannedImports.isNotEmpty;
  bool get hasMetrics => metrics.isNotEmpty;
  bool get hasRules => rules.isNotEmpty;
}

class _Layer {
  final String name;
  final List<String> paths;
  final List<String> canDependOn;
  _Layer(this.name, this.paths, this.canDependOn);
}

class _BannedImport {
  final String message;
  _BannedImport(this.message);
}

class _BannedSymbol {
  final List<String> deny;
  final String suggest;
  final String message;
  _BannedSymbol(this.deny, this.suggest, this.message);
}

class _MetricThreshold {
  final int warning;
  final int error;
  _MetricThreshold(this.warning, this.error);
}

// ── YAML parsers ──

List<_Layer> _parseLayers(YamlMap yaml) {
  final arch = yaml['architecture'];
  if (arch is! YamlMap) return [];
  final layers = arch['layers'];
  if (layers is! YamlMap) return [];
  return [
    for (final entry in layers.entries)
      if (entry.value is YamlMap)
        _Layer(
          '${entry.key}',
          (entry.value['paths'] as YamlList?)?.map((e) => '$e').toList() ?? [],
          (entry.value['can_depend_on'] as YamlList?)
                  ?.map((e) => '$e')
                  .toList() ??
              [],
        ),
  ];
}

bool _parseFeatureIsolation(YamlMap yaml) {
  final arch = yaml['architecture'];
  if (arch is! YamlMap) return false;
  final fi = arch['feature_isolation'];
  if (fi is! YamlMap) return false;
  return fi['enabled'] == true;
}

List<String> _parseSharedPaths(YamlMap yaml) {
  final arch = yaml['architecture'];
  if (arch is! YamlMap) return [];
  final fi = arch['feature_isolation'];
  if (fi is! YamlMap) return [];
  final shared = fi['allow_shared'];
  if (shared is! YamlList) return [];
  return shared.map((e) => '$e').toList();
}

List<_BannedImport> _parseBannedImports(YamlMap yaml) {
  final arch = yaml['architecture'];
  if (arch is! YamlMap) return [];
  final banned = arch['banned_imports'];
  if (banned is! YamlList) return [];
  return [
    for (final item in banned)
      if (item is YamlMap && item['message'] != null)
        _BannedImport('${item['message']}'),
  ];
}

List<_BannedSymbol> _parseBannedSymbols(YamlMap yaml) {
  final arch = yaml['architecture'];
  if (arch is! YamlMap) return [];
  final symbols = arch['banned_symbols'];
  if (symbols is! YamlList) return [];
  return [
    for (final item in symbols)
      if (item is YamlMap)
        _BannedSymbol(
          (item['deny'] as YamlList?)?.map((e) => '$e').toList() ?? [],
          '${item['suggest'] ?? ''}',
          '${item['message'] ?? ''}',
        ),
  ];
}

Map<String, _MetricThreshold> _parseMetrics(YamlMap yaml) {
  final metrics = yaml['metrics'];
  if (metrics is! YamlMap) return {};
  final result = <String, _MetricThreshold>{};
  for (final entry in metrics.entries) {
    if (entry.value is YamlMap) {
      final w = entry.value['warning'];
      final e = entry.value['error'];
      if (w is int && e is int) {
        result['${entry.key}'] = _MetricThreshold(w, e);
      }
    }
  }
  return result;
}

Map<String, String> _parseRules(YamlMap yaml) {
  final rules = yaml['rules'];
  if (rules is! YamlMap) return {};
  return {for (final entry in rules.entries) '${entry.key}': '${entry.value}'};
}

YamlMap? _loadYaml(String projectRoot) {
  final file = File(p.join(projectRoot, 'analyzer.yaml'));
  if (!file.existsSync()) return null;
  final yaml = loadYaml(file.readAsStringSync());
  return yaml is YamlMap ? yaml : null;
}

String? _loadPubspec(String projectRoot) {
  final file = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return null;
  return '${yaml['name']}';
}

// ── File writer ──

void _writeFile(String filePath, String content, bool dryRun) {
  if (dryRun) {
    print('  [dry-run] Would write: $filePath');
    return;
  }
  final file = File(filePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  print('  \u2713 $filePath');
}

// ── MCP Config ──

void _generateMcpConfig(String root, String tool, bool dryRun) {
  print('MCP:');

  if (tool == 'all' || tool == 'copilot') {
    _writeFile(
      p.join(root, '.vscode', 'mcp.json'),
      '{\n'
      '  "servers": {\n'
      '    "dart-sentinel": {\n'
      '      "type": "stdio",\n'
      '      "command": "dart_sentinel",\n'
      '      "args": ["--mcp"]\n'
      '    }\n'
      '  }\n'
      '}\n',
      dryRun,
    );
  }

  if (tool == 'all' || tool == 'cursor') {
    _writeFile(
      p.join(root, '.cursor', 'mcp.json'),
      '{\n'
      '  "mcpServers": {\n'
      '    "dart-sentinel": {\n'
      '      "command": "dart_sentinel",\n'
      '      "args": ["--mcp"]\n'
      '    }\n'
      '  }\n'
      '}\n',
      dryRun,
    );
  }
}

// ── Content builders ──

String _buildProjectInstructions(_ProjectConfig config) {
  final buf = StringBuffer();
  buf.writeln('# Project Instructions');
  buf.writeln();
  buf.writeln(
    'Architecture is enforced by **Dart Sentinel** (`analyzer.yaml`). '
    'The AI agent has access to Sentinel via MCP.',
  );
  buf.writeln();

  // Architecture section
  if (config.hasLayers) {
    buf.writeln('## Architecture');
    buf.writeln();
    for (final layer in config.layers) {
      final deps = layer.canDependOn.isEmpty
          ? '(no deps)'
          : layer.canDependOn.join(', ');
      buf.writeln('- **${layer.name}**: `${layer.paths.join(', ')}` → $deps');
    }
    buf.writeln();
  }

  if (config.hasFeatureIsolation) {
    buf.writeln('Features are isolated — no cross-feature imports.');
    if (config.sharedPaths.isNotEmpty) {
      buf.writeln(
        'Shared code allowed from: ${config.sharedPaths.map((s) => '`$s`').join(', ')}',
      );
    }
    buf.writeln();
  }

  if (config.hasBannedImports) {
    buf.writeln('## Import Restrictions');
    for (final b in config.bannedImports) {
      buf.writeln('- ${b.message}');
    }
    buf.writeln();
  }

  if (config.hasBannedSymbols) {
    buf.writeln('## Design System');
    for (final s in config.bannedSymbols) {
      buf.writeln(
        '- **${s.deny.join(', ')}** → use `${s.suggest}` — ${s.message}',
      );
    }
    buf.writeln();
  }

  if (config.hasMetrics) {
    buf.writeln('## Thresholds');
    final labels = {
      'cyclomatic_complexity': 'Cyclomatic complexity',
      'lines_per_method': 'Lines per method',
      'lines_per_file': 'Lines per file',
      'max_parameters': 'Max parameters',
      'max_nesting': 'Max nesting',
      'build_method_loc': 'Build method LOC',
      'build_method_branches': 'Build method branches',
      'number_of_methods': 'Methods per class',
      'weighted_methods_per_class': 'Weighted methods per class',
      'lines_per_class': 'Lines per class',
    };
    for (final entry in config.metrics.entries) {
      final label = labels[entry.key] ?? entry.key;
      buf.writeln(
        '- $label: warning ${entry.value.warning}, error ${entry.value.error}',
      );
    }
    buf.writeln();
  }

  // Workflow — the most important part
  buf.write(_workflowSection);

  return buf.toString();
}

String get _workflowSection => '''## Workflow — MANDATORY for every task

1. **Before writing code**: call `get_architecture` to read layer boundaries.
2. **Before adding an import**: call `check_import` to verify it\'s allowed.
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
''';

String _buildSentinelInstructions(_ProjectConfig config) {
  final buf = StringBuffer();
  buf.writeln('---');
  buf.writeln('applyTo: "**/*.dart"');
  buf.writeln('---');
  buf.writeln();
  buf.writeln('# Dart Sentinel — Checks for Dart files');
  buf.writeln();

  // Active rules as a compact reference
  if (config.hasRules) {
    buf.writeln('## Active Rules');
    final errors = <String>[];
    final warnings = <String>[];
    final infos = <String>[];
    for (final entry in config.rules.entries) {
      switch (entry.value) {
        case 'error':
          errors.add(entry.key);
        case 'warning':
          warnings.add(entry.key);
        case 'info':
          infos.add(entry.key);
      }
    }
    if (errors.isNotEmpty) {
      buf.writeln(
        '- **Errors** (block CI): ${errors.map((r) => '`$r`').join(', ')}',
      );
    }
    if (warnings.isNotEmpty) {
      buf.writeln('- **Warnings**: ${warnings.map((r) => '`$r`').join(', ')}');
    }
    if (infos.isNotEmpty) {
      buf.writeln('- **Info**: ${infos.map((r) => '`$r`').join(', ')}');
    }
    buf.writeln();
  }

  buf.write(r'''## Before writing code
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
''');

  return buf.toString();
}

// ── Generators ──

void _generateCopilot(String root, _ProjectConfig config, bool dryRun) {
  print('Copilot:');
  _writeFile(
    p.join(root, '.github', 'copilot-instructions.md'),
    _buildProjectInstructions(config),
    dryRun,
  );
  _writeFile(
    p.join(root, '.github', 'instructions', 'sentinel.instructions.md'),
    _buildSentinelInstructions(config),
    dryRun,
  );
}

void _generateCursor(String root, _ProjectConfig config, bool dryRun) {
  print('Cursor:');
  _writeFile(
    p.join(root, '.cursor', 'rules', 'sentinel.mdc'),
    '---\n'
    'description: Dart Sentinel architecture enforcement\n'
    'globs: ["**/*.dart", "analyzer.yaml"]\n'
    'alwaysApply: true\n'
    '---\n\n'
    '${_buildProjectInstructions(config)}'
    '\n'
    '${_buildSentinelInstructions(config)}',
    dryRun,
  );
}

void _generateClaude(String root, _ProjectConfig config, bool dryRun) {
  print('Claude Code:');
  _writeFile(
    p.join(root, 'CLAUDE.md'),
    _buildProjectInstructions(config),
    dryRun,
  );
}

void _generateWindsurf(String root, _ProjectConfig config, bool dryRun) {
  print('Windsurf:');
  _writeFile(
    p.join(root, '.windsurfrules'),
    _buildProjectInstructions(config),
    dryRun,
  );
}
