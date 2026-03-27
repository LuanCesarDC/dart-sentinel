import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects comparisons where both sides are identical (e.g. `x == x`, `a > a`).
class AvoidSelfCompareRule extends AnalyzerRule {
  @override
  String get name => 'avoid-self-compare';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor = _SelfCompareVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _SelfCompareVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  static const _comparisonOps = {'==', '!=', '>', '<', '>=', '<='};

  _SelfCompareVisitor(this.filePath, this.unit);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type.lexeme;
    if (_comparisonOps.contains(op)) {
      if (node.leftOperand.toSource() == node.rightOperand.toSource()) {
        final line = unit.lineInfo.getLocation(node.offset).lineNumber;
        issues.add(Issue(
          rule: 'avoid-self-compare',
          message:
              'both sides of "$op" are identical: '
              '${node.leftOperand.toSource()}',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ));
      }
    }

    super.visitBinaryExpression(node);
  }
}
