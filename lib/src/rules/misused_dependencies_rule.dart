import 'package:analyzer/dart/ast/ast.dart';
import 'package:yaml/yaml.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Validates pubspec dependencies against actual imports:
///
/// - unused-dependency: listed in dependencies but never imported
/// - missing-dependency: imported package not listed in pubspec
/// - over-promoted-dependency: dev-only package in dependencies
/// - under-promoted-dependency: production package in dev_dependencies
class MisusedDependenciesRule extends AnalyzerRule {
  @override
  String get name => 'misused-dependencies';

  @override
  Severity get defaultSeverity => Severity.warning;

  /// Packages that are used indirectly (build tools, code generators).
  static const _indirectPackages = {
    'build_runner',
    'build_verify',
    'build_test',
    'freezed',
    'json_serializable',
    'riverpod_generator',
    'mockito',
    'bloc_test',
    'very_good_analysis',
    'flutter_lints',
    'lints',
    'dart_code_metrics',
    'custom_lint',
  };

  @override
  List<Issue> run(ProjectContext context) {
    final content = context.pubspecContent;
    if (content.isEmpty) return [];
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) return [];

    final deps = _extractPackageNames(yaml['dependencies']);
    final devDeps = _extractPackageNames(yaml['dev_dependencies']);

    // Collect all imported packages from source files
    final libImports = <String>{}; // packages imported in lib/
    final testImports = <String>{}; // packages imported in test/

    for (final entry in context.parsedUnits.entries) {
      final filePath = context.relativePath(entry.key);
      final unit = entry.value;
      final isTest = filePath.startsWith('test/');

      for (final directive in unit.directives) {
        if (directive is ImportDirective) {
          final uri = directive.uri.stringValue;
          if (uri == null || !uri.startsWith('package:')) continue;
          final packageName = uri.split('/').first.replaceFirst('package:', '');
          if (isTest) {
            testImports.add(packageName);
          } else {
            libImports.add(packageName);
          }
        }
      }
    }

    final issues = <Issue>[];
    const filePath = 'pubspec.yaml';

    // Get the project's own package name
    final ownPackage = yaml['name']?.toString() ?? '';

    // ── unused-dependency ──
    for (final dep in deps) {
      if (dep == 'flutter' || dep == 'flutter_localizations') continue;
      if (_indirectPackages.contains(dep)) continue;
      if (!libImports.contains(dep) && !testImports.contains(dep)) {
        issues.add(
          Issue(
            rule: name,
            message: 'dependency "$dep" is not imported anywhere',
            file: filePath,
            severity: Severity.info,
          ),
        );
      }
    }

    // ── over-promoted: dev-only packages in dependencies ──
    for (final dep in deps) {
      if (dep == 'flutter' || dep == 'flutter_localizations') continue;
      if (_indirectPackages.contains(dep)) continue;
      if (!libImports.contains(dep) && testImports.contains(dep)) {
        issues.add(
          Issue(
            rule: name,
            message: '"$dep" is only used in tests — move to dev_dependencies',
            file: filePath,
            severity: Severity.warning,
          ),
        );
      }
    }

    // ── under-promoted: production packages in dev_dependencies ──
    for (final dep in devDeps) {
      if (_indirectPackages.contains(dep)) continue;
      if (libImports.contains(dep)) {
        issues.add(
          Issue(
            rule: name,
            message: '"$dep" is imported in lib/ — move to dependencies',
            file: filePath,
            severity: Severity.warning,
          ),
        );
      }
    }

    // ── missing-dependency ──
    final allDeclared = {...deps, ...devDeps, ownPackage, 'dart', 'flutter'};
    for (final pkg in libImports) {
      if (!allDeclared.contains(pkg)) {
        issues.add(
          Issue(
            rule: name,
            message: 'package "$pkg" is imported but not in pubspec.yaml',
            file: filePath,
            severity: Severity.error,
          ),
        );
      }
    }
    for (final pkg in testImports) {
      if (!allDeclared.contains(pkg)) {
        issues.add(
          Issue(
            rule: name,
            message:
                'package "$pkg" is imported in tests but not in pubspec.yaml',
            file: filePath,
            severity: Severity.warning,
          ),
        );
      }
    }

    return issues;
  }

  Set<String> _extractPackageNames(dynamic node) {
    if (node is! YamlMap) return {};
    return node.keys.map((k) => k.toString()).toSet();
  }
}
