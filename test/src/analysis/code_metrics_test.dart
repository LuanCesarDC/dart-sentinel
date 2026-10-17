import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_project.dart';

void main() {
  test('collects LOC, methods and cyclomatic complexity per file', () async {
    final context = await buildFixture({
      'lib/a.dart': '''
// comment
int a(int x) {
  if (x > 0 && x < 10) { return 1; }
  return x == 0 ? 0 : 2;
}

int b() => 1;
''',
    });
    final metrics = CodeMetrics(context).collect().single;
    expect(metrics.file, 'lib/a.dart');
    expect(metrics.methods, 2);
    expect(metrics.maxComplexity, 4); // 1 + if + && + ternary
    expect(metrics.loc, 5);
    expect(metrics.maintainability, inInclusiveRange(0, 100));
  });

  test('a bigger, branchier file is less maintainable', () async {
    final big = StringBuffer();
    for (var i = 0; i < 60; i++) {
      big.writeln(
        'int f$i(int x) { if (x > $i && x < ${i + 9}) { return x; } return $i; }',
      );
    }
    final context = await buildFixture({
      'lib/small.dart': 'int f() => 1;\n',
      'lib/big.dart': big.toString(),
    });
    final byFile = {
      for (final m in CodeMetrics(context).collect()) m.file: m.maintainability,
    };
    expect(byFile['lib/big.dart']!, lessThan(byFile['lib/small.dart']!));
  });

  test('debt estimate weighs severities', () {
    Issue at(Severity s) =>
        Issue(rule: 'r', message: 'm', file: 'f', severity: s);
    expect(
      estimateDebtMinutes([
        at(Severity.error),
        at(Severity.warning),
        at(Severity.info),
      ]),
      50,
    );
  });
}
