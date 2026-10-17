import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Flags a ternary nested inside another ternary (`a ? b : c ? d : e`).
/// Reported once per chain, at its outermost expression.
class AvoidNestedConditionalExpressionsRule extends AnalyzerRule {
  @override
  String get name => 'avoid-nested-conditional-expressions';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final visitor = _NestedTernaryVisitor(
        context.relativePath(entry.key),
        entry.value,
      );
      entry.value.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _NestedTernaryVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _NestedTernaryVisitor(this.filePath, this.unit);

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (_hasNestedBranch(node) && !_isBranchOfTernary(node)) {
      issues.add(
        Issue(
          rule: 'avoid-nested-conditional-expressions',
          message:
              'nested ternary — extract it to a variable, a method or an '
              'if/switch',
          file: filePath,
          line: unit.lineInfo.getLocation(node.offset).lineNumber,
          severity: Severity.warning,
        ),
      );
    }
    super.visitConditionalExpression(node);
  }

  bool _hasNestedBranch(ConditionalExpression node) =>
      _unwrap(node.thenExpression) is ConditionalExpression ||
      _unwrap(node.elseExpression) is ConditionalExpression;

  bool _isBranchOfTernary(ConditionalExpression node) {
    AstNode? parent = node.parent;
    while (parent is ParenthesizedExpression) {
      parent = parent.parent;
    }
    return parent is ConditionalExpression && parent.condition != node;
  }

  Expression _unwrap(Expression expression) {
    var current = expression;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    return current;
  }
}
