import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Flags a parameter of a function or method that its body never reads.
/// Overrides, abstract/external members, `main` and `_`-prefixed names are
/// skipped; closures are too, since their signature is dictated by the caller.
class AvoidUnusedParametersRule extends AnalyzerRule {
  @override
  String get name => 'avoid-unused-parameters';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final visitor = _ParameterVisitor(
        context.relativePath(entry.key),
        entry.value,
      );
      entry.value.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _ParameterVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _ParameterVisitor(this.filePath, this.unit);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme != 'main') {
      _check(
        node.name.lexeme,
        node.functionExpression.parameters,
        node.functionExpression.body,
      );
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final isOverride = node.metadata.any((a) => a.name.name == 'override');
    if (!isOverride && !node.isOperator) {
      _check(node.name.lexeme, node.parameters, node.body);
    }
    super.visitMethodDeclaration(node);
  }

  void _check(String owner, FormalParameterList? params, FunctionBody body) {
    if (params == null || body is EmptyFunctionBody) return;
    final used = _IdentifierCollector();
    body.accept(used);
    for (final parameter in params.parameters) {
      final name = parameter.name?.lexeme;
      if (name == null || name.startsWith('_') || used.names.contains(name)) {
        continue;
      }
      issues.add(
        Issue(
          rule: 'avoid-unused-parameters',
          message: 'parameter "$name" of "$owner" is never used',
          file: filePath,
          line: unit.lineInfo.getLocation(parameter.offset).lineNumber,
          severity: Severity.warning,
        ),
      );
    }
  }
}

class _IdentifierCollector extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}
