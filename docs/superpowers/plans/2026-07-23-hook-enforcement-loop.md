# Hook Enforcement Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Dart Sentinel enforce architecture/quality rules automatically inside Claude Code sessions via hooks, instead of depending on the model choosing to call MCP tools — and surface a visible "violations caught this session" summary as proof of value.

**Architecture:** Two new Claude Code hook subcommands wired into the existing `dart_sentinel` CLI dispatcher (`bin/dart_sentinel.dart`): `hook-edit` (PostToolUse — fast, per-file feedback, reuses the exact logic already proven in the `analyze_file` MCP tool) and `hook-stop` (Stop — full-project scan + the existing `Ratchet` baseline mechanism). A third subcommand, `setup-hooks`, writes/merges the hook configuration into `.claude/settings.json` so installation is one command. All three reuse the existing rule engine (`ProjectContext`, `RuleRunner`, `Ratchet`) — no new analysis logic is introduced.

**Tech Stack:** Pure Dart (SDK ^3.9.0), `package:args`, `package:path`, `package:test`, existing `dart_sentinel` rule engine.

## Global Constraints

- Rules must be independent — don't import other rule files. (from `CLAUDE.md`)
- Output formatters must not depend on rule implementations. (from `CLAUDE.md`)
- Utils must be pure algorithms — no I/O or internal dependencies. (from `CLAUDE.md`)
- Rules must not use `dart:io` — use `ProjectContext` for file data. (from `CLAUDE.md`)
- `bin/` is wiring, outside the layered architecture — the layer-dependency rule does not restrict what `bin/*.dart` files import, but `bin/` is still scanned for metrics/complexity (`extra_scan_dirs` in `analyzer.yaml`), so keep these files under the LOC/complexity thresholds like any other scanned file. (from `analyzer.yaml`)
- Every new/modified file must pass `dart run dart_sentinel` (self-analysis) with zero new errors before a task is considered done — this project enforces itself. (from `docs/superpowers/specs/2026-07-23-hook-enforcement-loop-design.md`)
- Baseline (`.dart_sentinel/baseline.json`) must only be updated on explicit user action (`--save-baseline`), never automatically inside a hook. (from spec)
- The Stop hook must never cause an infinite loop: if the incoming hook payload has `stop_hook_active: true`, it must allow (exit 0) immediately. (from spec, Stop hook edge case)
- Hooks must fail open: if Sentinel itself errors (parse failure, missing project, etc.), the hook must exit 0 rather than block the user's workflow. (from spec, edge cases)

---

## File Structure

| File | Responsibility |
|---|---|
| `bin/rule_registry.dart` (new) | Single source of truth for "all Sentinel rules" — extracted from `bin/analyze.dart` so `hook-edit`/`hook-stop`/`analyze` don't each hand-maintain their own copy of the 35-rule list. Lives in `bin/` (wiring), not `lib/src/core/`, because `core` is only allowed to depend on `utils` per `analyzer.yaml`'s layer config, and this list depends on every rule. |
| `bin/analyze.dart` (modify) | Replace its inline rule list with a call to `rule_registry.dart`. |
| `bin/hook_edit.dart` (new) | PostToolUse hook entry point. Reads the Claude Code hook JSON payload from stdin, analyzes the touched file (same logic as the existing `analyze_file` MCP tool: full analysis, filtered to one file), blocks (`exit(2)`, message on stderr) only on `error`-severity issues. |
| `bin/hook_stop.dart` (new) | Stop hook entry point. Full-project scan, compares against `.dart_sentinel/baseline.json` via the existing `Ratchet` class, blocks on regressions, prints an improvement summary otherwise. Guards against `stop_hook_active` re-entry. |
| `bin/setup_hooks.dart` (new) | `dart_sentinel setup-hooks` subcommand. Writes/merges the two hook entries into `.claude/settings.json`, idempotently. Refuses (with a warning) if `analyzer.yaml` is missing. |
| `bin/dart_sentinel.dart` (modify) | Dispatcher — add routing for `hook-edit`, `hook-stop`, `setup-hooks`. |
| `test/rule_registry_test.dart` (new) | Verifies the extracted registry still contains every rule name referenced by `RuleRunner`'s category map. |
| `test/hook_edit_test.dart` (new) | Process-level tests for the PostToolUse hook (clean file, blocking violation, non-Dart file). |
| `test/hook_stop_test.dart` (new) | Process-level tests for the Stop hook (no baseline yet, pass, regression, `stop_hook_active` guard). |
| `test/setup_hooks_test.dart` (new) | Tests for `.claude/settings.json` generation, merge, idempotency, and the missing-`analyzer.yaml` guard. |
| `README.md` (modify) | New "Claude Code Hooks" section documenting `setup-hooks` and what the loop does. |
| `CHANGELOG.md` (modify) | New entry for this feature. |

---

### Task 1: Extract shared rule registry

**Files:**
- Create: `bin/rule_registry.dart`
- Modify: `bin/analyze.dart:186-220` (the `_runRuleAnalysis` function and its inline rule list)
- Test: `test/rule_registry_test.dart`

**Interfaces:**
- Produces: `List<AnalyzerRule> allSentinelRules()` in `bin/rule_registry.dart` — the canonical list of every rule, in the same order `bin/analyze.dart` used before this change. Later tasks (`hook_edit.dart`, `hook_stop.dart`) import this via `import 'rule_registry.dart';` (relative, since both live in `bin/`).

- [ ] **Step 1: Write the failing test**

Create `test/rule_registry_test.dart`:

```dart
import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../bin/rule_registry.dart';

void main() {
  test('allSentinelRules has no duplicate rule names and covers key rules', () {
    final rules = allSentinelRules();
    final names = rules.map((r) => r.name).toList();

    expect(names.toSet().length, names.length, reason: 'no duplicate rule names');
    expect(names, contains('dead-files'));
    expect(names, contains('layer-dependency'));
    expect(names, contains('dispose-check'));
    expect(names, contains('complexity'));
    expect(names, contains('flutter-anti-patterns'));
    expect(rules.length, 35);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/rule_registry_test.dart`
Expected: FAIL — `Error: Not found: 'rule_registry.dart'` (or "package:dart_sentinel/..." import error), because `bin/rule_registry.dart` doesn't exist yet.

- [ ] **Step 3: Create `bin/rule_registry.dart`**

```dart
// Canonical list of every Sentinel rule. Extracted from bin/analyze.dart so
// hook-edit, hook-stop, and the analyze CLI don't each hand-maintain a copy.
import 'package:dart_sentinel/dart_sentinel.dart';

List<AnalyzerRule> allSentinelRules() => [
  DeadFilesRule(),
  DeadExportsRule(),
  BannedImportsRule(),
  BannedSymbolsRule(),
  LayerDependencyRule(),
  FeatureIsolationRule(),
  ImportCycleRule(),
  ComplexityRule(),
  BuildComplexityRule(),
  DisposeCheckRule(),
  AsyncSafetyRule(),
  EmptyCatchRule(),
  DeadTodosRule(),
  GenericNamingRule(),
  RedundantCommentsRule(),
  VerboseLoggingRule(),
  SingleMethodClassRule(),
  PassthroughFunctionRule(),
  LazyNullCheckRule(),
  ModelMissingMethodsRule(),
  UnusedCodeRule(),
  UntestedFilesRule(),
  TestCoverageRule(),
  TestQualityRule(),
  ClassMetricsRule(),
  PubspecRule(),
  AvoidGlobalStateRule(),
  NoMagicNumberRule(),
  NoEqualThenElseRule(),
  AvoidCommentedOutCodeRule(),
  NoEqualArgumentsRule(),
  AvoidSelfCompareRule(),
  AvoidReturningWidgetsRule(),
  FlutterAntiPatternsRule(),
  MisusedDependenciesRule(),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/rule_registry_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: Replace the inline list in `bin/analyze.dart`**

In `bin/analyze.dart`, find:

```dart
List<Issue> _runRuleAnalysis(ProjectContext context, String category) {
  final allRules = <AnalyzerRule>[
    DeadFilesRule(),
    DeadExportsRule(),
    // ... (33 more entries)
    MisusedDependenciesRule(),
  ];
  final runner = RuleRunner(rules: allRules, config: context.config);
  if (category == 'all') return runner.runAll(context);
  return runner.runCategory(context, category);
}
```

Replace with:

```dart
List<Issue> _runRuleAnalysis(ProjectContext context, String category) {
  final runner = RuleRunner(rules: allSentinelRules(), config: context.config);
  if (category == 'all') return runner.runAll(context);
  return runner.runCategory(context, category);
}
```

Add the import at the top of `bin/analyze.dart`:

```dart
import 'rule_registry.dart';
```

- [ ] **Step 6: Verify `analyze.dart` still runs end-to-end**

Run: `dart run bin/dart_sentinel.dart -o all --no-report`
Expected: Same shape of output as before this change (same total issue count on this repo) — confirms the extraction didn't drop or duplicate any rule.

- [ ] **Step 7: Self-check with Sentinel**

Run: `dart run bin/dart_sentinel.dart --no-report`
Expected: No new errors introduced by `bin/rule_registry.dart` or the `bin/analyze.dart` edit (both files are small and under all thresholds).

- [ ] **Step 8: Commit**

```bash
git add bin/rule_registry.dart bin/analyze.dart test/rule_registry_test.dart
git commit -m "refactor: extract shared rule registry from analyze.dart"
```

---

### Task 2: `hook-edit` — PostToolUse hook

**Files:**
- Create: `bin/hook_edit.dart`
- Modify: `bin/dart_sentinel.dart`
- Test: `test/hook_edit_test.dart`

**Interfaces:**
- Consumes: `allSentinelRules()` from Task 1 (`bin/rule_registry.dart`); `ProjectContext.build(String projectRoot)`, `RuleRunner(rules:, config:).runAll(ProjectContext)`, `Issue.severity`, `Severity.error`, `Issue.toString()` from `package:dart_sentinel/dart_sentinel.dart`.
- Produces: `Future<void> main(List<String> args)` in `bin/hook_edit.dart`, invoked by the dispatcher as `dart_sentinel hook-edit`. Exit code contract: `0` = allow, `2` = block (violations written to stderr).

- [ ] **Step 1: Write the failing test**

Create `test/hook_edit_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('hook_edit_test_');
    File(p.join(fixtureDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_app
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    Directory(p.join(fixtureDir.path, 'lib')).createSync();
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runHookEdit(String filePath) => _runDartSentinel(
    entrypoint: entrypoint,
    workingDirectory: repoRoot,
    args: ['hook-edit'],
    stdinPayload: {
      'tool_name': 'Edit',
      'tool_input': {'file_path': filePath},
      'cwd': fixtureDir.path,
    },
  );

  test('allows a clean file (exit 0, no stderr)', () async {
    final target = p.join(fixtureDir.path, 'lib', 'clean.dart');
    File(target).writeAsStringSync('int add(int a, int b) => a + b;\n');

    final result = await runHookEdit(target);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });

  test('blocks a file with an error-severity violation', () async {
    final target = p.join(fixtureDir.path, 'lib', 'huge.dart');
    // 610 lines trips complexity's file-LOC error threshold (>= 600).
    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(target).writeAsStringSync(lines.join('\n'));

    final result = await runHookEdit(target);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('complexity'));
  });

  test('allows non-Dart files without analyzing', () async {
    final target = p.join(fixtureDir.path, 'README.md');
    File(target).writeAsStringSync('# fixture');

    final result = await runHookEdit(target);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });
}

Future<ProcessResult> _runDartSentinel({
  required String entrypoint,
  required String workingDirectory,
  required List<String> args,
  required Map<String, dynamic> stdinPayload,
}) async {
  final process = await Process.start('dart', [
    'run',
    entrypoint,
    ...args,
  ], workingDirectory: workingDirectory);

  process.stdin.write(jsonEncode(stdinPayload));
  await process.stdin.close();

  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(
    process.pid,
    exitCode,
    await stdoutFuture,
    await stderrFuture,
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/hook_edit_test.dart`
Expected: FAIL on all three tests — `dart run bin/dart_sentinel.dart hook-edit` exits with a Dart "Unhandled exception" or falls through to the default `analyze` path (since `hook-edit` isn't routed yet), producing a non-matching exit code.

- [ ] **Step 3: Create `bin/hook_edit.dart`**

```dart
// Claude Code PostToolUse hook. Runs after every Edit/Write, analyzes the
// touched file the same way the `analyze_file` MCP tool does (full analysis,
// filtered to one file), and blocks only on error-severity violations so
// Claude treats them like compile errors.
import 'dart:convert';
import 'dart:io';

import 'package:dart_sentinel/dart_sentinel.dart';

import 'rule_registry.dart';

Future<void> main(List<String> args) async {
  final raw = await stdin.transform(utf8.decoder).join();
  final payload = _parsePayload(raw);
  if (payload == null) return; // malformed input — fail open

  final filePath = payload.filePath;
  if (filePath == null || !filePath.endsWith('.dart')) return;

  final projectRoot = payload.cwd ?? Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync()) return;

  List<Issue> fileIssues;
  try {
    final context = await ProjectContext.build(projectRoot);
    final relativePath = context.relativePath(filePath);
    final runner = RuleRunner(
      rules: allSentinelRules(),
      config: context.config,
    );
    fileIssues = runner
        .runAll(context)
        .where((issue) => issue.file == relativePath)
        .toList();
  } catch (_) {
    return; // fail open — never block the user on Sentinel's own errors
  }

  final blocking = fileIssues
      .where((issue) => issue.severity == Severity.error)
      .toList();
  if (blocking.isEmpty) return;

  stderr.writeln('Dart Sentinel found blocking violations in $filePath:');
  for (final issue in blocking) {
    stderr.writeln('  $issue');
  }
  exit(2);
}

class _HookPayload {
  final String? filePath;
  final String? cwd;
  _HookPayload({this.filePath, this.cwd});
}

_HookPayload? _parsePayload(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final toolInput = json['tool_input'] as Map<String, dynamic>?;
    return _HookPayload(
      filePath: toolInput?['file_path'] as String?,
      cwd: json['cwd'] as String?,
    );
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Wire the dispatcher**

In `bin/dart_sentinel.dart`, update the header comment and add routing:

```dart
// Main entry point — delegates to analyze.dart, mcp_server.dart, or subcommands.
//
// `dart_sentinel`                          → CLI analysis
// `dart_sentinel --mcp`                    → MCP server over stdio
// `dart_sentinel generate-ai-config`       → Generate AI integration files
// `dart_sentinel hook-edit`                → Claude Code PostToolUse hook
import 'analyze.dart' as analyze;
import 'generate_ai_config.dart' as gen_ai;
import 'hook_edit.dart' as hook_edit;
import 'mcp_server.dart' as mcp;

Future<void> main(List<String> args) async {
  if (args.contains('--mcp')) {
    mcp.main();
  } else if (args.isNotEmpty && args.first == 'generate-ai-config') {
    await gen_ai.main(args.sublist(1));
  } else if (args.isNotEmpty && args.first == 'hook-edit') {
    await hook_edit.main(args.sublist(1));
  } else {
    await analyze.main(args);
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/hook_edit_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Self-check with Sentinel**

Run: `dart run bin/dart_sentinel.dart --no-report`
Expected: No new errors from `bin/hook_edit.dart` or the `bin/dart_sentinel.dart` edit.

- [ ] **Step 7: Commit**

```bash
git add bin/hook_edit.dart bin/dart_sentinel.dart test/hook_edit_test.dart
git commit -m "feat: add hook-edit PostToolUse hook for Claude Code"
```

---

### Task 3: `hook-stop` — Stop hook with ratchet summary

**Files:**
- Create: `bin/hook_stop.dart`
- Modify: `bin/dart_sentinel.dart`
- Test: `test/hook_stop_test.dart`

**Interfaces:**
- Consumes: `allSentinelRules()` (Task 1); `ProjectContext.build`, `RuleRunner`, `Ratchet.saveBaseline`, `Ratchet.check`, `RatchetResult` from `package:dart_sentinel/dart_sentinel.dart`.
- Produces: `Future<void> main(List<String> args)` in `bin/hook_stop.dart`, routed as `dart_sentinel hook-stop`. Exit code contract: `0` = allow (baseline created, or ratchet passed, or `stop_hook_active` guard triggered), `2` = block (regression found, message on stderr).

- [ ] **Step 1: Write the failing test**

Create `test/hook_stop_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('hook_stop_test_');
    File(p.join(fixtureDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_app
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    Directory(p.join(fixtureDir.path, 'lib')).createSync();
    File(p.join(fixtureDir.path, 'lib', 'clean.dart'))
        .writeAsStringSync('int add(int a, int b) => a + b;\n');
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runHookStop({bool stopHookActive = false}) => _run(
    entrypoint: entrypoint,
    workingDirectory: repoRoot,
    args: ['hook-stop'],
    stdinPayload: {'cwd': fixtureDir.path, 'stop_hook_active': stopHookActive},
  );

  test('creates a baseline and allows on first run', () async {
    final result = await runHookStop();

    expect(result.exitCode, 0);
    expect(
      File(p.join(fixtureDir.path, '.dart_sentinel', 'baseline.json'))
          .existsSync(),
      isTrue,
    );
  });

  test('allows when nothing regressed since the baseline', () async {
    await runHookStop(); // creates baseline

    final result = await runHookStop();

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Ratchet passed'));
  });

  test('blocks when a new error-severity issue regresses the baseline', () async {
    await runHookStop(); // creates baseline with just clean.dart

    // Introduce a file-LOC error-severity violation.
    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(p.join(fixtureDir.path, 'lib', 'huge.dart'))
        .writeAsStringSync(lines.join('\n'));

    final result = await runHookStop();

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Ratchet failed'));
  });

  test('allows immediately when stop_hook_active is true, even with a regression', () async {
    await runHookStop(); // creates baseline

    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(p.join(fixtureDir.path, 'lib', 'huge.dart'))
        .writeAsStringSync(lines.join('\n'));

    final result = await runHookStop(stopHookActive: true);

    expect(result.exitCode, 0);
  });
}

Future<ProcessResult> _run({
  required String entrypoint,
  required String workingDirectory,
  required List<String> args,
  required Map<String, dynamic> stdinPayload,
}) async {
  final process = await Process.start('dart', [
    'run',
    entrypoint,
    ...args,
  ], workingDirectory: workingDirectory);

  process.stdin.write(jsonEncode(stdinPayload));
  await process.stdin.close();

  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(
    process.pid,
    exitCode,
    await stdoutFuture,
    await stderrFuture,
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/hook_stop_test.dart`
Expected: FAIL on all four tests — `hook-stop` isn't routed yet, so the dispatcher falls through to `analyze.main(['hook-stop'])`, which errors on the unknown `--only` value.

- [ ] **Step 3: Create `bin/hook_stop.dart`**

```dart
// Claude Code Stop hook. Runs a full-project scan when Claude finishes
// responding, compares it against the saved ratchet baseline, and blocks
// only if something regressed. Never updates the baseline itself — that
// only happens via `dart_sentinel --save-baseline`, run explicitly by the
// user, so a hook can never "launder" a regression by just stopping.
import 'dart:convert';
import 'dart:io';

import 'package:dart_sentinel/dart_sentinel.dart';

import 'rule_registry.dart';

Future<void> main(List<String> args) async {
  final raw = await stdin.transform(utf8.decoder).join();
  final payload = _parsePayload(raw);
  if (payload == null) return; // malformed input — fail open

  if (payload.stopHookActive) return; // avoid re-entrant Stop loop

  final projectRoot = payload.cwd ?? Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync()) return;

  List<Issue> issues;
  try {
    final context = await ProjectContext.build(projectRoot);
    final runner = RuleRunner(
      rules: allSentinelRules(),
      config: context.config,
    );
    issues = runner.runAll(context);
  } catch (_) {
    return; // fail open
  }

  final baselinePath = '$projectRoot/.dart_sentinel/baseline.json';
  if (!File(baselinePath).existsSync()) {
    Ratchet.saveBaseline(issues, path: baselinePath);
    print('Dart Sentinel: baseline created at $baselinePath');
    return;
  }

  final result = Ratchet.check(issues, path: baselinePath);
  if (!result.passed) {
    stderr.writeln(result.message);
    exit(2);
  }
  print(result.message);
}

class _HookPayload {
  final String? cwd;
  final bool stopHookActive;
  _HookPayload({this.cwd, required this.stopHookActive});
}

_HookPayload? _parsePayload(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _HookPayload(
      cwd: json['cwd'] as String?,
      stopHookActive: json['stop_hook_active'] as bool? ?? false,
    );
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Wire the dispatcher**

In `bin/dart_sentinel.dart`, add the `hook-stop` route (and the header comment line) alongside `hook-edit` from Task 2:

```dart
// `dart_sentinel hook-stop`                → Claude Code Stop hook
import 'hook_stop.dart' as hook_stop;
```

```dart
  } else if (args.isNotEmpty && args.first == 'hook-stop') {
    await hook_stop.main(args.sublist(1));
```

Place this as another `else if` branch alongside the `hook-edit` branch, before the final `else`.

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/hook_stop_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Self-check with Sentinel**

Run: `dart run bin/dart_sentinel.dart --no-report`
Expected: No new errors from `bin/hook_stop.dart` or the dispatcher edit.

- [ ] **Step 7: Commit**

```bash
git add bin/hook_stop.dart bin/dart_sentinel.dart test/hook_stop_test.dart
git commit -m "feat: add hook-stop Stop hook with ratchet summary"
```

---

### Task 4: `setup-hooks` — one-command installer

**Files:**
- Create: `bin/setup_hooks.dart`
- Modify: `bin/dart_sentinel.dart`
- Test: `test/setup_hooks_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks besides the `hook-edit`/`hook-stop` command names it writes into the generated config (`dart_sentinel hook-edit`, `dart_sentinel hook-stop`).
- Produces: `Future<void> main(List<String> args)` in `bin/setup_hooks.dart`, routed as `dart_sentinel setup-hooks`. Writes/merges `<project>/.claude/settings.json`.

- [ ] **Step 1: Write the failing test**

Create `test/setup_hooks_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('setup_hooks_test_');
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runSetupHooks() => Process.run('dart', [
    'run',
    entrypoint,
    'setup-hooks',
    '--project',
    fixtureDir.path,
  ], workingDirectory: repoRoot);

  File settingsFile() =>
      File(p.join(fixtureDir.path, '.claude', 'settings.json'));

  test('warns and writes nothing when analyzer.yaml is missing', () async {
    final result = await runSetupHooks();

    expect(result.exitCode, 0);
    expect(result.stdout, contains('analyzer.yaml'));
    expect(settingsFile().existsSync(), isFalse);
  });

  test('writes PostToolUse and Stop hooks when analyzer.yaml exists', () async {
    File(p.join(fixtureDir.path, 'analyzer.yaml')).writeAsStringSync('rules: {}\n');

    final result = await runSetupHooks();
    expect(result.exitCode, 0);

    final settings =
        jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
    final hooks = settings['hooks'] as Map<String, dynamic>;
    final postToolUse = hooks['PostToolUse'] as List;
    final stop = hooks['Stop'] as List;

    expect(
      jsonEncode(postToolUse),
      contains('dart_sentinel hook-edit'),
    );
    expect(jsonEncode(stop), contains('dart_sentinel hook-stop'));
  });

  test('merges into an existing settings.json without dropping other keys', () async {
    File(p.join(fixtureDir.path, 'analyzer.yaml')).writeAsStringSync('rules: {}\n');
    Directory(p.join(fixtureDir.path, '.claude')).createSync();
    settingsFile().writeAsStringSync(
      jsonEncode({
        'permissions': {'allow': []},
      }),
    );

    await runSetupHooks();

    final settings =
        jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
    expect(settings['permissions'], isNotNull);
    expect(settings['hooks'], isNotNull);
  });

  test('running twice does not duplicate hook entries', () async {
    File(p.join(fixtureDir.path, 'analyzer.yaml')).writeAsStringSync('rules: {}\n');

    await runSetupHooks();
    await runSetupHooks();

    final settings =
        jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
    final postToolUse = (settings['hooks'] as Map)['PostToolUse'] as List;

    expect(postToolUse.length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/setup_hooks_test.dart`
Expected: FAIL on all four tests — `setup-hooks` isn't routed yet.

- [ ] **Step 3: Create `bin/setup_hooks.dart`**

```dart
// `dart_sentinel setup-hooks` — writes/merges the PostToolUse and Stop hook
// entries into .claude/settings.json so hook-edit/hook-stop run automatically
// in Claude Code, without the user hand-editing JSON.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.');
  final results = parser.parse(args);
  final projectRoot = results['project'] as String? ?? Directory.current.path;

  final analyzerYaml = File(p.join(projectRoot, 'analyzer.yaml'));
  if (!analyzerYaml.existsSync()) {
    print(
      'No analyzer.yaml found at $projectRoot — set up your architecture '
      'config first, then run `dart_sentinel setup-hooks` again.',
    );
    return;
  }

  final settingsFile = File(p.join(projectRoot, '.claude', 'settings.json'));
  final settings = _readSettings(settingsFile);

  final hooks = (settings['hooks'] as Map<String, dynamic>?) ?? {};
  hooks['PostToolUse'] = _mergeHookEntry(
    hooks['PostToolUse'] as List?,
    command: 'dart_sentinel hook-edit',
    matcher: 'Edit|Write',
  );
  hooks['Stop'] = _mergeHookEntry(
    hooks['Stop'] as List?,
    command: 'dart_sentinel hook-stop',
    matcher: null,
  );
  settings['hooks'] = hooks;

  settingsFile.parent.createSync(recursive: true);
  settingsFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(settings),
  );
  print('Dart Sentinel hooks written to ${settingsFile.path}');
}

Map<String, dynamic> _readSettings(File file) {
  if (!file.existsSync()) return {};
  final content = file.readAsStringSync();
  if (content.trim().isEmpty) return {};
  return jsonDecode(content) as Map<String, dynamic>;
}

List<dynamic> _mergeHookEntry(
  List<dynamic>? existing, {
  required String command,
  required String? matcher,
}) {
  final entries = existing ?? [];
  final alreadyPresent = entries.any(
    (entry) => jsonEncode(entry).contains(command),
  );
  if (alreadyPresent) return entries;

  final newEntry = <String, dynamic>{
    if (matcher != null) 'matcher': matcher,
    'hooks': [
      {'type': 'command', 'command': command},
    ],
  };
  return [...entries, newEntry];
}
```

- [ ] **Step 4: Wire the dispatcher**

In `bin/dart_sentinel.dart`, add the `setup-hooks` route (and header comment) alongside the routes from Tasks 2 and 3:

```dart
// `dart_sentinel setup-hooks`              → write Claude Code hook config
import 'setup_hooks.dart' as setup_hooks;
```

```dart
  } else if (args.isNotEmpty && args.first == 'setup-hooks') {
    await setup_hooks.main(args.sublist(1));
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/setup_hooks_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Self-check with Sentinel**

Run: `dart run bin/dart_sentinel.dart --no-report`
Expected: No new errors from `bin/setup_hooks.dart` or the dispatcher edit.

- [ ] **Step 7: Commit**

```bash
git add bin/setup_hooks.dart bin/dart_sentinel.dart test/setup_hooks_test.dart
git commit -m "feat: add setup-hooks installer for Claude Code hooks"
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing (docs only).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add a "Claude Code Hooks" section to `README.md`**

Insert this new section right after the existing "## IDE Plugin (Analysis Server)" section (before "## Installation"):

```markdown
## Claude Code Hooks

For projects using Claude Code, Dart Sentinel can enforce your architecture
automatically — no MCP tool calls to remember, no manual CLI runs.

```bash
dart_sentinel setup-hooks
```

This writes two hooks into `.claude/settings.json`:

- **PostToolUse** (`hook-edit`) — after every `Edit`/`Write` on a `.dart`
  file, Sentinel analyzes just that file. If it introduces an error-severity
  violation, Claude sees it immediately and has to fix it before continuing —
  the same way a compile error would stop it.
- **Stop** (`hook-stop`) — when Claude finishes responding, Sentinel runs a
  full project scan and compares it against `.dart_sentinel/baseline.json`
  (Ratchet Mode). If anything regressed, Claude is told exactly what and has
  to keep working. If nothing regressed, you get a one-line summary of what
  was caught and fixed during the session.

Requires `analyzer.yaml` to already exist (`setup-hooks` will tell you if it
doesn't). Accept a new baseline explicitly once you're happy with the current
state:

```bash
dart_sentinel --save-baseline
```
```

- [ ] **Step 2: Add a `CHANGELOG.md` entry**

Read the top of `CHANGELOG.md` first to match its existing heading format, then add a new unreleased entry above the latest version heading:

```markdown
## Unreleased

- Add `dart_sentinel setup-hooks` to wire Claude Code PostToolUse/Stop hooks
  automatically, closing the enforcement loop without relying on MCP tool
  calls.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: document Claude Code hooks setup"
```

---

### Task 6: Dogfood on this repository

**Files:**
- Modify: `.claude/settings.json` (generated, not hand-written)
- Create: `.dart_sentinel/baseline.json` (generated)

**Interfaces:**
- Consumes: `setup-hooks`, `hook-edit`, `hook-stop` from Tasks 2–4, run against this repository itself.
- Produces: a live, working hook setup in this repo — the validation the design spec asked for ("ativar os hooks neste próprio repositório").

- [ ] **Step 1: Run the installer on this repo**

Run: `dart run bin/dart_sentinel.dart setup-hooks --project .`
Expected: `.claude/settings.json` created (or merged) with `hook-edit`/`hook-stop` entries.

- [ ] **Step 2: Create the initial baseline**

Run: `dart run bin/dart_sentinel.dart --save-baseline`
Expected: `.dart_sentinel/baseline.json` created, printed path confirmed.

- [ ] **Step 3: Manually verify the PostToolUse hook blocks a real violation**

```bash
cat <<'JSON' | dart run bin/dart_sentinel.dart hook-edit; echo "exit: $?"
{"tool_name":"Edit","tool_input":{"file_path":"$(pwd)/lib/src/core/issue.dart"},"cwd":"$(pwd)"}
JSON
```

Expected: `exit: 0` (this file is currently clean). Repeat by temporarily appending ~600 throwaway lines to a scratch `.dart` file under `lib/` and re-running to confirm `exit: 2` with a `complexity` message on stderr, then delete the scratch file.

- [ ] **Step 4: Manually verify the Stop hook**

```bash
echo '{"cwd":"'"$(pwd)"'","stop_hook_active":false}' | dart run bin/dart_sentinel.dart hook-stop; echo "exit: $?"
```

Expected: `exit: 0`, stdout contains `Ratchet passed`.

- [ ] **Step 5: Commit the generated hook config and baseline**

```bash
git add .claude/settings.json .dart_sentinel/baseline.json
git commit -m "chore: enable Claude Code hooks on this repo (dogfood)"
```
