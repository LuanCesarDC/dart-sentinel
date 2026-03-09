import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Checks the complexity of `build()` methods in Flutter widgets.
///
/// - `build()` with too many LOC → warning/error
/// - `build()` with too many branches (if/for/while/switch) → warning/error
class BuildComplexityRule extends AnalyzerRule {
  @override
  String get name => 'build-complexity';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    final metrics = context.config.metrics;

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor =
          _BuildComplexityVisitor(relativePath, unit, metrics);
      unit.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _BuildComplexityVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final MetricsConfig metrics;
  final List<Issue> issues = [];

  _BuildComplexityVisitor(this.filePath, this.unit, this.metrics);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Find build() methods
    for (final member in node.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        _analyzeBuildMethod(member, node.name.lexeme);
      }
    }

    super.visitClassDeclaration(node);
  }

  void _analyzeBuildMethod(MethodDeclaration method, String className) {
    final line =
        unit.lineInfo.getLocation(method.offset).lineNumber;

    // Count LOC
    final loc = method.body.toSource().split('\n').length;
    if (loc >= metrics.buildMethodLocError) {
      issues.add(Issue(
        rule: 'build-complexity',
        message:
            'build() in "$className" has $loc lines '
            '(limit: ${metrics.buildMethodLocError}). '
            'Consider extracting widgets or helper methods.',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (loc >= metrics.buildMethodLocWarning) {
      issues.add(Issue(
        rule: 'build-complexity',
        message:
            'build() in "$className" has $loc lines '
            '(limit: ${metrics.buildMethodLocWarning}). '
            'Consider extracting widgets or helper methods.',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    // Count branches
    final branchCounter = _BranchCounter();
    method.body.accept(branchCounter);
    final branches = branchCounter.count;

    if (branches >= metrics.buildMethodBranchesError) {
      issues.add(Issue(
        rule: 'build-complexity',
        message:
            'build() in "$className" has $branches branches '
            '(limit: ${metrics.buildMethodBranchesError}). '
            'Consider extracting logic into separate methods.',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (branches >= metrics.buildMethodBranchesWarning) {
      issues.add(Issue(
        rule: 'build-complexity',
        message:
            'build() in "$className" has $branches branches '
            '(limit: ${metrics.buildMethodBranchesWarning}). '
            'Consider extracting logic into separate methods.',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }
  }
}

class _BranchCounter extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitIfStatement(IfStatement node) {
    count++;
    super.visitIfStatement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    count++;
    super.visitIfElement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    count++;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    count++;
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    count++;
    super.visitWhileStatement(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    count++;
    super.visitSwitchStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    count++;
    super.visitConditionalExpression(node);
  }
}
