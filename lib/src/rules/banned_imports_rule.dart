import 'package:analyzer/dart/ast/ast.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';
import '../utils/import_spellings.dart';

/// Enforces banned import rules based on architecture configuration.
///
/// For example: ViewModels must not import Repositories directly.
class BannedImportsRule extends AnalyzerRule {
  @override
  String get name => 'banned-imports';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  List<Issue> run(ProjectContext context) {
    final bannedConfigs = context.config.bannedImports;
    if (bannedConfigs.isEmpty) return [];

    final issues = <Issue>[];
    for (final file in context.allFiles) {
      issues.addAll(_checkFile(file, bannedConfigs, context));
    }
    return issues;
  }

  List<Issue> _checkFile(
    String file,
    List<BannedImportConfig> configs,
    ProjectContext context,
  ) {
    final relativePath = context.relativePath(file);
    final unit = context.parsedUnits[file];
    if (unit == null) return [];

    final issues = <Issue>[];
    for (final config in configs) {
      if (!matchesAnyGlob(relativePath, config.paths)) continue;
      for (final directive in unit.directives) {
        if (directive is! ImportDirective) continue;
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        if (!_matchesDeny(uri, relativePath, config.deny, context)) continue;

        final line = unit.lineInfo.getLocation(directive.offset).lineNumber;
        issues.add(
          Issue(
            rule: name,
            message: config.message.isNotEmpty
                ? '${config.message} (import: $uri)'
                : 'Banned import: $uri',
            file: relativePath,
            line: line,
            severity: defaultSeverity,
          ),
        );
      }
    }
    return issues;
  }

  bool _matchesDeny(
    String importUri,
    String sourceRelativePath,
    List<String> denyPatterns,
    ProjectContext context,
  ) {
    final spellings = importSpellings(
      importUri: importUri,
      sourceRelativePath: sourceRelativePath,
      packageName: context.packageName,
    );
    return denyPatterns.any((pattern) {
      final glob = GlobMatcher(pattern);
      return spellings.any(glob.matches);
    });
  }
}
