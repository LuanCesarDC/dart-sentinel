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
    final constructorParams = _collectConstructorParamFields(members);
    final disposableFields = _collectDisposableFields(members, constructorParams);
    final methodBodies = _collectMethodBodies(members);
    final disposeCleanups = _collectDisposeCleanups(members, methodBodies);
    final addListenerCalls = _collectAddListenerCalls(members);

    _reportMissingDispose(disposableFields, disposeCleanups, members);
    _reportMissingRemoveListener(addListenerCalls, disposeCleanups);
  }

  // ── Data collection helpers ──

  Set<String> _collectConstructorParamFields(NodeList<ClassMember> members) {
    final result = <String>{};
    for (final member in members) {
      if (member is! ConstructorDeclaration) continue;
      result.addAll(_formalParamFields(member));
      result.addAll(_initializerParamFields(member));
    }
    return result;
  }

  Set<String> _formalParamFields(ConstructorDeclaration constructor) {
    final result = <String>{};
    for (final param in constructor.parameters.parameters) {
      final actual =
          param is DefaultFormalParameter ? param.parameter : param;
      if (actual is FieldFormalParameter) {
        result.add(actual.name.lexeme);
      } else if (actual is SuperFormalParameter) {
        result.add(actual.name.lexeme);
      }
    }
    return result;
  }

  Set<String> _initializerParamFields(ConstructorDeclaration constructor) {
    final result = <String>{};
    final paramNames = _constructorParamNames(constructor);
    for (final init in constructor.initializers) {
      if (init is! ConstructorFieldInitializer) continue;
      if (init.expression is! SimpleIdentifier) continue;
      final expr = init.expression as SimpleIdentifier;
      if (paramNames.contains(expr.name)) {
        result.add(init.fieldName.name);
      }
    }
    return result;
  }

  Set<String> _constructorParamNames(ConstructorDeclaration constructor) {
    return constructor.parameters.parameters
        .map((p) {
          final actual =
              p is DefaultFormalParameter ? p.parameter : p;
          return actual.name?.lexeme;
        })
        .whereType<String>()
        .toSet();
  }

  Map<String, _DisposableType> _collectDisposableFields(
      NodeList<ClassMember> members, Set<String> constructorParams) {
    final fields = <String, _DisposableType>{};
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      for (final variable in member.fields.variables) {
        final typeName = member.fields.type?.toSource() ?? '';
        final fieldName = variable.name.lexeme;
        if (constructorParams.contains(fieldName)) continue;
        final type = _classifyDisposableType(typeName);
        if (type != null) fields[fieldName] = type;
      }
    }
    return fields;
  }

  Map<String, FunctionBody> _collectMethodBodies(
      NodeList<ClassMember> members) {
    final bodies = <String, FunctionBody>{};
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      if (member.body is EmptyFunctionBody) continue;
      bodies[member.name.lexeme] = member.body;
    }
    return bodies;
  }

  Map<String, Set<String>> _collectDisposeCleanups(
      NodeList<ClassMember> members,
      Map<String, FunctionBody> methodBodies) {
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      if (member.name.lexeme != 'dispose') continue;
      final collector = _CleanupCollector(methodBodies);
      collector.collectFrom(member.body);
      return collector.cleanups;
    }
    return {};
  }

  Set<String> _collectAddListenerCalls(NodeList<ClassMember> members) {
    final calls = <String>{};
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      if (member.name.lexeme == 'dispose') continue;
      final visitor = _AddListenerVisitor();
      member.body.visitChildren(visitor);
      calls.addAll(visitor.targets);
    }
    return calls;
  }

  // ── Reporting helpers ──

  void _reportMissingDispose(
      Map<String, _DisposableType> disposableFields,
      Map<String, Set<String>> disposeCleanups,
      NodeList<ClassMember> members) {
    for (final entry in disposableFields.entries) {
      final cleanups = disposeCleanups[entry.key] ?? {};
      if (cleanups.contains(entry.value.requiredCleanup)) continue;

      final fieldDecl = _findFieldDeclaration(members, entry.key);
      final line = fieldDecl != null
          ? unit.lineInfo.getLocation(fieldDecl.offset).lineNumber
          : 0;
      issues.add(Issue(
        rule: 'dispose-check',
        message:
            '${entry.value.typeName} "${entry.key}" must call '
            '.${entry.value.requiredCleanup}() in dispose()',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }
  }

  void _reportMissingRemoveListener(
      Set<String> addListenerCalls,
      Map<String, Set<String>> disposeCleanups) {
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
      if (cleanups.contains('removeListener')) continue;
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

  FieldDeclaration? _findFieldDeclaration(
      NodeList<ClassMember> members, String fieldName) {
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      for (final variable in member.fields.variables) {
        if (variable.name.lexeme == fieldName) return member;
      }
    }
    return null;
  }

  _DisposableType? _classifyDisposableType(String typeName) {
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

  static String _normalizeTarget(String target) {
    var normalized = target.startsWith('this.') ? target.substring(5) : target;
    if (normalized.contains('.')) {
      normalized = normalized.split('.').last;
    }
    normalized = normalized.replaceAll('?', '');
    normalized = normalized.replaceFirst(RegExp(r'^_+'), '');
    return normalized.toLowerCase();
  }
}

// ── Helper classes ──

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

/// Recursively collects cleanup calls from dispose(), following calls
/// to other methods defined in the same class.
class _CleanupCollector {
  final Map<String, FunctionBody> _methodBodies;
  final Map<String, Set<String>> cleanups = {};
  final Set<String> _visited = {};

  _CleanupCollector(this._methodBodies);

  void collectFrom(FunctionBody body) {
    final visitor = _CleanupVisitor();
    body.visitChildren(visitor);
    for (final cleanup in visitor.cleanups) {
      cleanups.putIfAbsent(cleanup.target, () => {}).add(cleanup.method);
    }

    final callVisitor = _MethodCallCollector();
    body.visitChildren(callVisitor);
    for (final calledMethod in callVisitor.calledMethods) {
      if (_visited.contains(calledMethod)) continue;
      _visited.add(calledMethod);
      final calledBody = _methodBodies[calledMethod];
      if (calledBody != null) collectFrom(calledBody);
    }
  }
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
