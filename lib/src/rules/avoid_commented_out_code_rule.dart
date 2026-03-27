import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects commented-out code blocks.
///
/// Heuristics:
/// - Lines starting with `//` that look like Dart statements
///   (contain `;`, `{`, `}`, `=>`, `return`, `if`, `for`, `class`, etc.)
/// - Three or more consecutive comment lines that parse as code
class AvoidCommentedOutCodeRule extends AnalyzerRule {
  @override
  String get name => 'avoid-commented-out-code';

  @override
  Severity get defaultSeverity => Severity.info;

  static final _codePatterns = RegExp(
    r'^\s*//'
    r'\s*('
    r'(import|export)\s'
    r'|class\s'
    r'|void\s'
    r'|return\s'
    r'|if\s*\('
    r'|for\s*\('
    r'|while\s*\('
    r'|switch\s*\('
    r'|final\s'
    r'|var\s'
    r'|const\s'
    r'|\w+\.\w+\('
    r'|\w+\s*=\s*'
    r'|\w+\([^)]*\)\s*[{;]'
    r'|try\s*\{'
    r'|catch\s*\('
    r')',
  );

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final file in context.allFiles) {
      final relativePath = context.relativePath(file);
      if (relativePath.endsWith('.g.dart') ||
          relativePath.endsWith('.freezed.dart')) {
        continue;
      }

      final lines = context.readFileLines(file);
      if (lines == null) continue;

      int consecutiveCodeComments = 0;
      int blockStart = 0;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_codePatterns.hasMatch(line)) {
          if (consecutiveCodeComments == 0) blockStart = i + 1;
          consecutiveCodeComments++;
        } else {
          if (consecutiveCodeComments >= 3) {
            issues.add(Issue(
              rule: name,
              message:
                  '$consecutiveCodeComments lines of commented-out code',
              file: relativePath,
              line: blockStart,
              severity: Severity.info,
            ));
          }
          consecutiveCodeComments = 0;
        }
      }

      // Check trailing block
      if (consecutiveCodeComments >= 3) {
        issues.add(Issue(
          rule: name,
          message: '$consecutiveCodeComments lines of commented-out code',
          file: relativePath,
          line: blockStart,
          severity: Severity.info,
        ));
      }
    }

    return issues;
  }
}
