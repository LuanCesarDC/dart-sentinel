import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';

Future<void> main(List<String> args) async {
  final parser = _buildParser();
  final results = parser.parse(args);

  if (results['help'] as bool) {
    _printUsage(parser);
    return;
  }

  final projectRoot = results['project'] as String? ?? Directory.current.path;
  final category = results['only'] as String;
  final format = results['format'] as String;
  final outputPath = results['output'] as String?;
  final noReport = results['no-report'] as bool;
  final saveBaseline = results['save-baseline'] as bool;
  final checkBaseline = results['check-baseline'] as bool;
  final files = results['files'] as List<String>;

  // Validate project
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found at $projectRoot');
    stderr.writeln(
        'Run this command from your Dart/Flutter project root, or use --project.');
    exit(1);
  }

  print('🔍 Dart Sentinel — analyzing project...');
  print('');

  final stopwatch = Stopwatch()..start();

  // Build project context
  final context = await ProjectContext.build(projectRoot);

  print(
      '  Scanned ${context.allFiles.length} files (${context.entrypoints.length} entrypoints)');

  // ── Special analysis modes ──

  final handled = _trySpecialMode(category, context, files, format);
  if (handled) return;

  // ── Standard rule analysis ──
  final issues = _runRuleAnalysis(context, category);

  stopwatch.stop();

  _printResults(issues, format, stopwatch.elapsed);

  final reportPath = outputPath ?? '$projectRoot/.dart_sentinel/report.json';
  if (!noReport) {
    _writeReport(reportPath, issues, (
      projectRoot: projectRoot,
      elapsed: stopwatch.elapsed,
      category: category,
    ));
    print('  Report saved to: $reportPath');
  }
  _handleRatchet(
    issues: issues,
    projectRoot: projectRoot,
    save: saveBaseline,
    check: checkBaseline,
  );
  print('');

  if (issues.any((i) => i.severity == Severity.error)) {
    exit(1);
  }
}

bool _trySpecialMode(
  String category,
  ProjectContext context,
  List<String> files,
  String format,
) {
  switch (category) {
    case 'impact':
      _runImpact(context, files, format);
      return true;
    case 'map':
      _runMap(context, format);
      return true;
    case 'migrations':
      _runMigrations(context, format);
      return true;
    default:
      return false;
  }
}

void _handleRatchet({
  required List<Issue> issues,
  required String projectRoot,
  required bool save,
  required bool check,
}) {
  final baselinePath = '$projectRoot/.dart_sentinel/baseline.json';
  if (save) {
    Ratchet.saveBaseline(issues, path: baselinePath);
    print('  Baseline saved to: $baselinePath');
  }
  if (check) {
    final ratchetResult = Ratchet.check(issues, path: baselinePath);
    print('');
    print(ratchetResult.message);
    if (!ratchetResult.passed) exit(1);
  }
}

ArgParser _buildParser() {
  return ArgParser()
    ..addOption(
      'only',
      abbr: 'o',
      help: 'Run only a specific category of rules.',
      allowed: [
        'arch', 'dead', 'metrics', 'lint', 'slop',
        'impact', 'map', 'migrations', 'all',
      ],
      defaultsTo: 'all',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format.',
      allowed: ['console', 'json', 'markdown', 'mermaid'],
      defaultsTo: 'console',
    )
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the project root (defaults to current directory).',
    )
    ..addOption(
      'output',
      help: 'Write JSON report to file (default: .dart_sentinel/report.json).',
    )
    ..addMultiOption(
      'files',
      help: 'Files to analyze for impact (used with -o impact).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help.',
    )
    ..addFlag(
      'no-report',
      negatable: false,
      help: 'Skip writing the JSON report file (terminal output only).',
    )
    ..addFlag(
      'save-baseline',
      negatable: false,
      help: 'Save current issue counts as the ratchet baseline.',
    )
    ..addFlag(
      'check-baseline',
      negatable: false,
      help: 'Compare current issues against the saved baseline (CI mode).',
    );
}

List<Issue> _runRuleAnalysis(ProjectContext context, String category) {
  final allRules = <AnalyzerRule>[
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
  ];
  final runner = RuleRunner(rules: allRules, config: context.config);
  if (category == 'all') return runner.runAll(context);
  return runner.runCategory(context, category);
}

void _printResults(List<Issue> issues, String format, Duration elapsed) {
  switch (format) {
    case 'json':
      print(JsonOutput.format(issues));
    case 'markdown':
      print(MarkdownOutput.format(issues));
    default:
      print(ConsoleOutput.format(issues, elapsed: elapsed));
  }
}

void _runImpact(ProjectContext context, List<String> files, String format) {
  final impact = ImpactAnalyzer(context);
  if (files.isEmpty) {
    _printHotSpots(impact.hotSpots(), format);
  } else {
    _printImpactReport(impact.analyze(files), format);
  }
  print('');
}

void _printHotSpots(List<HotSpot> spots, String format) {
  if (format == 'json') {
    print(const JsonEncoder.withIndent('  ').convert(
      spots.map((s) => {
        'file': s.file,
        'directDependents': s.directDependents,
        'transitiveDependents': s.transitiveDependents,
      }).toList(),
    ));
    return;
  }
  print('  Hot Spots (highest blast radius):');
  print('');
  for (final s in spots) {
    print('  ${s.transitiveDependents.toString().padLeft(3)} transitive '
        '(${s.directDependents} direct)  ${s.file}');
  }
}

void _printImpactReport(ImpactReport report, String format) {
  if (format == 'json') {
    print(const JsonEncoder.withIndent('  ').convert({
      'changedFiles': report.changedFiles,
      'totalAffected': report.totalAffected,
      'totalFiles': report.totalFiles,
      'impactPercent': report.impactPercent.toStringAsFixed(1),
      'affectedByCategory': report.affectedByCategory,
      'affectedFiles': report.affectedFiles,
    }));
    return;
  }
  print('  Changed: ${report.changedFiles.join(', ')}');
  print('  Affected: ${report.totalAffected} / ${report.totalFiles} '
      'files (${report.impactPercent.toStringAsFixed(1)}%)');
  if (report.affectedByCategory.isNotEmpty) {
    print('  By category:');
    for (final entry in report.affectedByCategory.entries) {
      print('    ${entry.key}: ${entry.value}');
    }
  }
}

void _runMap(ProjectContext context, String format) {
  final mapper = DependencyMapper(context);
  switch (format) {
    case 'mermaid':
      print(mapper.toMermaid());
    case 'json':
      print(const JsonEncoder.withIndent('  ').convert({
        'totalFiles': context.allFiles.length,
        'totalEdges': context.importGraph.values.fold<int>(
            0, (s, v) => s + v.length),
      }));
    default:
      print(mapper.toTextSummary());
  }
  print('');
}

void _runMigrations(ProjectContext context, String format) {
  final tracker = MigrationTracker(context);
  final report = tracker.track();
  if (format == 'json') {
    print(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } else {
    print(report.toText());
  }
  print('');
}

void _writeReport(
  String path,
  List<Issue> issues,
  ({String projectRoot, Duration elapsed, String category}) meta,
) {
  final dir = Directory(path).parent;
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final absRoot = Directory(meta.projectRoot).absolute.path;

  final report = {
    'version': 1,
    'timestamp': DateTime.now().toIso8601String(),
    'projectRoot': absRoot,
    'elapsedMs': meta.elapsed.inMilliseconds,
    'category': meta.category,
    'summary': {
      'total': issues.length,
      'errors': issues.where((i) => i.severity == Severity.error).length,
      'warnings': issues.where((i) => i.severity == Severity.warning).length,
      'infos': issues.where((i) => i.severity == Severity.info).length,
      'files': issues.map((i) => i.file).toSet().length,
    },
    'issues': issues.map((i) {
      // Build absolute path for VS Code to resolve
      var filePath = i.file;
      if (!filePath.startsWith('/')) {
        filePath = '$absRoot/${i.file}';
      }
      return {
        'rule': i.rule,
        'message': i.message,
        'file': filePath,
        'relativeFile': i.file,
        'line': i.line,
        'severity': i.severity.toString(),
      };
    }).toList(),
  };

  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
}

void _printUsage(ArgParser parser) {
  print('''
Dart Sentinel — Static analysis & metrics for Dart/Flutter

Usage: dart run dart_sentinel [options]
       dart run dart_sentinel:analyze [options]
       dart run bin/dart_sentinel.dart [options]  (from source)

Options:
${parser.usage}

Categories:
  all        Run all rules (default)
  arch       Architecture: banned imports, layers, feature isolation, cycles
  dead       Dead code: unreachable files, unused exports
  metrics    Metrics: complexity, LOC, nesting, build method
  lint       Lint: dispose checks, async safety
  slop       AI Slop: empty catch, dead todos, generic names, verbose logs, etc.
  impact     Change impact analysis (use --files to specify changed files)
  map        Dependency map (use -f mermaid for Mermaid diagram)
  migrations Migration tracker for banned-symbols progress

Examples:
  dart run dart_sentinel                                    # run all rules
  dart run dart_sentinel -o arch                            # architecture only
  dart run dart_sentinel -o metrics -f json                 # metrics as JSON
  dart run dart_sentinel -p /path/to/project                # specify project
  dart run dart_sentinel -o impact --files lib/src/core/issue.dart  # blast radius
  dart run dart_sentinel -o impact                          # hot spots
  dart run dart_sentinel -o map -f mermaid                  # Mermaid diagram
  dart run dart_sentinel -o migrations                      # migration progress
  dart run dart_sentinel --save-baseline                    # save ratchet baseline
  dart run dart_sentinel --check-baseline                   # CI ratchet check
  dart run dart_sentinel:analyze                            # explicit script''');
}
