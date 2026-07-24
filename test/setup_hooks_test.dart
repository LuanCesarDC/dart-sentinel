import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final entrypoint = p.join(repoRoot, 'bin', 'dart_sentinel.dart');
  late Directory fixtureDir;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('setup_hooks_test_');
  });

  tearDown(() {
    fixtureDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> runSetupHooks() => Process.run('dart', [
    'run',
    entrypoint,
    'setup-hooks',
    '--project',
    fixtureDir.path,
  ], workingDirectory: repoRoot);

  File settingsFile() =>
      File(p.join(fixtureDir.path, '.claude', 'settings.json'));

  test('warns and writes nothing when analyzer.yaml is missing', () async {
    final result = await runSetupHooks();

    expect(result.exitCode, 0);
    expect(result.stdout, contains('analyzer.yaml'));
    expect(settingsFile().existsSync(), isFalse);
  });

  test('writes PostToolUse and Stop hooks when analyzer.yaml exists', () async {
    File(
      p.join(fixtureDir.path, 'analyzer.yaml'),
    ).writeAsStringSync('rules: {}\n');

    final result = await runSetupHooks();
    expect(result.exitCode, 0);

    final settings =
        jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
    final hooks = settings['hooks'] as Map<String, dynamic>;
    final postToolUse = hooks['PostToolUse'] as List;
    final stop = hooks['Stop'] as List;

    expect(jsonEncode(postToolUse), contains('dart_sentinel hook-edit'));
    expect(jsonEncode(stop), contains('dart_sentinel hook-stop'));
  });

  test(
    'merges into an existing settings.json without dropping other keys',
    () async {
      File(
        p.join(fixtureDir.path, 'analyzer.yaml'),
      ).writeAsStringSync('rules: {}\n');
      Directory(p.join(fixtureDir.path, '.claude')).createSync();
      settingsFile().writeAsStringSync(
        jsonEncode({
          'permissions': {'allow': []},
        }),
      );

      await runSetupHooks();

      final settings =
          jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
      expect(settings['permissions'], isNotNull);
      expect(settings['hooks'], isNotNull);
    },
  );

  test(
    'fails gracefully and does not overwrite malformed settings.json',
    () async {
      File(
        p.join(fixtureDir.path, 'analyzer.yaml'),
      ).writeAsStringSync('rules: {}\n');
      Directory(p.join(fixtureDir.path, '.claude')).createSync();
      const malformed = '[1, 2, 3]';
      settingsFile().writeAsStringSync(malformed);

      final result = await runSetupHooks();

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('settings.json'),
      );
      expect(settingsFile().readAsStringSync(), equals(malformed));
    },
  );

  test(
    'fails gracefully and does not overwrite settings.json with invalid JSON syntax',
    () async {
      File(
        p.join(fixtureDir.path, 'analyzer.yaml'),
      ).writeAsStringSync('rules: {}\n');
      Directory(p.join(fixtureDir.path, '.claude')).createSync();
      const invalidJson = '{invalid json';
      settingsFile().writeAsStringSync(invalidJson);

      final result = await runSetupHooks();

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('settings.json'),
      );
      expect(settingsFile().readAsStringSync(), equals(invalidJson));
    },
  );

  test('running twice does not duplicate hook entries', () async {
    File(
      p.join(fixtureDir.path, 'analyzer.yaml'),
    ).writeAsStringSync('rules: {}\n');

    await runSetupHooks();
    await runSetupHooks();

    final settings =
        jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
    final postToolUse = (settings['hooks'] as Map)['PostToolUse'] as List;

    expect(postToolUse.length, 1);
  });
}
