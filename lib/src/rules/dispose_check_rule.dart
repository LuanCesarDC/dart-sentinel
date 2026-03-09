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
///
/// Smart ownership detection:
/// - Fields received via constructor (`this.controller`) are NOT owned by this
///   class and do NOT require cleanup — the creator is responsible.
/// - Only fields created locally (assigned in the class body) are checked.
///
/// Indirect cleanup detection:
/// - If `dispose()` calls a helper method (e.g. `reset()`, `cancelSubscriptions()`),
///   the rule follows those calls to find cleanups inside.
///
/// Listener target normalization:
/// - `addListener`/`removeListener` targets are normalized to the trailing
///   identifier, so `locator<GymService>().removeListener(x)` matches
///   `gymService.addListener(x)` when `gymService` resolves to the same field.
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
    _analyzeClass(node, node.members);
    super.visitClassDeclaration(node);
  }

  void _analyzeClass(AstNode node, NodeList<ClassMember> members) {
    // ── 1. Collect fields that came from constructor parameters ──
    final constructorParamFields = <String>{};
    for (final member in members) {
      if (member is ConstructorDeclaration) {
        _collectConstructorParamFields(member, constructorParamFields);
      }
    }

    // ── 2. Collect disposable fields, excluding constructor params ──
    final disposableFields = <String, _DisposableType>{};

    for (final member in members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          final typeName = member.fields.type?.toSource() ?? '';
          final fieldName = variable.name.lexeme;

          // Skip fields that come from constructor (not owned by this class)
          if (constructorParamFields.contains(fieldName)) continue;

          final disposableType = _classifyDisposableType(typeName);
          if (disposableType != null) {
            disposableFields[fieldName] = disposableType;
          }
        }
      }
    }

    // ── 3. Build a map of all methods in this class (for indirect cleanup) ──
    final methodBodies = <String, FunctionBody>{};
    for (final member in members) {
      if (member is MethodDeclaration && member.body is! EmptyFunctionBody) {
        methodBodies[member.name.lexeme] = member.body;
      }
    }

    // ── 4. Collect addListener calls (outside dispose) ──
    final addListenerCalls = <String>{};

    // ── 5. Collect cleanups from dispose() — following indirect calls ──
    final disposeCleanups = <String, Set<String>>{};

    for (final member in members) {
      if (member is MethodDeclaration) {
        if (member.name.lexeme == 'dispose') {
          // Scan dispose body + any methods it calls (transitively)
          _collectCleanupsRecursive(
            member.body,
            methodBodies,
            disposeCleanups,
            visited: {},
          );
        } else {
          // Scan for addListener calls in non-dispose methods
          final listenerVisitor = _AddListenerVisitor();
          member.body.visitChildren(listenerVisitor);
          addListenerCalls.addAll(listenerVisitor.targets);
        }
      }
    }

    // ── 6. Check disposable fields ──
    for (final entry in disposableFields.entries) {
      final fieldName = entry.key;
      final disposableType = entry.value;
      final cleanups = disposeCleanups[fieldName] ?? {};

      final requiredMethod = disposableType.requiredCleanup;
      if (!cleanups.contains(requiredMethod)) {
        final fieldDecl = _findFieldDeclaration(members, fieldName);
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

    // ── 7. Check addListener / removeListener pairs ──
    // Normalize both sides to simple field names for comparison
    final normalizedCleanups = <String, Set<String>>{};
    for (final entry in disposeCleanups.entries) {
      final normalized = _normalizeTarget(entry.key);
      normalizedCleanups
          .putIfAbsent(normalized, () => {})
          .addAll(entry.value);
    }

    for (final target in addListenerCalls) {
      final normalized = _normalizeTarget(target);
      final cleanups = normalizedCleanups[normalized] ?? {};
      if (!cleanups.contains('removeListener')) {
        issues.add(Issue(
          rule: 'dispose-check',
          message:
              '"$target.addListener()" called but '
              '"removeListener()" not found in dispose()',
          file: filePath,
          severity: Severity.warning,
        ));
      }
    }
  }

  /// Collects field names that are assigned via constructor parameters.
  /// Handles: `this.controller`, `this.focusNode`, etc.
  /// Also handles constructors that assign `controller = controller` from a
  /// named/positional parameter.
  void _collectConstructorParamFields(
    ConstructorDeclaration constructor,
    Set<String> out,
  ) {
    // Formal parameters with `this.x` syntax
    for (final param in constructor.parameters.parameters) {
      final actualParam =
          param is DefaultFormalParameter ? param.parameter : param;
      if (actualParam is FieldFormalParameter) {
        out.add(actualParam.name.lexeme);
      }
      // Also handle super.x formal parameters (rare but possible)
      if (actualParam is SuperFormalParameter) {
        out.add(actualParam.name.lexeme);
      }
    }

    // Initializer list assignments: `field = paramName`
    for (final init in constructor.initializers) {
      if (init is ConstructorFieldInitializer) {
        // If the field is initialized from a constructor parameter,
        // it's externally owned
        final expr = init.expression;
        if (expr is SimpleIdentifier) {
          // Check if the right side is one of the constructor's params
          final paramNames = constructor.parameters.parameters
              .map((p) {
                final actual =
                    p is DefaultFormalParameter ? p.parameter : p;
                return actual.name?.lexeme;
              })
              .whereType<String>()
              .toSet();
          if (paramNames.contains(expr.name)) {
            out.add(init.fieldName.name);
          }
        }
      }
    }
  }

  /// Recursively collect cleanup calls from a method body, following calls
  /// to other methods defined in the same class.
  void _collectCleanupsRecursive(
    FunctionBody body,
    Map<String, FunctionBody> methodBodies,
    Map<String, Set<String>> disposeCleanups, {
    required Set<String> visited,
  }) {
    // Scan this body for direct cleanup calls
    final cleanupVisitor = _CleanupVisitor();
    body.visitChildren(cleanupVisitor);
    for (final cleanup in cleanupVisitor.cleanups) {
      disposeCleanups
          .putIfAbsent(cleanup.target, () => {})
          .add(cleanup.method);
    }

    // Find calls to other methods in this class and follow them
    final callVisitor = _MethodCallCollector();
    body.visitChildren(callVisitor);

    for (final calledMethod in callVisitor.calledMethods) {
      if (visited.contains(calledMethod)) continue; // avoid infinite loops
      visited.add(calledMethod);

      final calledBody = methodBodies[calledMethod];
      if (calledBody != null) {
        _collectCleanupsRecursive(
          calledBody,
          methodBodies,
          disposeCleanups,
          visited: visited,
        );
      }
    }
  }

  /// Normalize a target expression to its trailing simple identifier.
  ///
  /// Examples:
  /// - `gymService` → `gymService`
  /// - `this.gymService` → `gymService`
  /// - `_gymService` → `_gymService`
  /// - `locator<GymService>()` → `locator` (won't match field, harmless)
  /// - `widget.controller` → `controller`
  ///
  /// For listener matching, we also strip underscores prefix and compare
  /// case-insensitively to handle `_studentService` vs `studentService`.
  static String _normalizeTarget(String target) {
    // Remove `this.` prefix
    var normalized = target.startsWith('this.') ? target.substring(5) : target;

    // If it contains `.`, take the last segment (e.g., `widget.controller` → `controller`)
    if (normalized.contains('.')) {
      normalized = normalized.split('.').last;
    }

    // Remove null-aware operator suffix
    normalized = normalized.replaceAll('?', '');

    // Strip leading underscores for comparison
    normalized = normalized.replaceFirst(RegExp(r'^_+'), '');

    return normalized.toLowerCase();
  }

  FieldDeclaration? _findFieldDeclaration(
      NodeList<ClassMember> members, String fieldName) {
    for (final member in members) {
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

/// Collects direct cleanup calls (dispose/cancel/close/removeListener)
/// from a method body.
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

/// Collects names of methods called without a target (i.e., calls to
/// methods in the same class): `reset()`, `_cancelTimers()`, etc.
class _MethodCallCollector extends RecursiveAstVisitor<void> {
  final Set<String> calledMethods = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Only collect calls without a target (same-class calls)
    // or with `this` as target
    final target = node.target;
    if (target == null) {
      calledMethods.add(node.methodName.name);
    } else if (target is ThisExpression) {
      calledMethods.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects targets of `addListener()` calls, normalized.
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
