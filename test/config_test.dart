import 'dart:io';

import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/rule_registry.dart';
import 'helpers/fixture_project.dart';

AnalyzerConfig _load(String yaml) {
  final dir = Directory.systemTemp.createTempSync('sentinel_cfg_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, 'analyzer.yaml')).writeAsStringSync(yaml);
  return AnalyzerConfig.load(dir.path);
}

void main() {
  final ruleNames = allSentinelRules().map((rule) => rule.name).toList();

  group('rule severities', () {
    test('off disables a rule', () {
      final config = _load('rules:\n  dead-files: off\n  complexity: error\n');
      expect(config.disabledRules, {'dead-files'});
      expect(config.ruleSeverities['complexity'], Severity.error);
    });

    test('invalid severity is a fatal problem naming the rule', () {
      final config = _load('rules:\n  complexity: loud\n');
      expect(config.problems.single, contains("rules.complexity"));
      expect(config.problems.single, contains("'loud'"));
      expect(config.ruleSeverities, isEmpty);
    });

    test('unknown rule suggests the closest name', () {
      final config = _load('rules:\n  dead-file: warning\n');
      expect(
        config.validate(ruleNames).single,
        contains("did you mean 'dead-files'"),
      );
    });

    test('unknown top-level key suggests the closest key', () {
      final config = _load('entrypoint:\n  - lib/main.dart\n');
      expect(config.validate(ruleNames).single, contains("'entrypoints'"));
    });

    test('runner skips disabled rules', () async {
      final context = await buildFixture({
        'analyzer.yaml': 'rules:\n  empty-catch: off\n',
        'lib/a.dart': 'void f() { try { g(); } catch (e) {} }\nvoid g() {}\n',
      });
      final issues = RuleRunner(
        rules: allSentinelRules(),
        config: context.config,
      ).runAll(context);
      expect(issues.where((i) => i.rule == 'empty-catch'), isEmpty);
    });
  });

  test('every shipped template is valid', () {
    final templates = Directory('example/templates')
        .listSync()
        .whereType<File>()
        .where(
          (f) => f.path.endsWith('.yaml') && !f.path.contains('github-actions'),
        );
    expect(templates, isNotEmpty);
    for (final template in templates) {
      final config = _load(template.readAsStringSync());
      expect(config.problems, isEmpty, reason: template.path);
      expect(config.validate(ruleNames), isEmpty, reason: template.path);
    }
  });

  group('layer coverage', () {
    test('flags empty layers and folders outside every layer', () {
      final config = _load('''
architecture:
  layers:
    ui:
      paths: ["lib/ui/**"]
      can_depend_on: []
    data:
      paths: ["lib/data/**"]
      can_depend_on: []
''');
      final warnings = layerCoverageWarnings(config, [
        'lib/ui/a.dart',
        'lib/features/x/b.dart',
      ]);
      expect(warnings, contains(contains("layer 'data' matches no file")));
      expect(warnings, contains(contains('lib/features/ is outside')));
    });

    test('recursive glob in the middle of a path matches', () {
      final config = _load('''
architecture:
  layers:
    models:
      paths: ["lib/core/*/model/**"]
      can_depend_on: []
''');
      expect(
        layerCoverageWarnings(config, ['lib/core/auth/model/user.dart']),
        isEmpty,
      );
    });
  });

  test('recommendTemplate reads the folder structure', () {
    expect(
      recommendTemplate(['ui', 'data', 'domain', 'routing']),
      'flutter_official',
    );
    expect(
      recommendTemplate(['domain', 'data', 'presentation']),
      'clean_architecture',
    );
    expect(recommendTemplate(['widgets']), 'starter');
  });
}
