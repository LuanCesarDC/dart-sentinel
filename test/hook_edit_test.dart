import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('hook_edit_test_');
    File(p.join(fixtureDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_app
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    Directory(p.join(fixtureDir.path, 'lib')).createSync();
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runHookEdit(String filePath) => _runDartSentinel(
    entrypoint: entrypoint,
    workingDirectory: repoRoot,
    args: ['hook-edit'],
    stdinPayload: {
      'tool_name': 'Edit',
      'tool_input': {'file_path': filePath},
      'cwd': fixtureDir.path,
    },
  );

  test('allows a clean file (exit 0, no stderr)', () async {
    final target = p.join(fixtureDir.path, 'lib', 'clean.dart');
    File(target).writeAsStringSync('int add(int a, int b) => a + b;\n');

    final result = await runHookEdit(target);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });

  test('blocks a file with an error-severity violation', () async {
    final target = p.join(fixtureDir.path, 'lib', 'huge.dart');
    // 610 lines trips complexity's file-LOC error threshold (>= 600).
    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(target).writeAsStringSync(lines.join('\n'));

    final result = await runHookEdit(target);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('complexity'));
  });

  test('allows non-Dart files without analyzing', () async {
    final target = p.join(fixtureDir.path, 'README.md');
    File(target).writeAsStringSync('# fixture');

    final result = await runHookEdit(target);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });
}

Future<ProcessResult> _runDartSentinel({
  required String entrypoint,
  required String workingDirectory,
  required List<String> args,
  required Map<String, dynamic> stdinPayload,
}) async {
  final process = await Process.start('dart', [
    'run',
    entrypoint,
    ...args,
  ], workingDirectory: workingDirectory);

  process.stdin.write(jsonEncode(stdinPayload));
  await process.stdin.close();

  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(
    process.pid,
    exitCode,
    await stdoutFuture,
    await stderrFuture,
  );
}
