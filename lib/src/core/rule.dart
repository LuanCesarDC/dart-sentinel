import 'issue.dart';
import 'project_context.dart';

/// Base class for all analyzer rules.
///
/// Each rule is an isolated plugin that receives the full [ProjectContext]
/// and returns a list of [Issue]s found.
abstract class AnalyzerRule {
  /// Unique name for this rule (e.g. 'dead-files', 'banned-imports').
  String get name;

  /// Default severity for issues produced by this rule.
  Severity get defaultSeverity;

  /// Run this rule against the project and return any issues found.
  List<Issue> run(ProjectContext context);
}
