import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects classes with a single public method that could be a plain function.
class SingleMethodClassRule extends AnalyzerRule {
  @override
  String get name => 'single-method-class';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.singleMethodClass;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor =
          _SingleMethodClassVisitor(relativePath, entry.value, config);
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _SingleMethodClassVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final SingleMethodClassConfig config;
  final List<Issue> issues = [];

  _SingleMethodClassVisitor(this.filePath, this.unit, this.config);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_shouldSkip(node)) {
      super.visitClassDeclaration(node);
      return;
    }

    final publicMethods = _publicMethods(node);
    final publicFields = _publicFields(node);

    if (publicMethods.length == 1 && publicFields.isEmpty) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      final methodName = publicMethods.first.name.lexeme;
      issues.add(Issue(
        rule: 'single-method-class',
        message:
            'Class \'${node.name.lexeme}\' has only one public method '
            '\'$methodName\' — consider using a plain function instead.',
        file: filePath,
        line: line,
        severity: Severity.info,
      ));
    }

    super.visitClassDeclaration(node);
  }

  bool _shouldSkip(ClassDeclaration node) {
    if (node.abstractKeyword != null) return true;
    if (config.ignoreIfExtends) {
      if (node.extendsClause != null || node.implementsClause != null) {
        return true;
      }
      if (node.withClause != null) return true;
    }
    if (config.ignoreIfHasConstructorParams && _hasConstructorParams(node)) {
      return true;
    }
    return false;
  }

  static const _objectMethods = {'toString', 'hashCode', 'noSuchMethod'};

  Iterable<MethodDeclaration> _publicMethods(ClassDeclaration node) {
    return node.members.whereType<MethodDeclaration>().where(
          (m) =>
              !m.isStatic &&
              !m.name.lexeme.startsWith('_') &&
              !_objectMethods.contains(m.name.lexeme),
        );
  }

  Iterable<FieldDeclaration> _publicFields(ClassDeclaration node) {
    return node.members.whereType<FieldDeclaration>().where(
          (f) =>
              !f.isStatic &&
              !f.fields.variables.first.name.lexeme.startsWith('_'),
        );
  }

  bool _hasConstructorParams(ClassDeclaration node) {
    for (final member in node.members) {
      if (member is ConstructorDeclaration) {
        if (member.parameters.parameters.isNotEmpty) return true;
      }
    }
    return false;
  }
}
