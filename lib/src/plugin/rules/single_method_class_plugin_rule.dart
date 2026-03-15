import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects classes with a single public method.
class SingleMethodClassPluginRule extends AnalysisRule {
  SingleMethodClassPluginRule()
      : super(
          name: 'single_method_class',
          description: 'Detects classes with a single public method that could be a function.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.singleMethodClass;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final SingleMethodClassPluginRule rule;
  _Visitor(this.rule);

  static const _objectMethods = {'toString', 'hashCode', 'noSuchMethod'};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.abstractKeyword != null) return;
    if (node.extendsClause != null || node.implementsClause != null) return;
    if (node.withClause != null) return;

    final body = node.body;
    if (body is! BlockClassBody) return;

    final publicMethods = body.members
        .whereType<MethodDeclaration>()
        .where((m) =>
            !m.isStatic &&
            !m.name.lexeme.startsWith('_') &&
            !_objectMethods.contains(m.name.lexeme));

    final publicFields = body.members
        .whereType<FieldDeclaration>()
        .where((f) =>
            !f.isStatic && !f.fields.variables.first.name.lexeme.startsWith('_'));

    if (publicMethods.length == 1 && publicFields.isEmpty) {
      final methodName = publicMethods.first.name.lexeme;
      rule.reportAtNode(
        node.namePart,
        arguments: [node.namePart.typeName.lexeme, methodName],
      );
    }
  }
}
