import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('hook_stop_test_');
    File(p.join(fixtureDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_app
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    Directory(p.join(fixtureDir.path, 'lib')).createSync();
    File(p.join(fixtureDir.path, 'lib', 'clean.dart'))
        .writeAsStringSync('int add(int a, int b) => a + b;\n');
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runHookStop({bool stopHookActive = false}) => _run(
    entrypoint: entrypoint,
    workingDirectory: repoRoot,
    args: ['hook-stop'],
    stdinPayload: {'cwd': fixtureDir.path, 'stop_hook_active': stopHookActive},
  );

  test('creates a baseline and allows on first run', () async {
    final result = await runHookStop();

    expect(result.exitCode, 0);
    expect(
      File(p.join(fixtureDir.path, '.dart_sentinel', 'baseline.json'))
          .existsSync(),
      isTrue,
    );
  });

  test('allows when nothing regressed since the baseline', () async {
    await runHookStop(); // creates baseline

    final result = await runHookStop();

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Ratchet passed'));
  });

  test('blocks when a new error-severity issue regresses the baseline', () async {
    await runHookStop(); // creates baseline with just clean.dart

    // Introduce a file-LOC error-severity violation.
    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(p.join(fixtureDir.path, 'lib', 'huge.dart'))
        .writeAsStringSync(lines.join('\n'));

    final result = await runHookStop();

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Ratchet failed'));
  });

  test('allows immediately when stop_hook_active is true, even with a regression', () async {
    await runHookStop(); // creates baseline

    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(p.join(fixtureDir.path, 'lib', 'huge.dart'))
        .writeAsStringSync(lines.join('\n'));

    final result = await runHookStop(stopHookActive: true);

    expect(result.exitCode, 0);
  });
}

Future<ProcessResult> _run({
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
