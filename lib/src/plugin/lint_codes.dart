import 'package:analyzer/error/error.dart';

/// Lint diagnostic codes for all Dart Sentinel plugin rules.
abstract final class SentinelCodes {
  // ── AI Slop ──

  static const LintCode emptyCatch = LintCode(
    'empty_catch',
    'Empty catch block swallows the exception silently.',
    correctionMessage: 'Add error handling, rethrow, or document why it is safe to ignore.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const LintCode emptyCatchPrintOnly = LintCode(
    'empty_catch',
    'Catch block only prints the error — consider logging with context or rethrowing.',
    correctionMessage: 'Replace with proper error handling or rethrow.',
    uniqueName: 'LintCode.empty_catch_print_only',
    severity: DiagnosticSeverity.WARNING,
  );

  static const LintCode deadTodo = LintCode(
    'dead_todo',
    '{0}',
    correctionMessage: 'Add context (issue number, author) or remove the comment.',
    severity: DiagnosticSeverity.INFO,
  );

  static const LintCode redundantComment = LintCode(
    'redundant_comment',
    'Comment restates the code — remove or add insight.',
    correctionMessage: 'Remove the comment or rewrite it to explain why, not what.',
    severity: DiagnosticSeverity.INFO,
  );

  static const LintCode genericNaming = LintCode(
    'generic_naming',
    'Generic {0} name "{1}" — use a more descriptive name.',
    correctionMessage: 'Rename to better reflect the purpose.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const LintCode verboseLogging = LintCode(
    'verbose_logging',
    '{0} consecutive log statements — consider a single structured log.',
    correctionMessage: 'Reduce to fewer, more meaningful log calls.',
    severity: DiagnosticSeverity.INFO,
  );

  static const LintCode singleMethodClass = LintCode(
    'single_method_class',
    'Class "{0}" has only one public method "{1}" — consider using a plain function.',
    correctionMessage: 'Replace the class with a top-level function.',
    severity: DiagnosticSeverity.INFO,
  );

  static const LintCode passthroughFunction = LintCode(
    'passthrough_function',
    '"{0}" only delegates to "{1}" — consider calling "{1}" directly.',
    correctionMessage: 'Inline the call or remove the wrapper.',
    severity: DiagnosticSeverity.INFO,
  );

  // ── Flutter Safety ──

  static const LintCode asyncSafety = LintCode(
    'async_safety',
    '{0}',
    correctionMessage: 'Add a `mounted` check before using BuildContext or setState after await.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const LintCode disposeCheck = LintCode(
    'dispose_check',
    '{0}',
    correctionMessage: 'Dispose or cancel the resource in dispose().',
    severity: DiagnosticSeverity.WARNING,
  );

  // ── Metrics ──

  static const LintCode complexity = LintCode(
    'sentinel_complexity',
    '{0}',
    correctionMessage: 'Extract methods, simplify logic, or reduce parameters.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const LintCode buildComplexity = LintCode(
    'build_complexity',
    '{0}',
    correctionMessage: 'Extract widgets or helper methods.',
    severity: DiagnosticSeverity.WARNING,
  );
}
