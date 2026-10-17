import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Flags an `async` function whose body never awaits. Overrides are skipped:
/// they may need `async` to match a `Future` signature.
class AvoidRedundantAsyncRule extends AnalyzerRule {
  @override
  String get name => 'avoid-redundant-async';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final visitor = _AsyncVisitor(
        context.relativePath(entry.key),
        entry.value,
      );
      entry.value.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _AsyncVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _AsyncVisitor(this.filePath, this.unit);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(node.name.lexeme, node.functionExpression.body, node.offset);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final isOverride = node.metadata.any((a) => a.name.name == 'override');
    if (!isOverride) _check(node.name.lexeme, node.body, node.offset);
    super.visitMethodDeclaration(node);
  }

  void _check(String name, FunctionBody body, int offset) {
    if (!body.isAsynchronous || body.isGenerator || name == 'main') return;
    final finder = _AwaitFinder();
    body.accept(finder);
    if (finder.found) return;
    issues.add(
      Issue(
        rule: 'avoid-redundant-async',
        message:
            '"$name" is async but never awaits — drop `async` (return '
            'the Future directly or make it synchronous)',
        file: filePath,
        line: unit.lineInfo.getLocation(offset).lineNumber,
        severity: Severity.warning,
      ),
    );
  }
}

/// Finds `await` / `await for` in a body, ignoring nested closures.
class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) => found = true;

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForStatement(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}
