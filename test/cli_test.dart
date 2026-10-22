import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<ProcessResult> _sentinel(List<String> args) =>
    Process.run('dart', ['run', 'bin/dart_sentinel.dart', ...args]);

Directory _project(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('sentinel_cli_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final entry in {
    'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    ...files,
  }.entries) {
    File(p.join(root.path, entry.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return root;
}

void main() {
  test('-p . and an absolute -p report the same issues', () async {
    final root = _project({
      'lib/main.dart': 'void main() {}\n',
      'lib/service.dart': 'int add(int a, int b) => a + b;\n',
      'test/other_test.dart': 'void main() {}\n',
    });
    final script = p.absolute('bin/dart_sentinel.dart');
    Future<Set<String>> rules(String projectArg) async {
      final result = await Process.run('dart', [
        'run',
        script,
        '-f',
        'json',
        '--no-report',
        '--no-cache',
        '-p',
        projectArg,
      ], workingDirectory: root.path);
      final issues = (jsonDecode(result.stdout as String) as Map)['issues'];
      return {for (final i in issues as List) '${i['rule']}:${i['file']}'};
    }

    final relative = await rules('.');
    final absolute = await rules(root.path);
    expect(relative, absolute);
    expect(relative.any((i) => i.startsWith('untested-files:')), isTrue);
  });

  test('-f json writes only JSON to stdout', () async {
    final root = _project({'lib/main.dart': 'void main() {}\n'});
    final result = await _sentinel([
      '-f',
      'json',
      '--no-report',
      '-p',
      root.path,
    ]);
    expect(() => jsonDecode(result.stdout as String), returnsNormally);
    expect(result.stderr, contains('analyzing project'));
  });

  test('invalid severity exits 2 with a clear message', () async {
    final root = _project({
      'lib/main.dart': 'void main() {}\n',
      'analyzer.yaml': 'rules:\n  complexity: loud\n',
    });
    final result = await _sentinel(['--no-report', '-p', root.path]);
    expect(result.exitCode, 2);
    expect(result.stderr, contains("invalid severity 'loud'"));
  });

  test('doctor flags dart_sentinel in dev_dependencies', () async {
    final root = _project({
      'pubspec.yaml':
          'name: demo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n'
          'dev_dependencies:\n  dart_sentinel: ^0.3.0\n',
    });
    final result = await _sentinel(['doctor', '-p', root.path]);
    expect(result.exitCode, 1);
    expect(result.stdout, contains('remove it from pubspec.yaml'));
  });

  test('init writes analyzer.yaml from the detected template', () async {
    final root = _project({
      'lib/ui/home.dart': 'class Home {}\n',
      'lib/data/repo.dart': 'class Repo {}\n',
    });
    final result = await _sentinel(['init', '--no-hooks', '-p', root.path]);
    expect(result.stdout, contains('flutter_official'));
    expect(File(p.join(root.path, 'analyzer.yaml')).existsSync(), isTrue);
  });

  test('rules lists rules and reflects off', () async {
    final root = _project({'analyzer.yaml': 'rules:\n  dead-files: off\n'});
    final result = await _sentinel(['rules', '-p', root.path]);
    expect(result.stdout, matches(RegExp(r'○ dead-files\s+dead\s+off')));
  });

  test('-o accepts comma-separated and repeated categories', () async {
    final root = _project({'lib/main.dart': 'void main() {}\n'});
    for (final args in [
      ['-o', 'arch,lint'],
      ['-o', 'arch', '-o', 'lint'],
    ]) {
      final result = await _sentinel([...args, '--no-report', '-p', root.path]);
      expect(
        result.stderr,
        isNot(contains('FormatException')),
        reason: '$args',
      );
      expect(result.exitCode, 0, reason: '$args');
    }
  });

  test(
    '--fail-on-regression compares migrations to the saved baseline',
    () async {
      const config = '''
architecture:
  banned_symbols:
    - paths: ["lib/**"]
      deny: ["OldButton"]
      suggest: AppButton
''';
      final root = _project({
        'analyzer.yaml': config,
        'lib/a.dart': 'void a() { OldButton(); }\n',
      });
      await _sentinel(['-o', 'migrations', '--save-baseline', '-p', root.path]);

      final same = await _sentinel([
        '-o',
        'migrations',
        '--fail-on-regression',
        '-p',
        root.path,
      ]);
      expect(same.exitCode, 0);

      File(
        p.join(root.path, 'lib/b.dart'),
      ).writeAsStringSync('void b() { OldButton(); }\n');
      final worse = await _sentinel([
        '-o',
        'migrations',
        '--fail-on-regression',
        '-p',
        root.path,
      ]);
      expect(worse.exitCode, 1);
      expect(worse.stderr, contains('OldButton'));
    },
  );

  test('--profile flutter relaxes build-method limits', () async {
    final root = _project({'lib/main.dart': 'void main() {}\n'});
    final result = await _sentinel([
      '--profile',
      'flutter',
      '--no-report',
      '-p',
      root.path,
    ]);
    expect(result.exitCode, 0);
  });

  test(
    '--fatal-infos fails on an info that the default run tolerates',
    () async {
      final root = _project({
        'lib/main.dart': 'dynamic f() => 1;\nvoid main() { f(); }\n',
      });
      final plain = await _sentinel([
        '--no-report',
        '-o',
        'slop',
        '-p',
        root.path,
      ]);
      expect(plain.exitCode, 0);
      final strict = await _sentinel([
        '--no-report',
        '-o',
        'slop',
        '--fatal-infos',
        '-p',
        root.path,
      ]);
      expect(strict.exitCode, 1);
    },
  );

  test('-f sarif keeps stdout clean JSON', () async {
    final root = _project({'lib/main.dart': 'dynamic f() => 1;\n'});
    final result = await _sentinel([
      '-f',
      'sarif',
      '--no-report',
      '-p',
      root.path,
    ]);
    expect(jsonDecode(result.stdout as String)['version'], '2.1.0');
  });

  test('metrics prints a table and a debt estimate', () async {
    final root = _project({'lib/main.dart': 'void main() {}\n'});
    final result = await _sentinel(['metrics', '-p', root.path]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('lib/main.dart'));
    expect(result.stdout, contains('remediation'));
  });
}
