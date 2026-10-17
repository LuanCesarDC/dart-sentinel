import 'dart:convert';
import 'dart:io';

import 'migration_tracker.dart';

/// Remembers how many usages each migration had, so CI can fail when a
/// migration in progress goes backwards (not only when it reaches zero).
class MigrationBaseline {
  static const fileName = '.dart_sentinel/migrations.json';

  /// Saves the current remaining count of every migration in [report].
  static void save(MigrationReport report, String projectRoot) {
    final file = File('$projectRoot/$fileName')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in report.migrations) _key(entry): entry.remaining,
      }),
    );
  }

  /// Messages for every migration whose remaining count grew since [save].
  /// Returns null when no baseline exists.
  static List<String>? regressions(MigrationReport report, String projectRoot) {
    final file = File('$projectRoot/$fileName');
    if (!file.existsSync()) return null;
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return [
      for (final entry in report.migrations)
        if (entry.remaining > _savedCount(saved, entry))
          '${_key(entry)}: ${_savedCount(saved, entry)} → ${entry.remaining} '
              'remaining',
    ];
  }

  static int _savedCount(Map<String, dynamic> saved, MigrationEntry entry) {
    final count = saved[_key(entry)];
    return count is int ? count : 0;
  }

  static String _key(MigrationEntry entry) => entry.symbols.join(', ');
}
