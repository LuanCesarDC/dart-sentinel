import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../../../bin/rule_registry.dart';
import '../../helpers/fixture_project.dart';

const _catchBody =
    'void f() {\n  try {\n    g();\n  } catch (e) {}\n}\nvoid g() {}\n';

Future<List<Issue>> _run(Map<String, String> files) async {
  final context = await buildFixture(files);
  return RuleRunner(
    rules: allSentinelRules(),
    config: context.config,
  ).runAll(context).where((i) => i.rule == 'empty-catch').toList();
}

void main() {
  test('baseline: the empty catch is reported', () async {
    expect(await _run({'lib/a.dart': _catchBody}), isNotEmpty);
  });

  test('sentinel-ignore on the line above silences it', () async {
    final issues = await _run({
      'lib/a.dart': _catchBody.replaceFirst(
        '  } catch',
        '  // sentinel-ignore: empty-catch — g() is best effort\n  } catch',
      ),
    });
    expect(issues, isEmpty);
  });

  test('sentinel-ignore-file silences the rule for the whole file', () async {
    final issues = await _run({
      'lib/a.dart':
          '// sentinel-ignore-file: empty-catch, dead-todos\n$_catchBody',
    });
    expect(issues, isEmpty);
  });

  test('ignoring another rule does not silence it', () async {
    final issues = await _run({
      'lib/a.dart': '// sentinel-ignore-file: complexity\n$_catchBody',
    });
    expect(issues, isNotEmpty);
  });

  group('profiles', () {
    test('normal (default) demotes noisy rules to info', () async {
      final context = await buildFixture({'lib/a.dart': 'void f() {}\n'});
      expect(context.config.ruleSeverities['untested-files'], Severity.info);
    });

    test('strict leaves defaults alone', () async {
      final context = await buildFixture({
        'analyzer.yaml': 'profile: strict\n',
        'lib/a.dart': 'void f() {}\n',
      });
      expect(context.config.ruleSeverities, isNot(contains('untested-files')));
    });

    test('quiet disables them, explicit rules still win', () async {
      final context = await buildFixture({
        'analyzer.yaml': 'profile: quiet\nrules:\n  generic-naming: error\n',
        'lib/a.dart': 'void f() {}\n',
      });
      expect(context.config.disabledRules, contains('untested-files'));
      expect(context.config.disabledRules, isNot(contains('generic-naming')));
      expect(context.config.ruleSeverities['generic-naming'], Severity.error);
    });

    test('unknown profile is a fatal problem', () async {
      final context = await buildFixture({
        'analyzer.yaml': 'profile: loud\n',
        'lib/a.dart': 'void f() {}\n',
      });
      expect(context.config.problems.single, contains("'loud'"));
    });
  });
}
