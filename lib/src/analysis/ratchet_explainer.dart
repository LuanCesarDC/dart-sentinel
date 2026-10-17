import '../core/issue.dart';

/// Pinpoints which files made a ratchet rule worse, from the per-file counts
/// stored in the baseline.
class RatchetExplainer {
  /// Files whose per-rule count grew since the baseline, as
  /// `rule` → (`file` → increase). Empty for baselines saved before 0.5.1,
  /// which carry no per-file counts.
  static Map<String, Map<String, int>> findCulprits(
    List<Issue> issues,
    Object? savedFiles,
  ) {
    if (savedFiles is! Map) return {};
    final current = countByRuleAndFile(issues);
    final culprits = <String, Map<String, int>>{};
    for (final rule in current.entries) {
      final saved = savedFiles[rule.key];
      final before = saved is Map ? saved : const {};
      for (final file in rule.value.entries) {
        final increase = file.value - _savedCount(before, file.key);
        if (increase > 0) {
          culprits.putIfAbsent(rule.key, () => {})[file.key] = increase;
        }
      }
    }
    return culprits;
  }

  static const _maxFilesShown = 8;

  static String explain(
    List<String> regressedRules,
    Map<String, Map<String, int>> culprits,
  ) {
    final buffer = StringBuffer();
    for (final rule in regressedRules) {
      final files = culprits[rule];
      if (files == null) continue;
      final worst = files.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      buffer.write('\n\n  $rule — worse in:');
      for (final file in worst.take(_maxFilesShown)) {
        buffer.write('\n    ${file.key} (+${file.value})');
      }
      if (worst.length > _maxFilesShown) {
        buffer.write('\n    … and ${worst.length - _maxFilesShown} more');
      }
    }
    return buffer.toString();
  }

  static Map<String, Map<String, int>> countByRuleAndFile(List<Issue> issues) {
    final counts = <String, Map<String, int>>{};
    for (final issue in issues) {
      final files = counts.putIfAbsent(issue.rule, () => {});
      files[issue.file] = (files[issue.file] ?? 0) + 1;
    }
    return counts;
  }

  static int _savedCount(Map saved, String file) {
    final count = saved[file];
    return count is int ? count : 0;
  }
}
