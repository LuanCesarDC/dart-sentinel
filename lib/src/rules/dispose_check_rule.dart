import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Checks that resources are properly disposed.
///
/// - If `addListener(x)` is called, `removeListener(x)` must be in `dispose()`
/// - StreamSubscription fields must have `.cancel()` in `dispose()`
/// - StreamController fields must have `.close()` in `dispose()`
/// - TextEditingController/AnimationController/FocusNode/ScrollController
///   fields must have `.dispose()` in `dispose()`
class DisposeCheckRule extends AnalyzerRule {
  @override
  String get name => 'dispose-check';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor = _DisposeVisitor(relativePath, unit);
      unit.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _DisposeVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _DisposeVisitor(this.filePath, this.unit);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Collect disposable fields
    final disposableFields = <String, _DisposableType>{};

    for (final member in node.members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          final typeName = member.fields.type?.toSource() ?? '';
          final fieldName = variable.name.lexeme;

          final disposableType = _classifyDisposableType(typeName);
          if (disposableType != null) {
            disposableFields[fieldName] = disposableType;
          }
        }
      }
    }

    // Collect addListener calls (outside dispose)
    final addListenerCalls = <String>{};
    // Collect what's cleaned up in dispose()
    final disposeCleanups = <String, Set<String>>{};

    for (final member in node.members) {
      if (member is MethodDeclaration) {
        if (member.name.lexeme == 'dispose') {
          // Scan dispose body for cleanup calls
          final cleanupVisitor = _CleanupVisitor();
          member.body.visitChildren(cleanupVisitor);
          for (final cleanup in cleanupVisitor.cleanups) {
            disposeCleanups
                .putIfAbsent(cleanup.target, () => {})
                .add(cleanup.method);
          }
        } else {
          // Scan for addListener calls in non-dispose methods
          final listenerVisitor = _AddListenerVisitor();
          member.body.visitChildren(listenerVisitor);
          addListenerCalls.addAll(listenerVisitor.targets);
        }
      }
    }

    // Check disposable fields
    for (final entry in disposableFields.entries) {
      final fieldName = entry.key;
      final disposableType = entry.value;
      final cleanups = disposeCleanups[fieldName] ?? {};

      final requiredMethod = disposableType.requiredCleanup;
      if (!cleanups.contains(requiredMethod)) {
        final fieldDecl = _findFieldDeclaration(node, fieldName);
        final line = fieldDecl != null
            ? unit.lineInfo.getLocation(fieldDecl.offset).lineNumber
            : 0;

        issues.add(Issue(
          rule: 'dispose-check',
          message:
              '${disposableType.typeName} "$fieldName" must call '
              '.$requiredMethod() in dispose()',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ));
      }
    }

    // Check addListener / removeListener pairs
    for (final target in addListenerCalls) {
      final cleanups = disposeCleanups[target] ?? {};
      if (!cleanups.contains('removeListener')) {
        issues.add(Issue(
          rule: 'dispose-check',
          message:
              '"$target.addListener()" called but "$target.removeListener()" '
              'not found in dispose()',
          file: filePath,
          severity: Severity.warning,
        ));
      }
    }

    super.visitClassDeclaration(node);
  }

  FieldDeclaration? _findFieldDeclaration(
      ClassDeclaration node, String fieldName) {
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          if (variable.name.lexeme == fieldName) return member;
        }
      }
    }
    return null;
  }

  _DisposableType? _classifyDisposableType(String typeName) {
    // Strip nullable and generic parameters
    final cleaned =
        typeName.replaceAll('?', '').replaceAll(RegExp(r'<.*>'), '').trim();

    switch (cleaned) {
      case 'StreamSubscription':
        return _DisposableType('StreamSubscription', 'cancel');
      case 'StreamController':
        return _DisposableType('StreamController', 'close');
      case 'TextEditingController':
        return _DisposableType('TextEditingController', 'dispose');
      case 'AnimationController':
        return _DisposableType('AnimationController', 'dispose');
      case 'FocusNode':
        return _DisposableType('FocusNode', 'dispose');
      case 'ScrollController':
        return _DisposableType('ScrollController', 'dispose');
      case 'TabController':
        return _DisposableType('TabController', 'dispose');
      case 'PageController':
        return _DisposableType('PageController', 'dispose');
      case 'Timer':
        return _DisposableType('Timer', 'cancel');
      default:
        return null;
    }
  }
}

class _DisposableType {
  final String typeName;
  final String requiredCleanup;

  _DisposableType(this.typeName, this.requiredCleanup);
}

class _CleanupCall {
  final String target;
  final String method;

  _CleanupCall(this.target, this.method);
}

class _CleanupVisitor extends RecursiveAstVisitor<void> {
  final List<_CleanupCall> cleanups = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    final target = node.target;

    if (target != null) {
      final targetName = target.toSource();
      // Handle simple field references and 'this.field' references
      final cleanTarget = targetName.startsWith('this.')
          ? targetName.substring(5)
          : targetName;

      if ({'dispose', 'cancel', 'close', 'removeListener'}
          .contains(methodName)) {
        cleanups.add(_CleanupCall(cleanTarget, methodName));
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    // Handle optional chaining: field?.cancel()
    final expr = node.expression;
    if (expr is MethodInvocation) {
      visitMethodInvocation(expr);
      return;
    }
    super.visitExpressionStatement(node);
  }
}

class _AddListenerVisitor extends RecursiveAstVisitor<void> {
  final Set<String> targets = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'addListener') {
      final target = node.target;
      if (target != null) {
        final targetName = target.toSource();
        final cleanTarget = targetName.startsWith('this.')
            ? targetName.substring(5)
            : targetName;
        targets.add(cleanTarget);
      }
    }
    super.visitMethodInvocation(node);
  }
}
