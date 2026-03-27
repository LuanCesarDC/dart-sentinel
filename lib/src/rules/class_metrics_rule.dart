import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects god classes using class-level metrics:
///
/// - **NOM** (Number of Methods): total declared methods in a class/mixin/enum
/// - **WMC** (Weighted Methods per Class): sum of cyclomatic complexity of all methods
/// - **LOC per class**: source lines in the class body
class ClassMetricsRule extends AnalyzerRule {
  @override
  String get name => 'class-metrics';

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

      final visitor = _ClassMetricsVisitor(relativePath, unit, metrics);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _ClassMetricsVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final MetricsConfig metrics;
  final List<Issue> issues = [];

  _ClassMetricsVisitor(this.filePath, this.unit, this.metrics);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    if (node.body is BlockClassBody) {
      final body = node.body as BlockClassBody;
      _analyzeMembers(className, body.members, node);
    }
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final mixinName = node.name.lexeme;
    _analyzeMembers(mixinName, node.body.members, node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final enumName = node.namePart.typeName.lexeme;
    _analyzeMembers(enumName, node.body.members, node);
  }

  void _analyzeMembers(
    String name,
    NodeList<ClassMember> members,
    Declaration node,
  ) {
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;

    // NOM: count declared methods (not constructors or fields)
    int nom = 0;
    int wmc = 0;
    for (final member in members) {
      if (member is MethodDeclaration) {
        nom++;
        wmc += _cyclomaticComplexity(member.body);
      }
    }

    // LOC
    final source = node.toSource();
    final loc = source.split('\n').length;

    // Check NOM
    if (nom >= metrics.numberOfMethodsError) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has $nom methods (limit: ${metrics.numberOfMethodsError})',
          file: filePath,
          line: line,
          severity: Severity.error,
        ),
      );
    } else if (nom >= metrics.numberOfMethodsWarning) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has $nom methods (limit: ${metrics.numberOfMethodsWarning})',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ),
      );
    }

    // Check WMC
    if (wmc >= metrics.weightedMethodsPerClassError) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has WMC of $wmc (limit: ${metrics.weightedMethodsPerClassError})',
          file: filePath,
          line: line,
          severity: Severity.error,
        ),
      );
    } else if (wmc >= metrics.weightedMethodsPerClassWarning) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has WMC of $wmc (limit: ${metrics.weightedMethodsPerClassWarning})',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ),
      );
    }

    // Check LOC per class
    if (loc >= metrics.linesPerClassError) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has $loc lines (limit: ${metrics.linesPerClassError})',
          file: filePath,
          line: line,
          severity: Severity.error,
        ),
      );
    } else if (loc >= metrics.linesPerClassWarning) {
      issues.add(
        Issue(
          rule: 'class-metrics',
          message:
              'class "$name" has $loc lines (limit: ${metrics.linesPerClassWarning})',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ),
      );
    }
  }

  int _cyclomaticComplexity(FunctionBody body) {
    final visitor = _CyclomaticComplexityCounter();
    body.accept(visitor);
    return visitor.complexity + 1;
  }
}

class _CyclomaticComplexityCounter extends RecursiveAstVisitor<void> {
  int complexity = 0;

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type.lexeme;
    if (op == '&&' || op == '||' || op == '??') {
      complexity++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }
}
