import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Detects model classes inside configured `models.paths` that are missing
/// one or more of the configured generated methods (toMap, fromMap, copyWith,
/// ==, hashCode, toString).
///
/// Also warns about non-final fields when `immutable: true` is set.
class ModelMissingMethodsRule extends AnalyzerRule {
  @override
  String get name => 'model-missing-methods';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final modelsConfig = context.config.modelsConfig;
    if (modelsConfig.paths.isEmpty) return [];

    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      if (!_matchesModelPaths(relativePath, modelsConfig.paths)) continue;

      final visitor = _ModelClassVisitor(relativePath, unit, modelsConfig);
      unit.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }

  bool _matchesModelPaths(String relativePath, List<String> paths) {
    return paths.any((p) => GlobMatcher(p).matches(relativePath));
  }
}

class _ModelClassVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final ModelsConfig config;
  final List<Issue> issues = [];

  _ModelClassVisitor(this.filePath, this.unit, this.config);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;

    final existingMethods = <String>{};
    final existingFactories = <String>{};
    final fields = <FieldDeclaration>[];
    final body = node.body;
    if (body is! BlockClassBody) return;

    for (final member in body.members) {
      if (member is MethodDeclaration) {
        existingMethods.add(member.name.lexeme);
      } else if (member is ConstructorDeclaration) {
        if (member.factoryKeyword != null && member.name != null) {
          existingFactories.add(member.name!.lexeme);
        }
      } else if (member is FieldDeclaration) {
        fields.add(member);
      }
    }

    // Check for missing methods
    final missing = <String>[];

    if (config.copyWithName.isNotEmpty &&
        !existingMethods.contains(config.copyWithName)) {
      missing.add(config.copyWithName);
    }

    if (config.toMapName.isNotEmpty &&
        !existingMethods.contains(config.toMapName)) {
      missing.add(config.toMapName);
    }

    if (config.fromMapName.isNotEmpty &&
        !existingFactories.contains(config.fromMapName) &&
        !existingMethods.contains(config.fromMapName)) {
      missing.add(config.fromMapName);
    }

    if (config.equality) {
      if (!existingMethods.contains('==')) {
        missing.add('==');
      }
      if (!existingMethods.contains('hashCode') &&
          !_hasGetter(node, 'hashCode')) {
        missing.add('hashCode');
      }
    }

    if (config.toStringMethod && !existingMethods.contains('toString')) {
      missing.add('toString');
    }

    if (missing.isNotEmpty) {
      issues.add(
        Issue(
          rule: 'model-missing-methods',
          message:
              '$className is in a models path but is missing: '
              '${missing.join(', ')}',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ),
      );
    }

    // Check immutability
    if (config.immutable) {
      for (final field in fields) {
        if (field.isStatic) continue;
        for (final variable in field.fields.variables) {
          if (!field.fields.isFinal && !field.fields.isConst) {
            final fieldLine =
                unit.lineInfo.getLocation(variable.offset).lineNumber;
            issues.add(
              Issue(
                rule: 'model-missing-methods',
                message:
                    "Field '${variable.name.lexeme}' in immutable model "
                    'class $className should be final',
                file: filePath,
                line: fieldLine,
                severity: Severity.warning,
              ),
            );
          }
        }
      }
    }

    super.visitClassDeclaration(node);
  }

  bool _hasGetter(ClassDeclaration node, String name) {
    final body = node.body;
    if (body is! BlockClassBody) return false;
    for (final member in body.members) {
      if (member is MethodDeclaration &&
          member.isGetter &&
          member.name.lexeme == name) {
        return true;
      }
    }
    return false;
  }
}
