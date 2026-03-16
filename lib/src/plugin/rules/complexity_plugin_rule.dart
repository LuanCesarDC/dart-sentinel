import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects methods/functions exceeding complexity thresholds.
class ComplexityPluginRule extends AnalysisRule {
  ComplexityPluginRule()
    : super(
        name: 'sentinel_complexity',
        description:
            'Detects methods exceeding cyclomatic complexity, nesting, or parameter thresholds.',
      );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.complexity;

  // Default thresholds
  static const _ccWarning = 10;
  static const _linesWarning = 50;
  static const _paramsWarning = 5;
  static const _nestingWarning = 4;

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
  final ComplexityPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _analyze('Method', node.name.lexeme, node.body, node.parameters, node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _analyze(
      'Function',
      node.name.lexeme,
      node.functionExpression.body,
      node.functionExpression.parameters,
      node,
    );
  }

  void _analyze(
    String kind,
    String name,
    FunctionBody body,
    FormalParameterList? params,
    AstNode reportNode,
  ) {
    final cc = _cyclomaticComplexity(body);
    if (cc >= ComplexityPluginRule._ccWarning) {
      rule.reportAtNode(
        reportNode,
        arguments: [
          '$kind "$name" has cyclomatic complexity of $cc (limit: ${ComplexityPluginRule._ccWarning})',
        ],
      );
    }

    final lines = body.toSource().split('\n').length;
    if (lines >= ComplexityPluginRule._linesWarning) {
      rule.reportAtNode(
        reportNode,
        arguments: [
          '$kind "$name" has $lines lines (limit: ${ComplexityPluginRule._linesWarning})',
        ],
      );
    }

    final paramCount = params?.parameters.length ?? 0;
    if (paramCount >= ComplexityPluginRule._paramsWarning) {
      rule.reportAtNode(
        reportNode,
        arguments: [
          '$kind "$name" has $paramCount parameters (limit: ${ComplexityPluginRule._paramsWarning})',
        ],
      );
    }

    final nesting = _maxNestingDepth(body);
    if (nesting >= ComplexityPluginRule._nestingWarning) {
      rule.reportAtNode(
        reportNode,
        arguments: [
          '$kind "$name" has nesting depth of $nesting (limit: ${ComplexityPluginRule._nestingWarning})',
        ],
      );
    }
  }

  int _cyclomaticComplexity(FunctionBody body) {
    final v = _CCVisitor();
    body.accept(v);
    return v.complexity + 1;
  }

  int _maxNestingDepth(FunctionBody body) {
    final v = _NestingVisitor();
    body.accept(v);
    return v.maxDepth;
  }
}

class _CCVisitor extends RecursiveAstVisitor<void> {
  int complexity = 0;

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||' || op == '??') complexity++;
    super.visitBinaryExpression(node);
  }
}

class _NestingVisitor extends RecursiveAstVisitor<void> {
  int _depth = 0;
  int maxDepth = 0;

  void _enter() {
    _depth++;
    if (_depth > maxDepth) maxDepth = _depth;
  }

  void _exit() {
    _depth--;
  }

  @override
  void visitIfStatement(IfStatement node) {
    _enter();
    super.visitIfStatement(node);
    _exit();
  }

  @override
  void visitForStatement(ForStatement node) {
    _enter();
    super.visitForStatement(node);
    _exit();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _enter();
    super.visitWhileStatement(node);
    _exit();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _enter();
    super.visitDoStatement(node);
    _exit();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _enter();
    super.visitSwitchStatement(node);
    _exit();
  }
}
