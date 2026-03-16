import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects passthrough functions that only delegate.
class PassthroughFunctionPluginRule extends AnalysisRule {
  PassthroughFunctionPluginRule()
    : super(
        name: 'passthrough_function',
        description:
            'Detects functions that only delegate to another with the same arguments.',
      );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.passthroughFunction;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addMethodDeclaration(this, visitor);
    registry.addFunctionDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final PassthroughFunctionPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final hasOverride = node.metadata.any((a) => a.name.name == 'override');
    if (hasOverride) return;
    _check(node.name.lexeme, node.parameters, node.body, node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(
      node.name.lexeme,
      node.functionExpression.parameters,
      node.functionExpression.body,
      node,
    );
  }

  void _check(
    String funcName,
    FormalParameterList? params,
    FunctionBody body,
    AstNode reportNode,
  ) {
    if (params == null) return;
    final paramNames = params.parameters
        .map((p) => p.name?.lexeme)
        .whereType<String>()
        .toList();
    if (paramNames.isEmpty) return;

    final singleExpr = _extractSingleExpression(body);
    if (singleExpr == null) return;

    final call = _extractCallInfo(singleExpr);
    if (call == null || call.calleeName == funcName) return;

    if (_isPassthrough(call.argList, paramNames)) {
      rule.reportAtNode(reportNode, arguments: [funcName, call.calleeName]);
    }
  }

  Expression? _extractSingleExpression(FunctionBody body) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      final stmts = body.block.statements;
      if (stmts.length == 1 && stmts.first is ReturnStatement) {
        return (stmts.first as ReturnStatement).expression;
      }
    }
    return null;
  }

  _CallInfo? _extractCallInfo(Expression expr) {
    if (expr is MethodInvocation) {
      return _CallInfo(expr.methodName.name, expr.argumentList);
    }
    if (expr is FunctionExpressionInvocation) {
      final fn = expr.function;
      if (fn is SimpleIdentifier) {
        return _CallInfo(fn.name, expr.argumentList);
      }
    }
    return null;
  }

  bool _isPassthrough(ArgumentList argList, List<String> paramNames) {
    final args = argList.arguments;
    if (args.length != paramNames.length) return false;

    for (var i = 0; i < args.length; i++) {
      Expression argExpr = args[i];
      if (argExpr is NamedExpression) {
        argExpr = argExpr.expression;
      }
      if (argExpr is! SimpleIdentifier) return false;
      if (argExpr.name != paramNames[i]) return false;
    }
    return true;
  }
}

class _CallInfo {
  final String calleeName;
  final ArgumentList argList;
  _CallInfo(this.calleeName, this.argList);
}
