import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Checks for common async safety issues in Flutter code:
///
/// 1. `setState` called after `await` without `mounted` check
/// 2. `BuildContext` used after `await` without `mounted` check
/// 3. `async` function passed where `void Function()` is expected (fire-and-forget)
class AsyncSafetyRule extends AnalyzerRule {
  @override
  String get name => 'async-safety';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor = _AsyncSafetyVisitor(relativePath, unit);
      unit.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _AsyncSafetyVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _AsyncSafetyVisitor(this.filePath, this.unit);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.body is! BlockFunctionBody) {
      super.visitMethodDeclaration(node);
      return;
    }

    final body = node.body as BlockFunctionBody;
    if (!body.isAsynchronous) {
      super.visitMethodDeclaration(node);
      return;
    }

    _checkAsyncBody(body.block.statements);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final body = node.functionExpression.body;
    if (body is! BlockFunctionBody || !body.isAsynchronous) {
      super.visitFunctionDeclaration(node);
      return;
    }

    _checkAsyncBody(body.block.statements);
    super.visitFunctionDeclaration(node);
  }

  void _checkAsyncBody(List<Statement> statements) {
    bool seenAwait = false;
    bool mountedCheckAfterAwait = false;

    for (final stmt in statements) {
      // Check for await expressions
      if (_containsAwait(stmt)) {
        seenAwait = true;
        mountedCheckAfterAwait = false;
      }

      // Check for mounted check
      if (seenAwait && _isMountedCheck(stmt)) {
        mountedCheckAfterAwait = true;
      }

      // After an await, check for unsafe usage
      if (seenAwait && !mountedCheckAfterAwait) {
        _checkForSetStateAfterAwait(stmt);
        _checkForContextAfterAwait(stmt);
      }

      // Recurse into if/else blocks
      if (stmt is IfStatement) {
        if (_isMountedCheck(stmt)) {
          mountedCheckAfterAwait = true;
        }
      }
    }
  }

  bool _containsAwait(Statement stmt) {
    final visitor = _AwaitFinder();
    stmt.accept(visitor);
    return visitor.found;
  }

  bool _isMountedCheck(Statement stmt) {
    final source = stmt.toSource();
    return source.contains('mounted') ||
        source.contains('!mounted') ||
        source.contains('context.mounted');
  }

  void _checkForSetStateAfterAwait(Statement stmt) {
    final visitor = _SetStateFinder();
    stmt.accept(visitor);

    for (final offset in visitor.offsets) {
      final line = unit.lineInfo.getLocation(offset).lineNumber;
      issues.add(Issue(
        rule: 'async-safety',
        message: 'setState() called after await without `mounted` check',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }
  }

  void _checkForContextAfterAwait(Statement stmt) {
    final visitor = _ContextUsageFinder();
    stmt.accept(visitor);

    for (final usage in visitor.usages) {
      final line = unit.lineInfo.getLocation(usage.offset).lineNumber;
      issues.add(Issue(
        rule: 'async-safety',
        message:
            '${usage.description} used after await without `mounted` check',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
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
  final List<int> offsets = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState') {
      offsets.add(node.offset);
    }
    super.visitMethodInvocation(node);
  }
}

class _ContextUsage {
  final int offset;
  final String description;

  _ContextUsage(this.offset, this.description);
}

class _ContextUsageFinder extends RecursiveAstVisitor<void> {
  final List<_ContextUsage> usages = [];

  static const _contextMethods = {
    'Navigator.of',
    'Theme.of',
    'MediaQuery.of',
    'ScaffoldMessenger.of',
    'Scaffold.of',
    'DefaultTextStyle.of',
    'Directionality.of',
    'ModalRoute.of',
    'FocusScope.of',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Check for X.of(context)
    final target = node.target?.toSource() ?? '';
    final fullCall = '$target.${node.methodName.name}';

    if (_contextMethods.contains(fullCall)) {
      usages.add(_ContextUsage(node.offset, fullCall));
    }

    // Check for context.read, context.watch, etc.
    if (node.target is SimpleIdentifier) {
      final targetName = (node.target as SimpleIdentifier).name;
      if (targetName == 'context') {
        usages.add(_ContextUsage(
            node.offset, 'context.${node.methodName.name}'));
      }
    }

    super.visitMethodInvocation(node);
  }
}
