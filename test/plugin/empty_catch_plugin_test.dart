import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/empty_catch_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(EmptyCatchPluginRuleTest);
}

@reflectiveTest
class EmptyCatchPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = EmptyCatchPluginRule();
    super.setUp();
  }

  Future<void> test_emptyCatch_reports() async {
    await assertDiagnostics(
      r'''
void f() {
  try {
    print('a');
  } catch (e) {
  }
}
''',
      [lint(39, 15)],
    );
  }

  Future<void> test_emptyCatch_withComment_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  try {
    print('a');
  } catch (e) {
    // intentionally ignored
  }
}
''');
  }

  Future<void> test_emptyCatch_withBody_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  try {
    print('a');
  } catch (e) {
    rethrow;
  }
}
''');
  }

  Future<void> test_printOnly_reports() async {
    await assertDiagnostics(
      r'''
void f() {
  try {
    doSomething();
  } catch (e) {
    print(e);
  }
}
void doSomething() {}
''',
      [lint(42, 29)],
    );
  }
}
