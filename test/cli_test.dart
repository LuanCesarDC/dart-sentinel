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
}
