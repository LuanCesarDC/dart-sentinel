// `dart_sentinel setup-hooks` — writes/merges the PostToolUse and Stop hook
// entries into .claude/settings.json so hook-edit/hook-stop run automatically
// in Claude Code, without the user hand-editing JSON.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.');
  final results = parser.parse(args);
  final projectRoot = results['project'] as String? ?? Directory.current.path;

  final analyzerYaml = File(p.join(projectRoot, 'analyzer.yaml'));
  if (!analyzerYaml.existsSync()) {
    print(
      'No analyzer.yaml found at $projectRoot — set up your architecture '
      'config first, then run `dart_sentinel setup-hooks` again.',
    );
    return;
  }

  final settingsFile = File(p.join(projectRoot, '.claude', 'settings.json'));
  final settings = _readSettings(settingsFile);

  final hooks = (settings['hooks'] as Map<String, dynamic>?) ?? {};
  hooks['PostToolUse'] = _mergeHookEntry(
    hooks['PostToolUse'] as List?,
    command: 'dart_sentinel hook-edit',
    matcher: 'Edit|Write',
  );
  hooks['Stop'] = _mergeHookEntry(
    hooks['Stop'] as List?,
    command: 'dart_sentinel hook-stop',
    matcher: null,
  );
  settings['hooks'] = hooks;

  settingsFile.parent.createSync(recursive: true);
  settingsFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(settings),
  );
  print('Dart Sentinel hooks written to ${settingsFile.path}');
}

Map<String, dynamic> _readSettings(File file) {
  if (!file.existsSync()) return {};
  final content = file.readAsStringSync();
  if (content.trim().isEmpty) return {};

  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException catch (e) {
    stderr.writeln(
      'Could not parse ${file.path} — it does not contain valid JSON '
      '($e). Fix or remove the file, then run `dart_sentinel setup-hooks` '
      'again.',
    );
    exit(1);
  }

  if (decoded is! Map<String, dynamic>) {
    stderr.writeln(
      'Could not use ${file.path} — its top-level JSON value must be an '
      'object (found ${decoded.runtimeType}). Fix or remove the file, '
      'then run `dart_sentinel setup-hooks` again.',
    );
    exit(1);
  }

  return decoded;
}

List<dynamic> _mergeHookEntry(
  List<dynamic>? existing, {
  required String command,
  required String? matcher,
}) {
  final entries = existing ?? [];
  final alreadyPresent = entries.any(
    (entry) => jsonEncode(entry).contains(command),
  );
  if (alreadyPresent) return entries;

  final newEntry = <String, dynamic>{
    if (matcher != null) 'matcher': matcher,
    'hooks': [
      {'type': 'command', 'command': command},
    ],
  };
  return [...entries, newEntry];
}
