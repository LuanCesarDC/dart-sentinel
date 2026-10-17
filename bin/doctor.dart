// `dart_sentinel doctor` — checks the setup that makes Sentinel work as an
// automatic gate: Dart version, PATH, analyzer.yaml, hooks and pubspec.
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;

import 'pubspec_check.dart';
import 'rule_registry.dart';

const _minDartMajor = 3;
const _minDartMinor = 9;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.');
  final projectRoot =
      parser.parse(args)['project'] as String? ?? Directory.current.path;

  final checks = [
    _checkDartVersion(),
    _checkOnPath(),
    _checkPubspec(projectRoot),
    _checkAnalyzerYaml(projectRoot),
    _checkHooks(projectRoot),
  ];

  var failed = false;
  for (final check in checks) {
    final icon = switch (check.status) {
      _Status.ok => '✔',
      _Status.warn => '⚠',
      _Status.fail => '✖',
    };
    print('$icon ${check.title}');
    for (final detail in check.details) {
      print('    $detail');
    }
    if (check.status == _Status.fail) failed = true;
  }
  if (failed) exit(1);
}

enum _Status { ok, warn, fail }

class _Check {
  final String title;
  final _Status status;
  final List<String> details;
  _Check(this.title, this.status, [this.details = const []]);
}

_Check _checkDartVersion() {
  final match = RegExp(r'(\d+)\.(\d+)\.\d+').firstMatch(Platform.version);
  final major = int.tryParse(match?.group(1) ?? '') ?? 0;
  final minor = int.tryParse(match?.group(2) ?? '') ?? 0;
  final supported =
      major > _minDartMajor ||
      (major == _minDartMajor && minor >= _minDartMinor);
  final version = match?.group(0) ?? Platform.version;
  return supported
      ? _Check('Dart $version', _Status.ok)
      : _Check('Dart $version', _Status.fail, [
          'Sentinel needs Dart $_minDartMajor.$_minDartMinor or newer.',
        ]);
}

_Check _checkOnPath() {
  final lookup = Platform.isWindows ? 'where' : 'which';
  final result = Process.runSync(lookup, ['dart_sentinel']);
  if (result.exitCode == 0) {
    return _Check('dart_sentinel is on PATH', _Status.ok, [
      (result.stdout as String).trim().split('\n').first,
    ]);
  }
  return _Check('dart_sentinel is not on PATH', _Status.fail, [
    'Hooks call `dart_sentinel` directly. Run '
        '`dart pub global activate dart_sentinel` and add '
        '~/.pub-cache/bin to PATH.',
  ]);
}

_Check _checkPubspec(String projectRoot) {
  if (!File(p.join(projectRoot, 'pubspec.yaml')).existsSync()) {
    return _Check('pubspec.yaml not found', _Status.fail, [
      'Run doctor from the project root or pass --project.',
    ]);
  }
  final section = sentinelDependencySection(projectRoot);
  if (section == null) {
    return _Check('dart_sentinel is not a project dependency', _Status.ok);
  }
  return _Check('Version conflict risk', _Status.fail, [
    dependencyConflictAdvice(section),
  ]);
}

_Check _checkAnalyzerYaml(String projectRoot) {
  if (!File(p.join(projectRoot, 'analyzer.yaml')).existsSync()) {
    return _Check('analyzer.yaml not found', _Status.fail, [
      'Run `dart_sentinel init` to create one from a template.',
    ]);
  }
  final config = AnalyzerConfig.load(projectRoot);
  final warnings = config.validate(allSentinelRules().map((r) => r.name));
  final problems = [
    ...config.problems.map((m) => 'error: $m'),
    ...warnings.map((m) => 'warning: $m'),
  ];
  if (problems.isEmpty) return _Check('analyzer.yaml is valid', _Status.ok);
  return _Check(
    'analyzer.yaml has problems',
    config.problems.isEmpty ? _Status.warn : _Status.fail,
    problems,
  );
}

_Check _checkHooks(String projectRoot) {
  final file = File(p.join(projectRoot, '.claude', 'settings.json'));
  final content = file.existsSync() ? file.readAsStringSync() : '';
  final hasEdit = content.contains('dart_sentinel hook-edit');
  final hasStop = content.contains('dart_sentinel hook-stop');
  if (hasEdit && hasStop) {
    return _Check('Claude Code hooks installed', _Status.ok);
  }
  return _Check('Claude Code hooks missing', _Status.warn, [
    'Without hooks Sentinel is advisory only. Run `dart_sentinel setup-hooks`.',
  ]);
}
