import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/passthrough_function_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(PassthroughFunctionPluginRuleTest);
}

@reflectiveTest
class PassthroughFunctionPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PassthroughFunctionPluginRule();
    super.setUp();
  }

  Future<void> test_passthroughFunction_reports() async {
    await assertDiagnostics(
      r'''
void target(int a, String b) {}
void wrapper(int a, String b) => target(a, b);
''',
      [lint(32, 46)],
    );
  }

  Future<void> test_functionWithLogic_noReport() async {
    await assertNoDiagnostics(r'''
void target(int a) {}
void wrapper(int a) {
  print('calling target');
  target(a);
}
''');
  }

  Future<void> test_differentArgs_noReport() async {
    await assertNoDiagnostics(r'''
void target(int a, int b) {}
void wrapper(int a, int b) => target(b, a);
''');
  }
}
