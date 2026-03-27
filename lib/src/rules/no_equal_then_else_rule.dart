import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects if/else statements where both branches have identical bodies.
class NoEqualThenElseRule extends AnalyzerRule {
  @override
  String get name => 'no-equal-then-else';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor = _EqualBranchVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _EqualBranchVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _EqualBranchVisitor(this.filePath, this.unit);

  @override
  void visitIfStatement(IfStatement node) {
    final thenBranch = node.thenStatement;
    final elseBranch = node.elseStatement;

    if (elseBranch != null && elseBranch is! IfStatement) {
      if (thenBranch.toSource() == elseBranch.toSource()) {
        final line = unit.lineInfo.getLocation(node.offset).lineNumber;
        issues.add(Issue(
          rule: 'no-equal-then-else',
          message: 'if/else branches have identical bodies — condition is redundant',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ));
      }
    }

    super.visitIfStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (node.thenExpression.toSource() == node.elseExpression.toSource()) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      issues.add(Issue(
        rule: 'no-equal-then-else',
        message:
            'ternary has identical then/else — condition is redundant',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    super.visitConditionalExpression(node);
  }
}
