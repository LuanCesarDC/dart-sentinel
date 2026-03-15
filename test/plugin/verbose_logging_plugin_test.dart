import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/verbose_logging_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(VerboseLoggingPluginRuleTest);
}

@reflectiveTest
class VerboseLoggingPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = VerboseLoggingPluginRule();
    super.setUp();
  }

  Future<void> test_consecutiveLogs_reports() async {
    await assertDiagnostics(
      r'''
void f() {
  print('step 1');
  print('step 2');
  print('step 3');
}
''',
      [lint(13, 16)],
    );
  }

  Future<void> test_fewLogs_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  print('step 1');
  print('step 2');
}
''');
  }

  Future<void> test_logsWithOtherStatements_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  print('start');
  var x = 1;
  print('end');
}
''');
  }
}
