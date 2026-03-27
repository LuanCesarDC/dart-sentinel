import 'package:path/path.dart' as p;

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Detects files in lib/ that have no corresponding test file.
///
/// The mapping convention is configurable: by default, it uses the suffix
/// convention (e.g. `lib/src/services/auth_service.dart` →
/// `test/src/services/auth_service_test.dart`).
class UntestedFilesRule extends AnalyzerRule {
  @override
  String get name => 'untested-files';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final testingConfig = context.config.testingConfig;
    final testDir = p.join(context.projectRoot, testingConfig.testDir);

    if (!context.directoryExists(testDir)) return [];

    final issues = <Issue>[];

    for (final file in context.allFiles) {
      if (!file.startsWith(context.libRoot)) continue;

      final relativePath = context.relativePath(file);

      // Check excludes
      if (_isExcluded(relativePath, testingConfig.exclude)) continue;

      // Check require_for filter
      if (testingConfig.requireFor.isNotEmpty &&
          !testingConfig.requireFor.any(
            (p) => GlobMatcher(p).matches(relativePath),
          )) {
        continue;
      }

      // Map lib file to expected test file
      final expectedTestPath = _mapToTestPath(
        relativePath,
        testingConfig.testDir,
        testingConfig.convention,
      );

      final testFilePath = p.join(context.projectRoot, expectedTestPath);
      if (!context.fileExists(testFilePath)) {
        issues.add(
          Issue(
            rule: name,
            message:
                '$relativePath has no corresponding test file\n'
                '  Expected: $expectedTestPath',
            file: relativePath,
            severity: defaultSeverity,
          ),
        );
      }
    }

    return issues;
  }

  bool _isExcluded(String relativePath, List<String> excludes) {
    return excludes.any((e) => GlobMatcher(e).matches(relativePath));
  }

  /// Maps a lib/ file path to its expected test/ path.
  ///
  /// Convention 'suffix': `lib/src/foo.dart` → `test/src/foo_test.dart`
  String _mapToTestPath(
    String libRelativePath,
    String testDir,
    String convention,
  ) {
    // Remove 'lib/' prefix
    final withoutLib = libRelativePath.startsWith('lib/')
        ? libRelativePath.substring(4)
        : libRelativePath;

    final baseName = p.basenameWithoutExtension(withoutLib);
    final dirName = p.dirname(withoutLib);

    switch (convention) {
      case 'suffix':
      default:
        final testFileName = '${baseName}_test.dart';
        return p.join(testDir, dirName, testFileName);
    }
  }
}
