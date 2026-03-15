import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects variables and functions with generic/meaningless names.
class GenericNamingPluginRule extends AnalysisRule {
  GenericNamingPluginRule()
      : super(
          name: 'generic_naming',
          description: 'Detects variables and functions with low semantic specificity.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.genericNaming;

  static const _defaultDenyVariables = {
    'item', 'element', 'data', 'info', 'temp', 'tmp',
    'obj', 'object', 'thing', 'stuff', 'foo', 'bar', 'baz',
  };

  static const _defaultDenyFunctions = {
    'handle', 'process', 'execute', 'run',
    'doStuff', 'doWork', 'doSomething',
  };

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addVariableDeclaration(this, visitor);
    registry.addSimpleFormalParameter(this, visitor);
    registry.addFunctionDeclaration(this, visitor);
    registry.addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final GenericNamingPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.lexeme;
    if (!GenericNamingPluginRule._defaultDenyVariables.contains(name)) return;
    if (_isInLoop(node) || _isInLambda(node)) return;
    rule.reportAtToken(node.name, arguments: ['variable', name]);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final name = node.name?.lexeme;
    if (name == null) return;
    if (!GenericNamingPluginRule._defaultDenyVariables.contains(name)) return;
    if (_isInLambda(node)) return;
    rule.reportAtNode(node, arguments: ['parameter', name]);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (!GenericNamingPluginRule._defaultDenyFunctions.contains(name)) return;
    rule.reportAtToken(node.name, arguments: ['function', name]);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (!GenericNamingPluginRule._defaultDenyFunctions.contains(name)) return;
    rule.reportAtToken(node.name, arguments: ['method', name]);
  }

  bool _isInLoop(AstNode node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is ForStatement || parent is ForElement) return true;
      if (parent is FunctionBody || parent is ClassDeclaration) break;
      parent = parent.parent;
    }
    return false;
  }

  bool _isInLambda(AstNode node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is FunctionExpression && parent.parent is! FunctionDeclaration) {
        return true;
      }
      if (parent is ClassDeclaration || parent is CompilationUnit) break;
      parent = parent.parent;
    }
    return false;
  }
}
