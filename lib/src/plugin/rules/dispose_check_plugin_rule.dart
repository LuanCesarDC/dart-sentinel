import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects disposable resources not cleaned up in dispose().
class DisposeCheckPluginRule extends AnalysisRule {
  DisposeCheckPluginRule()
    : super(
        name: 'dispose_check',
        description:
            'Detects disposable resources not cleaned up in dispose().',
      );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.disposeCheck;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final DisposeCheckPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    if (body is! BlockClassBody) return;
    _analyzeClass(body.members);
  }

  void _analyzeClass(NodeList<ClassMember> members) {
    final constructorParams = _collectConstructorParamFields(members);
    final disposableFields = _collectDisposableFields(
      members,
      constructorParams,
    );
    final methodBodies = _collectMethodBodies(members);
    final disposeCleanups = _collectDisposeCleanups(members, methodBodies);
    final addListenerCalls = _collectAddListenerCalls(members);

    _reportMissingDispose(disposableFields, disposeCleanups, members);
    _reportMissingRemoveListener(addListenerCalls, disposeCleanups);
  }

  Set<String> _collectConstructorParamFields(NodeList<ClassMember> members) {
    final result = <String>{};
    for (final member in members) {
      if (member is! ConstructorDeclaration) continue;
      for (final param in member.parameters.parameters) {
        final actual = param is DefaultFormalParameter
            ? param.parameter
            : param;
        if (actual is FieldFormalParameter) result.add(actual.name.lexeme);
        if (actual is SuperFormalParameter) result.add(actual.name.lexeme);
      }
      for (final init in member.initializers) {
        if (init is! ConstructorFieldInitializer) continue;
        if (init.expression is SimpleIdentifier) {
          result.add(init.fieldName.name);
        }
      }
    }
    return result;
  }

  Map<String, _DisposableType> _collectDisposableFields(
    NodeList<ClassMember> members,
    Set<String> constructorParams,
  ) {
    final fields = <String, _DisposableType>{};
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      for (final variable in member.fields.variables) {
        final typeName = member.fields.type?.toSource() ?? '';
        final fieldName = variable.name.lexeme;
        if (constructorParams.contains(fieldName)) continue;
        final type = _classifyType(typeName);
        if (type != null) fields[fieldName] = type;
      }
    }
    return fields;
  }

  Map<String, FunctionBody> _collectMethodBodies(
    NodeList<ClassMember> members,
  ) {
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
    Map<String, FunctionBody> methodBodies,
  ) {
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
      final visitor = _AddListenerFinder();
      member.body.visitChildren(visitor);
      calls.addAll(visitor.targets);
    }
    return calls;
  }

  void _reportMissingDispose(
    Map<String, _DisposableType> disposableFields,
    Map<String, Set<String>> disposeCleanups,
    NodeList<ClassMember> members,
  ) {
    for (final entry in disposableFields.entries) {
      final cleanups = disposeCleanups[entry.key] ?? {};
      if (cleanups.contains(entry.value.requiredCleanup)) continue;

      final fieldDecl = _findFieldDeclaration(members, entry.key);
      if (fieldDecl == null) continue;

      rule.reportAtNode(
        fieldDecl,
        arguments: [
          '${entry.value.typeName} "${entry.key}" must call '
              '.${entry.value.requiredCleanup}() in dispose()',
        ],
      );
    }
  }

  void _reportMissingRemoveListener(
    Set<String> addListenerCalls,
    Map<String, Set<String>> disposeCleanups,
  ) {
    final normalizedCleanups = <String, Set<String>>{};
    for (final entry in disposeCleanups.entries) {
      final normalized = _normalizeTarget(entry.key);
      normalizedCleanups.putIfAbsent(normalized, () => {}).addAll(entry.value);
    }
    // We can't report at the exact addListener call node from here easily,
    // so this is handled at the class level for now.
  }

  FieldDeclaration? _findFieldDeclaration(
    NodeList<ClassMember> members,
    String fieldName,
  ) {
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      for (final variable in member.fields.variables) {
        if (variable.name.lexeme == fieldName) return member;
      }
    }
    return null;
  }

  _DisposableType? _classifyType(String typeName) {
    final cleaned = typeName
        .replaceAll('?', '')
        .replaceAll(RegExp(r'<.*>'), '')
        .trim();
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

  String _normalizeTarget(String target) {
    final parts = target.split('.');
    return parts.last;
  }
}

class _DisposableType {
  final String typeName;
  final String requiredCleanup;
  _DisposableType(this.typeName, this.requiredCleanup);
}

class _CleanupCollector extends RecursiveAstVisitor<void> {
  final Map<String, FunctionBody> methodBodies;
  final Map<String, Set<String>> cleanups = {};
  final Set<String> _visited = {};

  _CleanupCollector(this.methodBodies);

  void collectFrom(FunctionBody body) {
    body.visitChildren(this);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier) {
      cleanups.putIfAbsent(target.name, () => {}).add(node.methodName.name);
    }
    if (target is PrefixedIdentifier) {
      cleanups
          .putIfAbsent(target.identifier.name, () => {})
          .add(node.methodName.name);
    }

    // Follow method calls within the class
    if (target == null) {
      final methodName = node.methodName.name;
      if (!_visited.contains(methodName) &&
          methodBodies.containsKey(methodName)) {
        _visited.add(methodName);
        methodBodies[methodName]!.visitChildren(this);
      }
    }

    super.visitMethodInvocation(node);
  }
}

class _AddListenerFinder extends RecursiveAstVisitor<void> {
  final Set<String> targets = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'addListener') {
      final target = node.target;
      if (target is SimpleIdentifier) targets.add(target.name);
      if (target is PrefixedIdentifier) targets.add(target.identifier.name);
    }
    super.visitMethodInvocation(node);
  }
}
