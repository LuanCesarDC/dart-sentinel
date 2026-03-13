import '../config/analyzer_config.dart';
import 'issue.dart';
import 'project_context.dart';
import 'rule.dart';

/// Runs all enabled rules against a [ProjectContext] and collects issues.
class RuleRunner {
  final List<AnalyzerRule> rules;
  final AnalyzerConfig config;

  RuleRunner({
    required this.rules,
    required this.config,
  });

  /// Run all rules and return sorted issues.
  ///
  /// Severity can be overridden per-rule via [config.ruleSeverities].
  List<Issue> runAll(ProjectContext context) {
    final issues = <Issue>[];

    for (final rule in rules) {
      final ruleIssues = rule.run(context);

      // Apply severity override if configured
      final overrideSeverity = config.ruleSeverities[rule.name];

      if (overrideSeverity != null) {
        for (final issue in ruleIssues) {
          issues.add(Issue(
            rule: issue.rule,
            message: issue.message,
            file: issue.file,
            line: issue.line,
            severity: overrideSeverity,
          ));
        }
      } else {
        issues.addAll(ruleIssues);
      }
    }

    issues.sort();
    return issues;
  }

  /// Run only rules matching the given [category].
  ///
  /// Categories: 'arch', 'dead', 'metrics', 'lint'
  List<Issue> runCategory(ProjectContext context, String category) {
    final categoryRules = _filterByCategory(category);
    final runner = RuleRunner(rules: categoryRules, config: config);
    return runner.runAll(context);
  }

  List<AnalyzerRule> _filterByCategory(String category) {
    final categoryMap = <String, Set<String>>{
      'arch': {
        'banned-imports',
        'banned-symbols',
        'layer-dependency',
        'feature-isolation',
        'import-cycles',
      },
      'dead': {
        'dead-files',
        'dead-exports',
      },
      'metrics': {
        'complexity',
        'build-complexity',
      },
      'lint': {
        'dispose-check',
        'async-safety',
      },
    };

    final ruleNames = categoryMap[category] ?? {};
    return rules.where((r) => ruleNames.contains(r.name)).toList();
  }
}
