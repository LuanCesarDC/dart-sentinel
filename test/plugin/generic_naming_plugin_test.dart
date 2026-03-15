import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/generic_naming_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(GenericNamingPluginRuleTest);
}

@reflectiveTest
class GenericNamingPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = GenericNamingPluginRule();
    super.setUp();
  }

  Future<void> test_genericVariable_reports() async {
    await assertDiagnostics(
      r'''
void f() {
  var data = 42;
  print(data);
}
''',
      [lint(17, 4)],
    );
  }

  Future<void> test_descriptiveVariable_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  var userCount = 42;
  print(userCount);
}
''');
  }

  Future<void> test_genericInLoop_noReport() async {
    await assertNoDiagnostics(r'''
void f() {
  for (var item in [1, 2, 3]) {
    print(item);
  }
}
''');
  }

  Future<void> test_genericFunction_reports() async {
    await assertDiagnostics(
      r'''
void process() {}
''',
      [lint(5, 7)],
    );
  }

  Future<void> test_descriptiveFunction_noReport() async {
    await assertNoDiagnostics(r'''
void processPayment() {}
''');
  }
}
