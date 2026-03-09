import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/graph_utils.dart';

/// Detects import cycles in the dependency graph using Tarjan's algorithm.
///
/// Reports the full cycle path: A → B → C → A.
class ImportCycleRule extends AnalyzerRule {
  @override
  String get name => 'import-cycles';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final cycles = findCycles(context.importGraph);
    final issues = <Issue>[];

    for (final cycle in cycles) {
      // Format the cycle as relative paths
      final cyclePaths =
          cycle.map((f) => context.relativePath(f)).toList();
      cyclePaths.add(cyclePaths.first); // Close the cycle

      final cycleStr = cyclePaths.join(' → ');

      // Report the issue on the first file of the cycle
      issues.add(Issue(
        rule: name,
        message: 'Import cycle detected: $cycleStr',
        file: context.relativePath(cycle.first),
        severity: defaultSeverity,
      ));
    }

    return issues;
  }
}
