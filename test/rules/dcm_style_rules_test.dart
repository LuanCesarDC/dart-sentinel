import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

Future<List<Issue>> _run(AnalyzerRule rule, String source, {String? path}) =>
    runRule(rule, {path ?? 'lib/sample.dart': source});

void main() {
  group('avoid-nested-conditional-expressions', () {
    final rule = AvoidNestedConditionalExpressionsRule();

    test('reports a chain once, at the outermost ternary', () async {
      final issues = await _run(
        rule,
        'String f(int a) => a > 1 ? "x" : a > 0 ? "y" : a < 0 ? "z" : "w";\n',
      );
      expect(issues, hasLength(1));
    });

    test('allows a single ternary and a ternary in the condition', () async {
      final issues = await _run(
        rule,
        'int f(bool a, bool b) => (a ? b : false) ? 1 : 2;\n'
        'int g(bool a) => a ? 1 : 2;\n',
      );
      expect(issues, isEmpty);
    });
  });

  group('avoid-negated-conditions', () {
    final rule = AvoidNegatedConditionsRule();

    test('flags if/else and ternary with a negated condition', () async {
      final issues = await _run(
        rule,
        'int f(bool a, int b) {\n'
        '  if (!a) { return 1; } else { return 2; }\n'
        '}\n'
        'int g(int a, int b) => a != b ? 1 : 2;\n',
      );
      expect(issues, hasLength(2));
    });

    test('ignores negation without else and else-if chains', () async {
      final issues = await _run(
        rule,
        'int f(bool a, bool b) {\n'
        '  if (!a) { return 1; }\n'
        '  if (a) { return 2; } else if (!b) { return 3; } else { return 4; }\n'
        '}\n',
      );
      expect(issues, isEmpty);
    });
  });

  group('avoid-dynamic', () {
    final rule = AvoidDynamicRule();

    test('flags a dynamic annotation but not a type argument', () async {
      final issues = await _run(
        rule,
        'dynamic f(dynamic a, Map<String, dynamic> json) => a;\n',
      );
      expect(issues, hasLength(2));
    });
  });

  group('prefer-match-file-name', () {
    final rule = PreferMatchFileNameRule();

    test('flags a single public type with a different file name', () async {
      final issues = await _run(
        rule,
        'class HomePage {}\n',
        path: 'lib/page.dart',
      );
      expect(issues.single.message, contains('home_page.dart'));
    });

    test(
      'accepts a match, private extras, several types and generated',
      () async {
        expect(
          await _run(
            rule,
            'class HomePage {}\nclass _S {}\n',
            path: 'lib/home_page.dart',
          ),
          isEmpty,
        );
        expect(
          await _run(rule, 'class A {}\nclass B {}\n', path: 'lib/x.dart'),
          isEmpty,
        );
        expect(await _run(rule, 'class A {}\n', path: 'lib/x.g.dart'), isEmpty);
      },
    );
  });

  group('avoid-redundant-async', () {
    final rule = AvoidRedundantAsyncRule();

    test('flags async without await', () async {
      final issues = await _run(rule, 'Future<int> f() async { return 1; }\n');
      expect(issues, hasLength(1));
    });

    test(
      'accepts await, await for, generators, overrides and closure-only awaits',
      () async {
        final issues = await _run(
          rule,
          'Future<void> a(Future<void> x) async { await x; }\n'
          'Future<void> b(Stream<int> s) async { await for (final _ in s) {} }\n'
          'Stream<int> c() async* { yield 1; }\n'
          'class K { @override Future<int> m() async => 1; }\n'
          'Future<void> main() async {}\n',
        );
        expect(issues, isEmpty);
      },
    );

    test('an await inside a nested closure does not count', () async {
      final issues = await _run(
        rule,
        'Future<void> f() async { final g = () async { await null; }; g(); }\n',
      );
      expect(issues, hasLength(1));
    });
  });

  group('avoid-unused-parameters', () {
    final rule = AvoidUnusedParametersRule();

    test('flags an unused parameter', () async {
      final issues = await _run(rule, 'int f(int a, int b) => a;\n');
      expect(issues.single.message, contains('"b"'));
    });

    test(
      'skips used, underscore, override, abstract, main and closures',
      () async {
        final issues = await _run(
          rule,
          'int a(int x) => x;\n'
          'int b(int _x) => 1;\n'
          'void main(List<String> args) {}\n'
          'abstract class K { int m(int x); @override String toString() => ""; }\n'
          'class L extends K { @override int m(int x) => 1; }\n'
          'void c() { final f = (int x) => 1; f(0); }\n'
          'String d(String s) => "\$s!";\n',
        );
        expect(issues, isEmpty);
      },
    );
  });
}
