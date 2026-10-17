import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../../../bin/rule_registry.dart';
import '../../helpers/fixture_project.dart';

void main() {
  test('runCategories runs the union of the requested categories', () async {
    final context = await buildFixture({
      'lib/a.dart': 'void f() { try { g(); } catch (e) {} }\nvoid g() {}\n',
    });
    final runner = RuleRunner(
      rules: allSentinelRules(),
      config: context.config,
    );

    final slopOnly = runner.runCategories(context, ['slop']);
    final both = runner.runCategories(context, ['slop', 'lint']);

    expect(slopOnly.any((i) => i.rule == 'empty-catch'), isTrue);
    expect(both.length, greaterThanOrEqualTo(slopOnly.length));
  });

  test('categoryOf maps rules and falls back to other', () {
    expect(categoryOf('dead-files'), 'dead');
    expect(categoryOf('nope'), 'other');
  });
}
