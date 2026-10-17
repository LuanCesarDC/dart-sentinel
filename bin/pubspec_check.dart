// Detects dart_sentinel declared as a project dependency. It is a global
// tool: depending on it pulls its analyzer constraints into the project.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Section of pubspec.yaml that lists dart_sentinel, or null when it is
/// correctly absent.
String? sentinelDependencySection(String projectRoot) {
  final file = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return null;
  for (final section in ['dependencies', 'dev_dependencies']) {
    final deps = yaml[section];
    if (deps is YamlMap && deps.containsKey('dart_sentinel')) return section;
  }
  return null;
}

String dependencyConflictAdvice(String section) =>
    'dart_sentinel is listed in $section of pubspec.yaml. It is a global '
    'tool — remove it from pubspec.yaml and install it with '
    '`dart pub global activate dart_sentinel`.';
