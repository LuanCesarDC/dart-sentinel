import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

/// A function with [branches] sequential ifs has cyclomatic complexity
/// branches + 1.
String _functionWithComplexity(int complexity) {
  final ifs = List.generate(complexity - 1, (i) => '  if (n == $i) return $i;');
  return 'int f(int n) {\n${ifs.join('\n')}\n  return -1;\n}\n';
}

void main() {
  test(
    'complexity equal to the limit is allowed, one above is reported',
    () async {
      final atLimit = await runRule(ComplexityRule(), {
        'lib/a.dart': _functionWithComplexity(10),
      });
      expect(atLimit.where((i) => i.message.contains('cyclomatic')), isEmpty);

      final overLimit = await runRule(ComplexityRule(), {
        'lib/a.dart': _functionWithComplexity(11),
      });
      expect(
        overLimit.single.message,
        allOf(contains('11'), contains('limit: 10')),
      );
    },
  );

  test('class-metrics allows exactly the method limit', () async {
    String classWith(int methods) =>
        'class A {\n${List.generate(methods, (i) => '  void m$i() {}').join('\n')}\n}\n';
    expect(
      await runRule(ClassMetricsRule(), {'lib/a.dart': classWith(15)}),
      isEmpty,
    );
    expect(
      await runRule(ClassMetricsRule(), {'lib/a.dart': classWith(16)}),
      isNotEmpty,
    );
  });
}
