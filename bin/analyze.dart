import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'only',
      abbr: 'o',
      help: 'Run only a specific category of rules.',
      allowed: ['arch', 'dead', 'metrics', 'lint', 'all'],
      defaultsTo: 'all',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format.',
      allowed: ['console', 'json', 'markdown'],
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
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help.',
    );

  final results = parser.parse(args);

  if (results['help'] as bool) {
    _printUsage(parser);
    return;
  }

  final projectRoot = results['project'] as String? ?? Directory.current.path;
  final category = results['only'] as String;
  final format = results['format'] as String;
  final outputPath = results['output'] as String?;

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

  // Create all rules
  final allRules = <AnalyzerRule>[
    // Dead code
    DeadFilesRule(),
    DeadExportsRule(),
    // Architecture
    BannedImportsRule(),
    LayerDependencyRule(),
    FeatureIsolationRule(),
    ImportCycleRule(),
    // Metrics
    ComplexityRule(),
    BuildComplexityRule(),
    // Lint
    DisposeCheckRule(),
    AsyncSafetyRule(),
  ];

  final runner = RuleRunner(rules: allRules, config: context.config);

  // Run rules
  final List<Issue> issues;
  if (category == 'all') {
    issues = runner.runAll(context);
  } else {
    issues = runner.runCategory(context, category);
  }

  stopwatch.stop();

  // Output
  switch (format) {
    case 'json':
      print(JsonOutput.format(issues));
    case 'markdown':
      print(MarkdownOutput.format(issues));
    default:
      print(ConsoleOutput.format(issues, elapsed: stopwatch.elapsed));
  }

  // Write report to file (always, or when --output is specified)
  final reportPath = outputPath ?? '$projectRoot/.dart_sentinel/report.json';
  _writeReport(
    reportPath,
    issues: issues,
    projectRoot: projectRoot,
    elapsed: stopwatch.elapsed,
    category: category,
  );
  print('  Report saved to: $reportPath');
  print('');

  // Exit with error code if there are errors
  final hasErrors =
      issues.any((i) => i.severity == Severity.error);
  if (hasErrors) {
    exit(1);
  }
}

void _writeReport(
  String path, {
  required List<Issue> issues,
  required String projectRoot,
  required Duration elapsed,
  required String category,
}) {
  final dir = Directory(path).parent;
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final absRoot = Directory(projectRoot).absolute.path;

  final report = {
    'version': 1,
    'timestamp': DateTime.now().toIso8601String(),
    'projectRoot': absRoot,
    'elapsedMs': elapsed.inMilliseconds,
    'category': category,
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
  print('Dart Sentinel — Static analysis & metrics for Dart/Flutter');
  print('');
  print('Usage: dart run dart_sentinel [options]');
  print('       dart run dart_sentinel:analyze [options]');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Categories:');
  print('  all      Run all rules (default)');
  print('  arch     Architecture: banned imports, layers, feature isolation, cycles');
  print('  dead     Dead code: unreachable files, unused exports');
  print('  metrics  Metrics: complexity, LOC, nesting, build method');
  print('  lint     Lint: dispose checks, async safety');
  print('');
  print('Examples:');
  print('  dart run dart_sentinel                          # run all rules');
  print('  dart run dart_sentinel -o arch                  # architecture only');
  print('  dart run dart_sentinel -o metrics -f json       # metrics as JSON');
  print('  dart run dart_sentinel -p /path/to/project      # specify project');
}
