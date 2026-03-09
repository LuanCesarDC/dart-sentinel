import 'dart:convert';
import 'dart:math' as math;

import '../core/issue.dart';

/// Formats issues for console output with colors and alignment.
class ConsoleOutput {
  /// Print issues to console with colored severity indicators.
  static String format(List<Issue> issues, {Duration? elapsed}) {
    if (issues.isEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('');
      buffer.writeln('  ✅ No issues found!');
      if (elapsed != null) {
        buffer.writeln('  ⏱  ${elapsed.inMilliseconds}ms');
      }
      buffer.writeln('');
      return buffer.toString();
    }

    final buffer = StringBuffer();
    buffer.writeln('');

    // Group by file
    final grouped = <String, List<Issue>>{};
    for (final issue in issues) {
      grouped.putIfAbsent(issue.file, () => []).add(issue);
    }

    for (final entry in grouped.entries) {
      buffer.writeln('  ${entry.key}');
      for (final issue in entry.value) {
        final icon = switch (issue.severity) {
          Severity.error => '  ✖',
          Severity.warning => '  ⚠',
          Severity.info => '  ℹ',
        };

        final loc = issue.line > 0 ? ':${issue.line}' : '';
        buffer.writeln(
            '$icon  ${issue.rule}$loc — ${issue.message}');
      }
      buffer.writeln('');
    }

    // Summary
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings =
        issues.where((i) => i.severity == Severity.warning).length;
    final infos = issues.where((i) => i.severity == Severity.info).length;

    final parts = <String>[];
    if (errors > 0) parts.add('$errors error${errors > 1 ? 's' : ''}');
    if (warnings > 0) parts.add('$warnings warning${warnings > 1 ? 's' : ''}');
    if (infos > 0) parts.add('$infos info${infos > 1 ? 's' : ''}');

    buffer.writeln('  ${parts.join(', ')} in ${grouped.length} file${grouped.length > 1 ? 's' : ''}');
    if (elapsed != null) {
      buffer.writeln('  ⏱  ${elapsed.inMilliseconds}ms');
    }
    buffer.writeln('');

    return buffer.toString();
  }

  /// Format metrics as a table (top N worst files).
  static String formatMetricsTable(
    List<FileMetricsSummary> metrics, {
    int top = 20,
  }) {
    if (metrics.isEmpty) return '  No metrics data.\n';

    // Sort by LOC descending
    final sorted = [...metrics]..sort((a, b) => b.loc.compareTo(a.loc));
    final display = sorted.take(top).toList();

    // Calculate column widths
    final fileWidth =
        math.max(4, display.map((m) => m.file.length).reduce(math.max));
    final locWidth =
        math.max(3, display.map((m) => m.loc.toString().length).reduce(math.max));
    final ccWidth =
        math.max(6, display.map((m) => m.maxCC.toString().length + 5).reduce(math.max));
    final methodsWidth =
        math.max(7, display.map((m) => m.methods.toString().length).reduce(math.max));

    final buffer = StringBuffer();
    buffer.writeln('');

    // Header
    buffer.writeln(
        '  ${'File'.padRight(fileWidth)}  ${'LOC'.padLeft(locWidth)}  ${'Max CC'.padLeft(ccWidth)}  ${'Methods'.padLeft(methodsWidth)}');
    buffer.writeln(
        '  ${'─' * fileWidth}  ${'─' * locWidth}  ${'─' * ccWidth}  ${'─' * methodsWidth}');

    for (final m in display) {
      final ccStr = m.maxCC > 20
          ? '${m.maxCC} ⚠️'
          : m.maxCC > 10
              ? '${m.maxCC} !'
              : '${m.maxCC}';
      buffer.writeln(
          '  ${m.file.padRight(fileWidth)}  ${m.loc.toString().padLeft(locWidth)}  ${ccStr.padLeft(ccWidth)}  ${m.methods.toString().padLeft(methodsWidth)}');
    }

    buffer.writeln('');
    return buffer.toString();
  }
}

/// Formats issues as JSON for CI consumption.
class JsonOutput {
  static String format(List<Issue> issues) {
    final json = issues.map((i) => i.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert({
      'issues': json,
      'summary': {
        'total': issues.length,
        'errors': issues.where((i) => i.severity == Severity.error).length,
        'warnings':
            issues.where((i) => i.severity == Severity.warning).length,
        'infos': issues.where((i) => i.severity == Severity.info).length,
      },
    });
  }
}

/// Formats issues as Markdown for PR comments.
class MarkdownOutput {
  static String format(List<Issue> issues) {
    if (issues.isEmpty) return '## ✅ Analysis: No issues found\n';

    final buffer = StringBuffer();
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings =
        issues.where((i) => i.severity == Severity.warning).length;

    buffer.writeln(
        '## 🔍 Analysis: $errors error${errors > 1 ? 's' : ''}, $warnings warning${warnings > 1 ? 's' : ''}');
    buffer.writeln('');

    // Group by rule
    final grouped = <String, List<Issue>>{};
    for (final issue in issues) {
      grouped.putIfAbsent(issue.rule, () => []).add(issue);
    }

    for (final entry in grouped.entries) {
      buffer.writeln('### ${entry.key} (${entry.value.length})');
      buffer.writeln('');
      buffer.writeln('| Severity | File | Line | Message |');
      buffer.writeln('|----------|------|------|---------|');
      for (final issue in entry.value) {
        final icon = switch (issue.severity) {
          Severity.error => '🔴',
          Severity.warning => '🟡',
          Severity.info => '🔵',
        };
        final loc = issue.line > 0 ? '${issue.line}' : '-';
        buffer.writeln(
            '| $icon | `${issue.file}` | $loc | ${issue.message} |');
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }
}

/// Summary of metrics for a single file.
class FileMetricsSummary {
  final String file;
  final int loc;
  final int maxCC;
  final int methods;

  const FileMetricsSummary({
    required this.file,
    required this.loc,
    required this.maxCC,
    required this.methods,
  });
}
