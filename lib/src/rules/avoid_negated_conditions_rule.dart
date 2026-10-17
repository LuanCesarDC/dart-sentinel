import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Flags `if (!x) a else b` and `!x ? a : b` — swap the branches and drop the
/// negation. `else if` chains are left alone.
class AvoidNegatedConditionsRule extends AnalyzerRule {
  @override
  String get name => 'avoid-negated-conditions';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final visitor = _NegatedVisitor(
        context.relativePath(entry.key),
        entry.value,
      );
      entry.value.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _NegatedVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _NegatedVisitor(this.filePath, this.unit);

  @override
  void visitIfStatement(IfStatement node) {
    final isElseIf =
        node.parent is IfStatement &&
        (node.parent as IfStatement).elseStatement == node;
    if (node.elseStatement != null &&
        !isElseIf &&
        _isNegated(node.expression)) {
      _report(node.offset);
    }
    super.visitIfStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (_isNegated(node.condition)) _report(node.offset);
    super.visitConditionalExpression(node);
  }

  bool _isNegated(Expression condition) {
    if (condition is PrefixExpression) {
      return condition.operator.lexeme == '!';
    }
    return condition is BinaryExpression && condition.operator.lexeme == '!=';
  }

  void _report(int offset) {
    issues.add(
      Issue(
        rule: 'avoid-negated-conditions',
        message:
            'negated condition with an else branch — invert it and swap '
            'the branches',
        file: filePath,
        line: unit.lineInfo.getLocation(offset).lineNumber,
        severity: Severity.info,
      ),
    );
  }
}
