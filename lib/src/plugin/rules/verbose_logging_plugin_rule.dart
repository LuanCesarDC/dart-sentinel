import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects excessive consecutive log/print statements.
class VerboseLoggingPluginRule extends AnalysisRule {
  VerboseLoggingPluginRule()
      : super(
          name: 'verbose_logging',
          description: 'Detects excessive consecutive log/print statements.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.verboseLogging;

  static const _defaultMax = 3;

  static const _logFunctions = {
    'print', 'debugPrint', 'log',
    'logger.info', 'logger.warning', 'logger.severe',
    'logger.fine', 'logger.finer', 'logger.finest',
    'logger.shout', 'logger.config',
  };

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addBlock(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final VerboseLoggingPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitBlock(Block node) {
    int consecutiveCount = 0;
    AstNode? streakStart;

    for (final stmt in node.statements) {
      if (_isLogStatement(stmt)) {
        streakStart ??= stmt;
        consecutiveCount++;
      } else {
        _reportIfExcessive(consecutiveCount, streakStart);
        consecutiveCount = 0;
        streakStart = null;
      }
    }
    _reportIfExcessive(consecutiveCount, streakStart);
  }

  void _reportIfExcessive(int count, AstNode? startNode) {
    if (count >= VerboseLoggingPluginRule._defaultMax && startNode != null) {
      rule.reportAtNode(startNode, arguments: [count]);
    }
  }

  bool _isLogStatement(Statement stmt) {
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;
    if (expr is! MethodInvocation) return false;
    final name = expr.methodName.name;
    final target = expr.target;

    if (target != null) {
      final fullName = '${target.toSource()}.$name';
      return VerboseLoggingPluginRule._logFunctions.contains(fullName);
    }
    return VerboseLoggingPluginRule._logFunctions.contains(name);
  }
}
