import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Reads an lcov.info file and verifies that test coverage meets the
/// configured thresholds (global and per-file).
class TestCoverageRule extends AnalyzerRule {
  @override
  String get name => 'test-coverage';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final coverageConfig = context.config.testingConfig.coverage;
    final lcovPath = '${context.projectRoot}/${coverageConfig.file}';

    final lcovContent = context.readFile(lcovPath);
    if (lcovContent == null) return [];
    final fileCoverage = _parseLcov(lcovContent);

    if (fileCoverage.isEmpty) return [];

    final issues = <Issue>[];

    // Per-file coverage
    int totalHit = 0;
    int totalFound = 0;

    for (final entry in fileCoverage.entries) {
      final file = entry.key;
      final cov = entry.value;
      totalHit += cov.linesHit;
      totalFound += cov.linesFound;

      if (cov.linesFound == 0) continue;
      final pct = (cov.linesHit / cov.linesFound * 100);

      // Check per-file minimum
      if (pct < coverageConfig.perFileMin) {
        // Check if excluded
        if (coverageConfig.exclude.any((e) => GlobMatcher(e).matches(file))) {
          continue;
        }

        // Check path-specific overrides
        final threshold = _getThreshold(file, coverageConfig);

        if (pct < threshold) {
          issues.add(
            Issue(
              rule: name,
              message:
                  '$file has ${pct.toStringAsFixed(0)}% coverage '
                  '(min: ${threshold.toStringAsFixed(0)}%)',
              file: file,
              severity: pct == 0 ? Severity.error : Severity.warning,
            ),
          );
        }
      }
    }

    // Global coverage
    if (totalFound > 0) {
      final globalPct = (totalHit / totalFound * 100);
      if (globalPct < coverageConfig.globalMin) {
        issues.add(
          Issue(
            rule: name,
            message:
                'Global coverage ${globalPct.toStringAsFixed(0)}% '
                'is below minimum ${coverageConfig.globalMin.toStringAsFixed(0)}%',
            file: 'project',
            severity: Severity.error,
          ),
        );
      }
    }

    return issues;
  }

  double _getThreshold(String file, CoverageConfig config) {
    for (final entry in config.enforceFor.entries) {
      if (GlobMatcher(entry.key).matches(file)) {
        return entry.value.toDouble();
      }
    }
    return config.perFileMin.toDouble();
  }

  Map<String, _FileCoverage> _parseLcov(String content) {
    final files = <String, _FileCoverage>{};
    String? currentFile;
    int linesFound = 0;
    int linesHit = 0;

    for (final line in content.split('\n')) {
      if (line.startsWith('SF:')) {
        currentFile = line.substring(3).trim();
        linesFound = 0;
        linesHit = 0;
      } else if (line.startsWith('LF:')) {
        linesFound = int.tryParse(line.substring(3).trim()) ?? 0;
      } else if (line.startsWith('LH:')) {
        linesHit = int.tryParse(line.substring(3).trim()) ?? 0;
      } else if (line == 'end_of_record' && currentFile != null) {
        files[currentFile] = _FileCoverage(
          linesFound: linesFound,
          linesHit: linesHit,
        );
        currentFile = null;
      }
    }

    return files;
  }
}

class _FileCoverage {
  final int linesFound;
  final int linesHit;

  _FileCoverage({required this.linesFound, required this.linesHit});
}
