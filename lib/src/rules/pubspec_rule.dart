import 'package:yaml/yaml.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Validates pubspec.yaml structure and dependency declarations.
///
/// Sub-rules:
/// - avoid-any-version: deps with `any` version constraint
/// - avoid-dependency-overrides: `dependency_overrides` section exists
/// - prefer-caret-version: deps not using caret syntax (^)
/// - dependencies-ordering: deps not in alphabetical order
/// - prefer-publish-to-none: missing `publish_to: none` for app packages
/// - banned-dependencies: configurable list of banned packages
class PubspecRule extends AnalyzerRule {
  @override
  String get name => 'pubspec';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final content = context.pubspecContent;
    if (content.isEmpty) return [];
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) return [];

    final issues = <Issue>[];
    const filePath = 'pubspec.yaml';

    // ── avoid-dependency-overrides ──
    if (yaml.containsKey('dependency_overrides')) {
      issues.add(Issue(
        rule: 'pubspec',
        message: 'pubspec.yaml contains dependency_overrides section',
        file: filePath,
        severity: Severity.warning,
      ));
    }

    // ── prefer-publish-to-none ──
    // If there's no `publish_to` and the package has no version or has
    // flutter dependency (likely an app, not a package), warn.
    final hasPublishTo = yaml.containsKey('publish_to');
    final hasFlutter = yaml['dependencies'] is YamlMap &&
        (yaml['dependencies'] as YamlMap).containsKey('flutter');
    if (!hasPublishTo && hasFlutter) {
      issues.add(Issue(
        rule: 'pubspec',
        message:
            'Flutter app missing "publish_to: none" in pubspec.yaml',
        file: filePath,
        severity: Severity.info,
      ));
    }

    // ── Check dependencies and dev_dependencies ──
    final bannedDeps = context.config.bannedDependencies;

    _checkDependencies(
      yaml['dependencies'],
      'dependencies',
      filePath,
      issues,
      bannedDeps,
    );
    _checkDependencies(
      yaml['dev_dependencies'],
      'dev_dependencies',
      filePath,
      issues,
      bannedDeps,
    );

    return issues;
  }

  void _checkDependencies(
    dynamic node,
    String section,
    String filePath,
    List<Issue> issues,
    Set<String> bannedDeps,
  ) {
    if (node is! YamlMap) return;

    final names = <String>[];
    for (final entry in node.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      names.add(name);

      // Skip SDK / path / git dependencies for version checks
      if (value is YamlMap) {
        // Has sdk, path, or git — skip version checks
        if (value.containsKey('sdk') ||
            value.containsKey('path') ||
            value.containsKey('git')) {
          // Still check banned
          if (bannedDeps.contains(name)) {
            issues.add(Issue(
              rule: 'pubspec',
              message: 'banned dependency "$name" found in $section',
              file: filePath,
              severity: Severity.error,
            ));
          }
          continue;
        }
        // Hosted with version field
        final version = value['version']?.toString();
        if (version != null) {
          _checkVersion(name, version, section, filePath, issues);
        }
      } else if (value is String) {
        _checkVersion(name, value, section, filePath, issues);
      } else if (value == null) {
        // `any` implicit
        issues.add(Issue(
          rule: 'pubspec',
          message:
              '$section "$name" has no version constraint (any)',
          file: filePath,
          severity: Severity.warning,
        ));
      }

      // ── banned-dependencies ──
      if (bannedDeps.contains(name)) {
        issues.add(Issue(
          rule: 'pubspec',
          message: 'banned dependency "$name" found in $section',
          file: filePath,
          severity: Severity.error,
        ));
      }
    }

    // ── dependencies-ordering ──
    for (int i = 1; i < names.length; i++) {
      if (names[i].compareTo(names[i - 1]) < 0) {
        issues.add(Issue(
          rule: 'pubspec',
          message:
              '$section are not in alphabetical order '
              '("${names[i]}" before "${names[i - 1]}")',
          file: filePath,
          severity: Severity.info,
        ));
        break; // one warning is enough
      }
    }
  }

  void _checkVersion(
    String name,
    String version,
    String section,
    String filePath,
    List<Issue> issues,
  ) {
    final trimmed = version.trim();

    // ── avoid-any-version ──
    if (trimmed == 'any' || trimmed.isEmpty) {
      issues.add(Issue(
        rule: 'pubspec',
        message: '$section "$name" uses "any" version constraint',
        file: filePath,
        severity: Severity.warning,
      ));
      return;
    }

    // ── prefer-caret-version ──
    // Allow: ^x.y.z, >=...  <..., and 'any'
    // Warn on bare versions like 1.2.3 or >1.0.0
    if (!trimmed.startsWith('^') &&
        !trimmed.startsWith('>=') &&
        !trimmed.startsWith('<=') &&
        trimmed != 'any') {
      issues.add(Issue(
        rule: 'pubspec',
        message:
            '$section "$name" version "$trimmed" — prefer caret syntax (^)',
        file: filePath,
        severity: Severity.info,
      ));
    }
  }
}
