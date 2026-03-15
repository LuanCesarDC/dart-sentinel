import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects overly complex build() methods in Flutter widgets.
class BuildComplexityPluginRule extends AnalysisRule {
  BuildComplexityPluginRule()
      : super(
          name: 'build_complexity',
          description: 'Detects overly complex build() methods in Flutter widgets.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.buildComplexity;

  static const _locWarning = 80;
  static const _branchesWarning = 6;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final BuildComplexityPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    if (body is! BlockClassBody) return;

    for (final member in body.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        _analyze(member, node.namePart.typeName.lexeme);
      }
    }
  }

  void _analyze(MethodDeclaration method, String className) {
    final loc = method.body.toSource().split('\n').length;
    if (loc >= BuildComplexityPluginRule._locWarning) {
      rule.reportAtNode(method, arguments: [
        'build() in "$className" has $loc lines (limit: ${BuildComplexityPluginRule._locWarning}). '
            'Consider extracting widgets.',
      ]);
    }

    final counter = _BranchCounter();
    method.body.accept(counter);
    if (counter.count >= BuildComplexityPluginRule._branchesWarning) {
      rule.reportAtNode(method, arguments: [
        'build() in "$className" has ${counter.count} branches '
            '(limit: ${BuildComplexityPluginRule._branchesWarning}). '
            'Consider extracting widgets.',
      ]);
    }
  }
}

class _BranchCounter extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitIfStatement(IfStatement node) { count++; super.visitIfStatement(node); }
  @override
  void visitForStatement(ForStatement node) { count++; super.visitForStatement(node); }
  @override
  void visitWhileStatement(WhileStatement node) { count++; super.visitWhileStatement(node); }
  @override
  void visitSwitchStatement(SwitchStatement node) { count++; super.visitSwitchStatement(node); }
  @override
  void visitConditionalExpression(ConditionalExpression node) { count++; super.visitConditionalExpression(node); }
  @override
  void visitIfElement(IfElement node) { count++; super.visitIfElement(node); }
}
