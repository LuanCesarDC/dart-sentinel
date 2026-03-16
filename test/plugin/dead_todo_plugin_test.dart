import 'package:analyzer/src/diagnostic/diagnostic.dart' // ignore: implementation_imports
    as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:dart_sentinel/src/plugin/rules/dead_todo_plugin_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveTests(DeadTodoPluginRuleTest);
}

@reflectiveTest
class DeadTodoPluginRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DeadTodoPluginRule();
    super.setUp();
  }

  Future<void> test_deadTodo_noContext_reports() async {
    // "TODO fix this" has only 2 meaningful words → dead todo
    // The analyzer also emits a built-in `todo` diagnostic
    await assertDiagnostics(
      r'''
// TODO fix this
void f() {}
''',
      [lint(0, 16), error(diag.todo, 3, 13)],
    );
  }

  Future<void> test_todoWithIssueRef_noReport() async {
    // Has #123 → not a dead todo; only the built-in TODO diagnostic fires
    await assertDiagnostics(
      r'''
// TODO(#123): fix this bug
void f() {}
''',
      [error(diag.todo, 3, 24)],
    );
  }

  Future<void> test_todoWithEnoughContext_noReport() async {
    // Has enough words → not a dead todo; only the built-in TODO fires
    await assertDiagnostics(
      r'''
// TODO: refactor the authentication flow to use the new token system
void f() {}
''',
      [error(diag.todo, 3, 66)],
    );
  }

  Future<void> test_normalComment_noReport() async {
    await assertNoDiagnostics(r'''
// This is a normal comment
void f() {}
''');
  }
}
