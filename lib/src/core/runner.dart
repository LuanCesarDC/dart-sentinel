import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import 'issue.dart';
import 'project_context.dart';
import 'rule.dart';
import 'suppressions.dart';

/// Category → rule names, shared by the runner and `dart_sentinel rules`.
const Map<String, Set<String>> ruleCategories = {
  'arch': {
    'banned-imports',
    'banned-symbols',
    'layer-dependency',
    'feature-isolation',
    'import-cycles',
  },
  'dead': {'dead-files', 'dead-exports', 'unused-code'},
  'metrics': {'complexity', 'build-complexity', 'class-metrics'},
  'lint': {'dispose-check', 'async-safety'},
  'slop': {
    'empty-catch',
    'dead-todos',
    'generic-naming',
    'redundant-comments',
    'verbose-logging',
    'single-method-class',
    'passthrough-function',
    'lazy-null-check',
    'avoid-global-state',
    'no-magic-number',
    'no-equal-then-else',
    'avoid-commented-out-code',
    'no-equal-arguments',
    'avoid-self-compare',
    'avoid-returning-widgets',
    'flutter-anti-patterns',
  },
  'models': {'model-missing-methods'},
  'testing': {'untested-files', 'test-coverage', 'test-quality'},
  'pub': {'pubspec', 'misused-dependencies'},
};

/// Category a rule belongs to, or 'other' for rules outside the map.
String categoryOf(String ruleName) => ruleCategories.entries
    .firstWhere(
      (entry) => entry.value.contains(ruleName),
      orElse: () => const MapEntry('other', {}),
    )
    .key;

/// Runs all enabled rules against a [ProjectContext] and collects issues.
class RuleRunner {
  final List<AnalyzerRule> rules;
  final AnalyzerConfig config;

  RuleRunner({required this.rules, required this.config});

  /// Run all rules and return sorted issues.
  ///
  /// Severity can be overridden per-rule via `AnalyzerConfig.ruleSeverities`.
  List<Issue> runAll(ProjectContext context) {
    final issues = <Issue>[];

    for (final rule in rules) {
      if (config.disabledRules.contains(rule.name)) continue;
      final ruleIssues = rule.run(context);

      // Apply severity override if configured
      final overrideSeverity = config.ruleSeverities[rule.name];

      if (overrideSeverity != null) {
        for (final issue in ruleIssues) {
          issues.add(
            Issue(
              rule: issue.rule,
              message: issue.message,
              file: issue.file,
              line: issue.line,
              severity: overrideSeverity,
            ),
          );
        }
      } else {
        issues.addAll(ruleIssues);
      }
    }

    final visible = issues.where((issue) => !_isSilenced(issue, context));
    return visible.toList()..sort();
  }

  bool _isSilenced(Issue issue, ProjectContext context) {
    final source = context.fileContents[_absolutePath(issue.file, context)];
    return source != null && isSuppressed(issue, source.split('\n'));
  }

  String _absolutePath(String relative, ProjectContext context) =>
      p.join(context.projectRoot, relative);

  /// Run only rules matching the given [category].
  ///
  /// Categories: 'arch', 'dead', 'metrics', 'lint', 'slop'
  List<Issue> runCategory(ProjectContext context, String category) {
    final categoryRules = _filterByCategory(category);
    final runner = RuleRunner(rules: categoryRules, config: config);
    return runner.runAll(context);
  }

  /// Run the rules of every category in [categories] (union).
  List<Issue> runCategories(
    ProjectContext context,
    Iterable<String> categories,
  ) {
    final selected = categories.expand(_filterByCategory).toSet().toList();
    return RuleRunner(rules: selected, config: config).runAll(context);
  }

  List<AnalyzerRule> _filterByCategory(String category) {
    final ruleNames = ruleCategories[category] ?? {};
    return rules.where((r) => ruleNames.contains(r.name)).toList();
  }
}
