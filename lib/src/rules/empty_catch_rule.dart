import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects swallowed exceptions: empty catch blocks and catch-and-print-only.
class EmptyCatchRule extends AnalyzerRule {
  @override
  String get name => 'empty-catch';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.emptyCatch;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      final visitor = _EmptyCatchVisitor(relativePath, entry.value, config);
      entry.value.visitChildren(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _EmptyCatchVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final EmptyCatchConfig config;
  final List<Issue> issues = [];

  _EmptyCatchVisitor(this.filePath, this.unit, this.config);

  @override
  void visitCatchClause(CatchClause node) {
    final body = node.body;
    final statements = body.statements;

    if (statements.isEmpty) {
      _checkEmptyBody(node, body);
    } else if (config.flagPrintOnly && _isPrintOnly(statements)) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      issues.add(Issue(
        rule: 'empty-catch',
        message: 'Catch block only prints the error — '
            'consider logging with context or rethrowing.',
        file: filePath,
        line: line,
        severity: Severity.warning,
      ));
    }

    super.visitCatchClause(node);
  }

  void _checkEmptyBody(CatchClause node, Block body) {
    // Allow if the body has a comment and config permits it
    if (config.allowEmptyWithComment && _hasComment(body)) return;

    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    issues.add(Issue(
      rule: 'empty-catch',
      message: 'Empty catch block swallows the exception silently.',
      file: filePath,
      line: line,
      severity: Severity.warning,
    ));
  }

  bool _isPrintOnly(List<Statement> statements) {
    if (statements.length != 1) return false;
    final stmt = statements.first;
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;
    if (expr is! MethodInvocation) return false;
    final name = expr.methodName.name;
    return name == 'print' || name == 'debugPrint';
  }

  bool _hasComment(Block body) {
    // Walk the token stream between { and } to find comment tokens
    var token = body.leftBracket.next;
    final end = body.rightBracket;
    while (token != null && token != end) {
      // Check preceding comments on each token
      var comment = token.precedingComments;
      while (comment != null) {
        return true;
      }
      token = token.next;
    }
    // Also check preceding comments on the closing brace
    var comment = end.precedingComments;
    while (comment != null) {
      return true;
    }
    return false;
  }
}
