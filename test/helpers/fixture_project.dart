import 'dart:io';

import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a throwaway project from [files] (relative path → content) and
/// returns its analysis context. `pubspec.yaml` is added when missing.
Future<ProjectContext> buildFixture(
  Map<String, String> files, {
  void Function(Directory root)? onCreated,
}) async {
  final root = await Directory.systemTemp.createTemp('sentinel_fixture_');
  addTearDown(() => root.deleteSync(recursive: true));
  final all = {
    'pubspec.yaml': 'name: fixture\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    ...files,
  };
  for (final entry in all.entries) {
    final file = File(p.join(root.path, entry.key))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  onCreated?.call(root);
  return ProjectContext.build(root.path);
}

/// Runs [rule] over a fixture and returns its issues.
Future<List<Issue>> runRule(
  AnalyzerRule rule,
  Map<String, String> files,
) async => rule.run(await buildFixture(files));
