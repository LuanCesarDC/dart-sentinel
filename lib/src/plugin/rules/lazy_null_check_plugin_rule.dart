import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects lazy null coalescing like `x ?? ""`, `x ?? 0`, etc.
class LazyNullCheckPluginRule extends AnalysisRule {
  LazyNullCheckPluginRule()
    : super(
        name: 'lazy_null_check',
        description:
            'Detects lazy null coalescing with empty defaults '
            'like ?? "", ?? 0, ?? [], ?? false.',
      );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.lazyNullCheck;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addBinaryExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final LazyNullCheckPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme != '??') return;

    final rhs = node.rightOperand;
    if (_isLazyDefault(rhs)) {
      rule.reportAtNode(node);
    }
  }

  bool _isLazyDefault(Expression expr) {
    // "" or ''
    if (expr is SimpleStringLiteral && expr.value.isEmpty) return true;

    // 0 or 0.0
    if (expr is IntegerLiteral && expr.value == 0) return true;
    if (expr is DoubleLiteral && expr.value == 0.0) return true;

    // false
    if (expr is BooleanLiteral && !expr.value) return true;

    // [] or {}
    if (expr is ListLiteral && expr.elements.isEmpty) return true;
    if (expr is SetOrMapLiteral && expr.elements.isEmpty) return true;

    return false;
  }
}
