import 'dart:convert';
import 'dart:io';

import '../core/issue.dart';

/// Ratchet Mode — baseline enforcement that only allows improvement.
///
/// Saves a snapshot of issue counts per rule and fails CI if any count
/// increases. Counts can only decrease (improve) over time.
class Ratchet {
  static const _defaultPath = '.dart_sentinel/baseline.json';

  /// Save a baseline from the current set of issues.
  static void saveBaseline(
    List<Issue> issues, {
    String? path,
  }) {
    final filePath = path ?? _defaultPath;
    final baseline = _buildBaseline(issues);

    final dir = File(filePath).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);

    File(filePath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(baseline),
    );
  }

  /// Compare current issues against a saved baseline.
  ///
  /// Returns a [RatchetResult] indicating pass/fail and any regressions.
  static RatchetResult check(
    List<Issue> issues, {
    String? path,
  }) {
    final filePath = path ?? _defaultPath;
    final file = File(filePath);

    if (!file.existsSync()) {
      return RatchetResult(
        passed: false,
        regressions: [],
        message: 'No baseline found at $filePath. '
            'Run with --save-baseline first.',
      );
    }

    final baselineJson =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final baselineCounts = (baselineJson['rules'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    final currentCounts = _countByRule(issues);
    final regressions = _findRegressions(currentCounts, baselineCounts);
    final improvements = _findImprovements(currentCounts, baselineCounts);

    return _buildResult(regressions, improvements);
  }

  static List<RatchetRegression> _findRegressions(
    Map<String, int> current,
    Map<String, int> baseline,
  ) {
    return [
      for (final entry in current.entries)
        if (entry.value > (baseline[entry.key] ?? 0))
          RatchetRegression(
            rule: entry.key,
            baseline: baseline[entry.key] ?? 0,
            current: entry.value,
          ),
    ];
  }

  static Map<String, int> _findImprovements(
    Map<String, int> current,
    Map<String, int> baseline,
  ) {
    return {
      for (final entry in baseline.entries)
        if ((current[entry.key] ?? 0) < entry.value)
          entry.key: entry.value - (current[entry.key] ?? 0),
    };
  }

  static RatchetResult _buildResult(
    List<RatchetRegression> regressions,
    Map<String, int> improvements,
  ) {
    if (regressions.isEmpty) {
      final improvementMsg = improvements.isEmpty
          ? 'No regressions.'
          : 'Improved: ${improvements.entries.map((e) => '${e.key} -${e.value}').join(', ')}';
      return RatchetResult(
        passed: true,
        regressions: [],
        improvements: improvements,
        message: 'Ratchet passed. $improvementMsg',
      );
    }

    final regMsg = regressions
        .map((r) => '  ${r.rule}: ${r.baseline} → ${r.current} (+${r.current - r.baseline})')
        .join('\n');
    return RatchetResult(
      passed: false,
      regressions: regressions,
      improvements: improvements,
      message: 'Ratchet failed — regressions detected:\n$regMsg',
    );
  }

  static Map<String, dynamic> _buildBaseline(List<Issue> issues) {
    return {
      'version': 1,
      'timestamp': DateTime.now().toIso8601String(),
      'total': issues.length,
      'rules': _countByRule(issues),
    };
  }

  static Map<String, int> _countByRule(List<Issue> issues) {
    final counts = <String, int>{};
    for (final issue in issues) {
      counts[issue.rule] = (counts[issue.rule] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
}

class RatchetResult {
  final bool passed;
  final List<RatchetRegression> regressions;
  final Map<String, int> improvements;
  final String message;

  RatchetResult({
    required this.passed,
    required this.regressions,
    this.improvements = const {},
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'message': message,
        'regressions': regressions.map((r) => r.toJson()).toList(),
        'improvements': improvements,
      };
}

class RatchetRegression {
  final String rule;
  final int baseline;
  final int current;

  RatchetRegression({
    required this.rule,
    required this.baseline,
    required this.current,
  });

  Map<String, dynamic> toJson() => {
        'rule': rule,
        'baseline': baseline,
        'current': current,
        'delta': current - baseline,
      };
}
