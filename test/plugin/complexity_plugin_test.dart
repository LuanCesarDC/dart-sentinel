import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/complexity_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(ComplexityPluginRuleTest);
}

@reflectiveTest
class ComplexityPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ComplexityPluginRule();
    super.setUp();
  }

  Future<void> test_simpleFunction_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  print('hello');
}
''');
  }

  Future<void> test_tooManyParams_reports() async {
    await assertDiagnostics(
      r'''
void f(int a, int b, int c, int d, int e, int f) {}
''',
      [lint(0, 51)],
    );
  }

  Future<void> test_fewParams_noReport() async {
    await assertNoDiagnostics(r'''
void f(int a, int b) {}
''');
  }
}
