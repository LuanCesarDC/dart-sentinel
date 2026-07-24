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
