import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/graph_utils.dart';

/// Detects Dart files that are not reachable from any entrypoint.
class DeadFilesRule extends AnalyzerRule {
  @override
  String get name => 'dead-files';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    if (context.entrypoints.isEmpty) return [];

    final reachable = reachableFromAll(
      context.entrypoints,
      context.importGraph,
    );

    final issues = <Issue>[];

    // Only check files under lib/
    for (final file in context.allFiles) {
      if (!file.startsWith(context.libRoot)) continue;
      if (reachable.contains(file)) continue;

      issues.add(Issue(
        rule: name,
        message: 'File is not reachable from any entrypoint',
        file: context.relativePath(file),
        severity: defaultSeverity,
      ));
    }

    return issues;
  }
}
