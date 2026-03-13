import '../core/project_context.dart';
import '../rules/banned_symbols_rule.dart';

/// Tracks migration progress for banned-symbols rules.
///
/// Counts remaining usages per banned-symbol config and computes
/// completion percentages to help teams track gradual migrations.
class MigrationTracker {
  final ProjectContext context;

  MigrationTracker(this.context);

  /// Compute migration progress for all banned-symbol configs.
  MigrationReport track() {
    final configs = context.config.bannedSymbols;
    if (configs.isEmpty) {
      return MigrationReport(migrations: [], totalRemaining: 0);
    }

    // Run banned-symbols rule to get current violations
    final rule = BannedSymbolsRule();
    final issues = rule.run(context);

    final migrations = <MigrationEntry>[];
    for (final config in configs) {
      final matching = issues.where((i) =>
          config.deny.any((d) => i.message.contains(d))).toList();

      final bySymbol = <String, int>{};
      for (final symbol in config.deny) {
        bySymbol[symbol] =
            matching.where((i) => i.message.contains(symbol)).length;
      }

      migrations.add(MigrationEntry(
        symbols: config.deny,
        suggest: config.suggest,
        message: config.message,
        remaining: matching.length,
        bySymbol: bySymbol,
        files: matching.map((i) => i.file).toSet().toList()..sort(),
      ));
    }

    return MigrationReport(
      migrations: migrations,
      totalRemaining: issues.length,
    );
  }
}

class MigrationReport {
  final List<MigrationEntry> migrations;
  final int totalRemaining;

  MigrationReport({
    required this.migrations,
    required this.totalRemaining,
  });

  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('Migration Progress');
    buffer.writeln('${'═' * 60}');

    if (migrations.isEmpty) {
      buffer.writeln('No banned-symbols migrations configured.');
      return buffer.toString();
    }

    for (final m in migrations) {
      final label = m.suggest.isNotEmpty
          ? '${m.symbols.join(', ')} → ${m.suggest}'
          : m.symbols.join(', ');
      buffer.writeln('');
      buffer.writeln('$label');
      buffer.writeln('  Remaining: ${m.remaining} usages in ${m.files.length} files');

      for (final entry in m.bySymbol.entries) {
        if (entry.value > 0) {
          buffer.writeln('    ${entry.key}: ${entry.value}');
        }
      }

      if (m.remaining == 0) {
        buffer.writeln('  ✅ Migration complete!');
      }
    }

    buffer.writeln('');
    buffer.writeln('Total remaining: $totalRemaining');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'totalRemaining': totalRemaining,
        'migrations': migrations.map((m) => m.toJson()).toList(),
      };
}

class MigrationEntry {
  final List<String> symbols;
  final String suggest;
  final String message;
  final int remaining;
  final Map<String, int> bySymbol;
  final List<String> files;

  MigrationEntry({
    required this.symbols,
    required this.suggest,
    required this.message,
    required this.remaining,
    required this.bySymbol,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
        'symbols': symbols,
        'suggest': suggest,
        'remaining': remaining,
        'bySymbol': bySymbol,
        'files': files,
      };
}
