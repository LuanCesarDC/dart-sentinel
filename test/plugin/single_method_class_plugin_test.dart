import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/single_method_class_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(SingleMethodClassPluginRuleTest);
}

@reflectiveTest
class SingleMethodClassPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SingleMethodClassPluginRule();
    super.setUp();
  }

  Future<void> test_singlePublicMethod_reports() async {
    await assertDiagnostics(
      r'''
class Validator {
  bool validate(String input) => input.isNotEmpty;
}
''',
      [lint(6, 9)],
    );
  }

  Future<void> test_multiplePublicMethods_noReport() async {
    await assertNoDiagnostics(r'''
class Validator {
  bool validate(String input) => input.isNotEmpty;
  String format(String input) => input.length.toString();
}
''');
  }

  Future<void> test_abstractClass_noReport() async {
    await assertNoDiagnostics(r'''
abstract class Validator {
  bool validate(String input);
}
''');
  }

  Future<void> test_extendsOther_noReport() async {
    await assertNoDiagnostics(r'''
class Base {}
class Child extends Base {
  void doWork() {}
}
''');
  }
}
