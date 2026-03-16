import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects empty catch blocks and catch-and-print-only.
class EmptyCatchPluginRule extends MultiAnalysisRule {
  EmptyCatchPluginRule()
    : super(
        name: 'empty_catch',
        description:
            'Detects empty catch blocks and catch-and-print-only patterns.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => [
    SentinelCodes.emptyCatch,
    SentinelCodes.emptyCatchPrintOnly,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCatchClause(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final EmptyCatchPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitCatchClause(CatchClause node) {
    final statements = node.body.statements;

    if (statements.isEmpty) {
      if (_hasComment(node.body)) return;
      rule.reportAtNode(node, diagnosticCode: SentinelCodes.emptyCatch);
      return;
    }

    if (_isPrintOnly(statements)) {
      rule.reportAtNode(
        node,
        diagnosticCode: SentinelCodes.emptyCatchPrintOnly,
      );
    }
  }

  bool _isPrintOnly(List<Statement> statements) {
    if (statements.length != 1) return false;
    final stmt = statements.first;
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;
    if (expr is! MethodInvocation) return false;
    final name = expr.methodName.name;
    return name == 'print' || name == 'debugPrint';
  }

  bool _hasComment(Block body) {
    var token = body.leftBracket.next;
    final end = body.rightBracket;
    while (token != null && token != end) {
      if (token.precedingComments != null) return true;
      token = token.next;
    }
    if (end.precedingComments != null) return true;
    return false;
  }
}
