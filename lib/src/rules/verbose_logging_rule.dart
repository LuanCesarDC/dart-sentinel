import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects excessive consecutive log/print statements.
class VerboseLoggingRule extends AnalyzerRule {
  @override
  String get name => 'verbose-logging';

  @override
  Severity get defaultSeverity => Severity.info;

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.verboseLogging;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor = _VerboseLoggingVisitor(relativePath, entry.value, config);
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _VerboseLoggingVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final VerboseLoggingConfig config;
  final List<Issue> issues = [];

  _VerboseLoggingVisitor(this.filePath, this.unit, this.config);

  @override
  void visitBlock(Block node) {
    _checkConsecutiveLogs(node.statements);
    super.visitBlock(node);
  }

  void _checkConsecutiveLogs(List<Statement> statements) {
    var consecutiveCount = 0;
    int? streakStartOffset;

    for (final stmt in statements) {
      if (_isLogStatement(stmt)) {
        if (consecutiveCount == 0) {
          streakStartOffset = stmt.offset;
        }
        consecutiveCount++;
      } else {
        _reportIfExcessive(consecutiveCount, streakStartOffset);
        consecutiveCount = 0;
        streakStartOffset = null;
      }
    }
    _reportIfExcessive(consecutiveCount, streakStartOffset);
  }

  void _reportIfExcessive(int count, int? offset) {
    if (count >= config.maxConsecutiveLogs && offset != null) {
      final line = unit.lineInfo.getLocation(offset).lineNumber;
      issues.add(Issue(
        rule: 'verbose-logging',
        message: '$count consecutive log statements — '
            'consider a single structured log or removing debug noise.',
        file: filePath,
        line: line,
        severity: Severity.info,
      ));
    }
  }

  bool _isLogStatement(Statement stmt) {
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;

    if (expr is MethodInvocation) {
      final name = expr.methodName.name;
      final target = expr.target;

      if (target != null) {
        // e.g. logger.info(...)
        final fullName = '${target.toSource()}.$name';
        return config.logFunctions.contains(fullName);
      }
      // e.g. print(...), debugPrint(...)
      return config.logFunctions.contains(name);
    }

    if (expr is FunctionExpressionInvocation) {
      final fn = expr.function;
      if (fn is SimpleIdentifier) {
        return config.logFunctions.contains(fn.name);
      }
    }

    return false;
  }
}
