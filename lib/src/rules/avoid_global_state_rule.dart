import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects global mutable state (top-level `var`/`late` variables and
/// non-`final`/`const` static fields).
class AvoidGlobalStateRule extends AnalyzerRule {
  @override
  String get name => 'avoid-global-state';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      for (final decl in unit.declarations) {
        if (decl is TopLevelVariableDeclaration) {
          final vars = decl.variables;
          if (vars.isConst || vars.isFinal) continue;

          for (final v in vars.variables) {
            final line = unit.lineInfo.getLocation(v.offset).lineNumber;
            issues.add(Issue(
              rule: name,
              message:
                  'top-level mutable variable "${v.name.lexeme}" — '
                  'prefer final or const',
              file: relativePath,
              line: line,
              severity: Severity.warning,
            ));
          }
        }
      }

      // Check static mutable fields in classes
      final visitor = _StaticMutableVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _StaticMutableVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _StaticMutableVisitor(this.filePath, this.unit);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (!node.isStatic) return;
    final vars = node.fields;
    if (vars.isConst || vars.isFinal) return;

    for (final v in vars.variables) {
      final line = unit.lineInfo.getLocation(v.offset).lineNumber;
      issues.add(Issue(
        rule: 'avoid-global-state',
        message:
            'static mutable field "${v.name.lexeme}" — '
            'prefer final or const',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }
  }
}
