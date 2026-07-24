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
