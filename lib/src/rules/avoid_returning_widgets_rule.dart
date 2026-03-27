import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects methods that return a Widget by constructing it inline,
/// suggesting extraction to a separate Widget class instead.
///
/// Only triggers when the method name starts with `_build` and the
/// file already imports Flutter.
class AvoidReturningWidgetsRule extends AnalyzerRule {
  @override
  String get name => 'avoid-returning-widgets';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      // Only check Flutter files
      final hasFlutterImport = unit.directives.any(
        (d) =>
            d is ImportDirective &&
            d.uri.stringValue != null &&
            d.uri.stringValue!.startsWith('package:flutter/'),
      );
      if (!hasFlutterImport) continue;

      final visitor = _ReturningWidgetsVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _ReturningWidgetsVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  static const _widgetTypes = {
    'Widget',
    'PreferredSizeWidget',
    'StatelessWidget',
    'StatefulWidget',
  };

  _ReturningWidgetsVisitor(this.filePath, this.unit);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final returnType = node.returnType;
    if (returnType == null) {
      super.visitMethodDeclaration(node);
      return;
    }

    final typeName = returnType.toSource();
    if (!_widgetTypes.contains(typeName)) {
      super.visitMethodDeclaration(node);
      return;
    }

    final methodName = node.name.lexeme;
    // Only flag _buildXxx methods that construct widgets inline
    if (!methodName.startsWith('_build') && !methodName.startsWith('build')) {
      super.visitMethodDeclaration(node);
      return;
    }

    // Exempt the overridden build() method itself
    if (methodName == 'build') {
      super.visitMethodDeclaration(node);
      return;
    }

    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    issues.add(Issue(
      rule: 'avoid-returning-widgets',
      message:
          'method "$methodName" returns Widget — '
          'consider extracting to a separate Widget class',
      file: filePath,
      line: line,
      severity: Severity.info,
    ));

    super.visitMethodDeclaration(node);
  }
}
