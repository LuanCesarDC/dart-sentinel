import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Flags an explicit `dynamic` type annotation. Type arguments
/// (`Map<String, dynamic>`) are allowed: that is how JSON is typed.
class AvoidDynamicRule extends AnalyzerRule {
  @override
  String get name => 'avoid-dynamic';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final visitor = _DynamicVisitor(
        context.relativePath(entry.key),
        entry.value,
      );
      entry.value.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _DynamicVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _DynamicVisitor(this.filePath, this.unit);

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'dynamic' && node.parent is! TypeArgumentList) {
      issues.add(
        Issue(
          rule: 'avoid-dynamic',
          message:
              'explicit "dynamic" disables type checking — use a '
              'specific type, Object? or a generic',
          file: filePath,
          line: unit.lineInfo.getLocation(node.offset).lineNumber,
          severity: Severity.info,
        ),
      );
    }
    super.visitNamedType(node);
  }
}
