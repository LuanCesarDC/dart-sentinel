// `dart_sentinel metrics` — raw per-file metrics (LOC, cyclomatic complexity,
// maintainability index) plus an estimate of the remediation time.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';

import 'rule_registry.dart';

const _defaultTop = 20;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.')
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['console', 'json'],
      defaultsTo: 'console',
    )
    ..addOption(
      'sort',
      allowed: ['maintainability', 'loc', 'complexity'],
      defaultsTo: 'maintainability',
      help: 'Worst files first by this metric.',
    )
    ..addOption('top', defaultsTo: '$_defaultTop', help: 'Rows to show.');
  final results = parser.parse(args);
  final root = results['project'] as String? ?? Directory.current.path;

  final context = await ProjectContext.build(root);
  final metrics = CodeMetrics(context).collect();
  final issues = RuleRunner(
    rules: allSentinelRules(),
    config: context.config,
  ).runAll(context);
  final debtMinutes = estimateDebtMinutes(issues);

  final sorted = _sorted(metrics, results['sort'] as String);
  if (results['format'] == 'json') {
    print(
      const JsonEncoder.withIndent('  ').convert({
        'files': [for (final m in sorted) m.toJson()],
        'summary': _summary(metrics, issues.length, debtMinutes),
      }),
    );
    return;
  }
  final top = int.tryParse(results['top'] as String) ?? _defaultTop;
  print(_table(sorted.take(top).toList()));
  print(_summaryText(metrics, issues.length, debtMinutes));
}

List<FileMetrics> _sorted(List<FileMetrics> metrics, String by) {
  final list = [...metrics];
  switch (by) {
    case 'loc':
      list.sort((a, b) => b.loc.compareTo(a.loc));
    case 'complexity':
      list.sort((a, b) => b.maxComplexity.compareTo(a.maxComplexity));
    default:
      list.sort((a, b) => a.maintainability.compareTo(b.maintainability));
  }
  return list;
}

Map<String, Object> _summary(
  List<FileMetrics> metrics,
  int issueCount,
  int debtMinutes,
) {
  final totalLoc = metrics.fold(0, (sum, m) => sum + m.loc);
  return {
    'files': metrics.length,
    'loc': totalLoc,
    'averageMaintainability': metrics.isEmpty
        ? 100
        : double.parse(
            (metrics.fold(0.0, (sum, m) => sum + m.maintainability) /
                    metrics.length)
                .toStringAsFixed(1),
          ),
    'issues': issueCount,
    'estimatedDebtMinutes': debtMinutes,
  };
}

String _summaryText(List<FileMetrics> metrics, int issueCount, int minutes) {
  final summary = _summary(metrics, issueCount, minutes);
  final hours = (minutes / 60).toStringAsFixed(1);
  return '  ${summary['files']} files, ${summary['loc']} lines of code, '
      'average maintainability ${summary['averageMaintainability']}/100\n'
      '  $issueCount issues ≈ $hours h of remediation '
      '(errors 30 min, warnings 15, infos 5)\n';
}

String _table(List<FileMetrics> rows) {
  if (rows.isEmpty) return '  No Dart files found.';
  final width = rows.map((m) => m.file.length).reduce((a, b) => a > b ? a : b);
  final buffer = StringBuffer()
    ..writeln(
      '  ${'File'.padRight(width)}  ${'MI'.padLeft(5)}  ${'LOC'.padLeft(5)}  '
      '${'Max CC'.padLeft(6)}  ${'Avg CC'.padLeft(6)}  Methods',
    );
  for (final m in rows) {
    buffer.writeln(
      '  ${m.file.padRight(width)}  '
      '${m.maintainability.toStringAsFixed(1).padLeft(5)}  '
      '${'${m.loc}'.padLeft(5)}  ${'${m.maxComplexity}'.padLeft(6)}  '
      '${m.averageComplexity.toStringAsFixed(1).padLeft(6)}  ${m.methods}',
    );
  }
  return buffer.toString();
}
