import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects variables and functions with low semantic specificity.
class GenericNamingRule extends AnalyzerRule {
  @override
  String get name => 'generic-naming';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.genericNaming;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor = _GenericNamingVisitor(
        relativePath, entry.value, config,
      );
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _GenericNamingVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final GenericNamingConfig config;
  final List<Issue> issues = [];

  _GenericNamingVisitor(this.filePath, this.unit, this.config);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.lexeme;
    if (!config.denyVariableNames.contains(name)) {
      super.visitVariableDeclaration(node);
      return;
    }

    // Skip loop variables: for (final item in ...) / for (var i = ...)
    if (config.allowInLoops && _isInLoop(node)) {
      super.visitVariableDeclaration(node);
      return;
    }

    // Skip lambda parameters: .map((item) => ...)
    if (config.allowInLambdas && _isInLambda(node)) {
      super.visitVariableDeclaration(node);
      return;
    }

    _report(name, node.name.offset, 'variable');
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final name = node.name?.lexeme;
    if (name == null || !config.denyVariableNames.contains(name)) {
      super.visitSimpleFormalParameter(node);
      return;
    }

    if (config.allowInLambdas && _isInLambda(node)) {
      super.visitSimpleFormalParameter(node);
      return;
    }

    _report(name, node.name!.offset, 'parameter');
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (config.denyFunctionNames.contains(name)) {
      _report(name, node.name.offset, 'function');
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (config.denyFunctionNames.contains(name)) {
      _report(name, node.name.offset, 'method');
    }
    super.visitMethodDeclaration(node);
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
      if (parent is FunctionExpression &&
          parent.parent is! FunctionDeclaration) {
        return true;
      }
      if (parent is ClassDeclaration || parent is CompilationUnit) break;
      parent = parent.parent;
    }
    return false;
  }

  void _report(String name, int offset, String kind) {
    final line = unit.lineInfo.getLocation(offset).lineNumber;
    issues.add(Issue(
      rule: 'generic-naming',
      message: 'Generic $kind name "$name" — use a more descriptive name.',
      file: filePath,
      line: line,
      severity: Severity.warning,
    ));
  }
}
