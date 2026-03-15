import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects setState/context used after await without mounted check.
class AsyncSafetyPluginRule extends AnalysisRule {
  AsyncSafetyPluginRule()
      : super(
          name: 'async_safety',
          description: 'Detects setState or BuildContext usage after await without mounted check.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.asyncSafety;

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
  final AsyncSafetyPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.body is! BlockFunctionBody) return;
    final body = node.body as BlockFunctionBody;
    if (!body.isAsynchronous) return;
    _checkAsyncBody(body.block.statements);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final body = node.functionExpression.body;
    if (body is! BlockFunctionBody || !body.isAsynchronous) return;
    _checkAsyncBody(body.block.statements);
  }

  void _checkAsyncBody(List<Statement> statements) {
    bool seenAwait = false;
    bool mountedCheckAfterAwait = false;

    for (final stmt in statements) {
      if (_containsAwait(stmt)) {
        seenAwait = true;
        mountedCheckAfterAwait = false;
      }

      if (seenAwait && _isMountedCheck(stmt)) {
        mountedCheckAfterAwait = true;
      }

      if (seenAwait && !mountedCheckAfterAwait) {
        _checkForSetState(stmt);
        _checkForContext(stmt);
      }

      if (stmt is IfStatement && _isMountedCheck(stmt)) {
        mountedCheckAfterAwait = true;
      }
    }
  }

  bool _containsAwait(Statement stmt) {
    final finder = _AwaitFinder();
    stmt.accept(finder);
    return finder.found;
  }

  bool _isMountedCheck(Statement stmt) {
    final source = stmt.toSource();
    return source.contains('mounted') || source.contains('context.mounted');
  }

  void _checkForSetState(Statement stmt) {
    final finder = _SetStateFinder();
    stmt.accept(finder);
    for (final node in finder.nodes) {
      rule.reportAtNode(
        node,
        arguments: ['setState() called after await without `mounted` check'],
      );
    }
  }

  void _checkForContext(Statement stmt) {
    final finder = _ContextUsageFinder();
    stmt.accept(finder);
    for (final usage in finder.usages) {
      rule.reportAtNode(
        usage.node,
        arguments: ['${usage.description} used after await without `mounted` check'],
      );
    }
  }
}

class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    found = true;
  }
}

class _SetStateFinder extends RecursiveAstVisitor<void> {
  final List<AstNode> nodes = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState') nodes.add(node);
    super.visitMethodInvocation(node);
  }
}

class _ContextUsage {
  final AstNode node;
  final String description;
  _ContextUsage(this.node, this.description);
}

class _ContextUsageFinder extends RecursiveAstVisitor<void> {
  final List<_ContextUsage> usages = [];

  static const _contextMethods = {
    'Navigator.of', 'Theme.of', 'MediaQuery.of',
    'ScaffoldMessenger.of', 'Scaffold.of',
    'DefaultTextStyle.of', 'Directionality.of',
    'ModalRoute.of', 'FocusScope.of',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource() ?? '';
    final fullCall = '$target.${node.methodName.name}';

    if (_contextMethods.contains(fullCall)) {
      usages.add(_ContextUsage(node, fullCall));
    }

    // context.read, context.watch, context.select
    if (target == 'context') {
      final method = node.methodName.name;
      if (method == 'read' || method == 'watch' || method == 'select') {
        usages.add(_ContextUsage(node, 'context.$method'));
      }
    }

    super.visitMethodInvocation(node);
  }
}
