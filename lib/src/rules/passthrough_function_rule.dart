import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects functions/methods whose body only delegates to another function
/// with the same arguments, adding no logic.
class PassthroughFunctionRule extends AnalyzerRule {
  @override
  String get name => 'passthrough-function';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor =
          _PassthroughVisitor(relativePath, entry.value);
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _PassthroughVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _PassthroughVisitor(this.filePath, this.unit);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Skip overrides (they may intentionally delegate to super)
    final hasOverride = node.metadata.any(
      (a) => a.name.name == 'override',
    );
    if (hasOverride) {
      super.visitMethodDeclaration(node);
      return;
    }

    _checkPassthrough(node.name.lexeme, node.parameters,
        node.body, node.offset);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _checkPassthrough(node.name.lexeme,
        node.functionExpression.parameters,
        node.functionExpression.body, node.offset);
    super.visitFunctionDeclaration(node);
  }

  void _checkPassthrough(
    String funcName,
    FormalParameterList? params,
    FunctionBody body,
    int offset,
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
      final line = unit.lineInfo.getLocation(offset).lineNumber;
      issues.add(Issue(
        rule: 'passthrough-function',
        message: '\'$funcName\' only delegates to \'${call.calleeName}\' '
            'with the same arguments — consider calling \'${call.calleeName}\' directly.',
        file: filePath,
        line: line,
        severity: Severity.info,
      ));
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

  ({ArgumentList argList, String calleeName})? _extractCallInfo(
      Expression expr) {
    if (expr is MethodInvocation) {
      return (argList: expr.argumentList, calleeName: expr.methodName.name);
    }
    if (expr is FunctionExpressionInvocation) {
      final fn = expr.function;
      if (fn is SimpleIdentifier) {
        return (argList: expr.argumentList, calleeName: fn.name);
      }
    }
    return null;
  }

  bool _isPassthrough(ArgumentList argList, List<String> paramNames) {
    final argNames = argList.arguments.map((a) {
      if (a is NamedExpression) {
        final expr = a.expression;
        return expr is SimpleIdentifier ? expr.name : null;
      }
      return a is SimpleIdentifier ? a.name : null;
    }).toList();

    if (argNames.length != paramNames.length) return false;

    final paramSet = paramNames.toSet();
    final argSet = argNames.whereType<String>().toSet();
    return argSet.length == paramNames.length &&
        argSet.difference(paramSet).isEmpty;
  }
}
