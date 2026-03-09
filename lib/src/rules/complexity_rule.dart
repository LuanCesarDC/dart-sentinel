import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Analyzes file and method-level complexity metrics:
///
/// - Lines of code (LOC) per file
/// - Cyclomatic complexity per method/function
/// - Number of methods per class
/// - Maximum nesting depth
/// - Number of parameters per method
/// - Lines per method
class ComplexityRule extends AnalyzerRule {
  @override
  String get name => 'complexity';

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

      // --- File-level metrics ---
      final loc = _countLoc(file, context);
      if (loc >= metrics.linesPerFileError) {
        issues.add(Issue(
          rule: name,
          message: 'File has $loc lines of code (limit: ${metrics.linesPerFileError})',
          file: relativePath,
          severity: Severity.error,
        ));
      } else if (loc >= metrics.linesPerFileWarning) {
        issues.add(Issue(
          rule: name,
          message: 'File has $loc lines of code (limit: ${metrics.linesPerFileWarning})',
          file: relativePath,
          severity: Severity.warning,
        ));
      }

      // --- Method/Function-level metrics ---
      final visitor = _ComplexityVisitor(relativePath, unit, metrics);
      unit.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }

  int _countLoc(String file, ProjectContext context) {
    final unit = context.parsedUnits[file];
    if (unit == null) return 0;

    final source = unit.toSource();
    final lines = source.split('\n');

    int count = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('//')) continue;
      if (trimmed.startsWith('/*')) continue;
      if (trimmed.startsWith('*')) continue;
      count++;
    }

    return count;
  }
}

class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final MetricsConfig metrics;
  final List<Issue> issues = [];

  _ComplexityVisitor(this.filePath, this.unit, this.metrics);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _analyzeCallable(
      name: node.name.lexeme,
      body: node.body,
      parameters: node.parameters,
      offset: node.offset,
      isMethod: true,
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _analyzeCallable(
      name: node.name.lexeme,
      body: node.functionExpression.body,
      parameters: node.functionExpression.parameters,
      offset: node.offset,
      isMethod: false,
    );
    super.visitFunctionDeclaration(node);
  }

  void _analyzeCallable({
    required String name,
    required FunctionBody body,
    required FormalParameterList? parameters,
    required int offset,
    required bool isMethod,
  }) {
    final line = unit.lineInfo.getLocation(offset).lineNumber;
    final kind = isMethod ? 'Method' : 'Function';

    // Cyclomatic complexity
    final cc = _cyclomaticComplexity(body);
    if (cc >= metrics.cyclomaticComplexityError) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has cyclomatic complexity of $cc '
            '(limit: ${metrics.cyclomaticComplexityError})',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (cc >= metrics.cyclomaticComplexityWarning) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has cyclomatic complexity of $cc '
            '(limit: ${metrics.cyclomaticComplexityWarning})',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    // Lines per method
    final methodLoc = _bodyLineCount(body);
    if (methodLoc >= metrics.linesPerMethodError) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has $methodLoc lines '
            '(limit: ${metrics.linesPerMethodError})',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (methodLoc >= metrics.linesPerMethodWarning) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has $methodLoc lines '
            '(limit: ${metrics.linesPerMethodWarning})',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    // Number of parameters
    final paramCount = parameters?.parameters.length ?? 0;
    if (paramCount >= metrics.maxParametersError) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has $paramCount parameters '
            '(limit: ${metrics.maxParametersError})',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (paramCount >= metrics.maxParametersWarning) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has $paramCount parameters '
            '(limit: ${metrics.maxParametersWarning})',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    // Maximum nesting depth
    final nesting = _maxNestingDepth(body);
    if (nesting >= metrics.maxNestingError) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has nesting depth of $nesting '
            '(limit: ${metrics.maxNestingError})',
        file: filePath,
        line: line,
        severity: Severity.error,
      ));
    } else if (nesting >= metrics.maxNestingWarning) {
      issues.add(Issue(
        rule: 'complexity',
        message:
            '$kind "$name" has nesting depth of $nesting '
            '(limit: ${metrics.maxNestingWarning})',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }
  }

  /// Calculate cyclomatic complexity of a function body.
  ///
  /// Counts: if, else, for, while, do, switch case, catch, &&, ||, ??, ternary
  int _cyclomaticComplexity(FunctionBody body) {
    final visitor = _CyclomaticComplexityVisitor();
    body.accept(visitor);
    return visitor.complexity + 1; // +1 for the method itself
  }

  int _bodyLineCount(FunctionBody body) {
    final source = body.toSource();
    return source.split('\n').length;
  }

  int _maxNestingDepth(FunctionBody body) {
    final visitor = _NestingDepthVisitor();
    body.accept(visitor);
    return visitor.maxDepth;
  }
}

class _CyclomaticComplexityVisitor extends RecursiveAstVisitor<void> {
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
    final op = node.operator.lexeme;
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

class _NestingDepthVisitor extends RecursiveAstVisitor<void> {
  int _currentDepth = 0;
  int maxDepth = 0;

  void _enter() {
    _currentDepth++;
    if (_currentDepth > maxDepth) maxDepth = _currentDepth;
  }

  void _exit() {
    _currentDepth--;
  }

  @override
  void visitIfStatement(IfStatement node) {
    _enter();
    super.visitIfStatement(node);
    _exit();
  }

  @override
  void visitForStatement(ForStatement node) {
    _enter();
    super.visitForStatement(node);
    _exit();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _enter();
    super.visitWhileStatement(node);
    _exit();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _enter();
    super.visitDoStatement(node);
    _exit();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _enter();
    super.visitSwitchStatement(node);
    _exit();
  }

  @override
  void visitTryStatement(TryStatement node) {
    _enter();
    super.visitTryStatement(node);
    _exit();
  }
}
