import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects lazy null coalescing patterns like `x ?? ""`, `x ?? 0`, `x ?? []`,
/// `x ?? false` where the null case is silently swallowed with an empty default
/// instead of being properly handled.
class LazyNullCheckRule extends AnalyzerRule {
  @override
  String get name => 'lazy-null-check';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.lazyNullCheck;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor = _LazyNullCheckVisitor(relativePath, entry.value, config);
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _LazyNullCheckVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final LazyNullCheckConfig config;
  final List<Issue> issues = [];

  _LazyNullCheckVisitor(this.filePath, this.unit, this.config);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '??') {
      final rhs = node.rightOperand;
      final match = _matchLazyDefault(rhs);
      if (match != null) {
        final line = unit.lineInfo.getLocation(node.offset).lineNumber;
        issues.add(
          Issue(
            rule: 'lazy-null-check',
            message:
                'Lazy null check: `?? $match` silently swallows null — '
                'consider handling the null case explicitly.',
            file: filePath,
            line: line,
            severity: Severity.warning,
          ),
        );
      }
    }
    super.visitBinaryExpression(node);
  }

  /// Returns a description of the default value if it matches a lazy pattern,
  /// or null if the expression is not considered lazy.
  String? _matchLazyDefault(Expression expr) {
    // "" or ''
    if (config.flagEmptyString && expr is SimpleStringLiteral) {
      if (expr.value.isEmpty) return '""';
    }

    // 0 or 0.0
    if (config.flagZero && expr is IntegerLiteral && expr.value == 0) {
      return '0';
    }
    if (config.flagZero && expr is DoubleLiteral && expr.value == 0.0) {
      return '0.0';
    }

    // false
    if (config.flagFalse && expr is BooleanLiteral && !expr.value) {
      return 'false';
    }

    // [] (empty list literal)
    if (config.flagEmptyCollection && expr is ListLiteral) {
      if (expr.elements.isEmpty) return '[]';
    }

    // {} (empty map/set literal)
    if (config.flagEmptyCollection && expr is SetOrMapLiteral) {
      if (expr.elements.isEmpty) return '{}';
    }

    return null;
  }
}
