import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Enforces that features do not import from other features directly.
///
/// Features should communicate only through shared layers (core, domain, services).
class FeatureIsolationRule extends AnalyzerRule {
  @override
  String get name => 'feature-isolation';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  List<Issue> run(ProjectContext context) {
    final featureConfig = context.config.featureIsolation;
    if (featureConfig == null || !featureConfig.enabled) return [];

    final issues = <Issue>[];

    for (final file in context.allFiles) {
      final relativePath = context.relativePath(file);
      final unit = context.parsedUnits[file];
      if (unit == null) continue;

      // Determine which feature this file belongs to
      final sourceFeature = _extractFeature(relativePath, featureConfig);
      if (sourceFeature == null) continue;

      // Check each import
      for (final directive in unit.directives) {
        if (directive is! ImportDirective) continue;

        final uri = directive.uri.stringValue;
        if (uri == null || uri.startsWith('dart:')) continue;

        // Resolve to relative path
        final importRelative = _resolveToRelative(uri, file, context);
        if (importRelative == null) continue;

        // Check if import goes to a shared/allowed path
        if (_isSharedImport(importRelative, featureConfig)) continue;

        // Check if import goes to a different feature
        final targetFeature =
            _extractFeature(importRelative, featureConfig);
        if (targetFeature == null) continue;

        if (targetFeature != sourceFeature) {
          // Check exceptions
          if (_isException(
              sourceFeature, importRelative, featureConfig)) continue;

          final line =
              unit.lineInfo.getLocation(directive.offset).lineNumber;

          issues.add(Issue(
            rule: name,
            message:
                'Feature "$sourceFeature" cannot import from feature "$targetFeature". '
                'Use shared layers instead. (import: $uri)',
            file: relativePath,
            line: line,
            severity: defaultSeverity,
          ));
        }
      }
    }

    return issues;
  }

  /// Extract the feature name from a file path.
  /// E.g. `lib/features/booking/viewmodel/foo.dart` → `booking`
  String? _extractFeature(
      String relativePath, FeatureIsolationConfig config) {
    for (final pattern in config.paths) {
      // Pattern like "lib/features/*/"
      // Extract the wildcard segment
      final normalized = relativePath.replaceAll(r'\', '/');
      final patternBase =
          pattern.replaceAll('*/', '').replaceAll('*', '');

      if (normalized.startsWith(patternBase)) {
        final rest = normalized.substring(patternBase.length);
        final parts = rest.split('/');
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          return parts.first;
        }
      }
    }
    return null;
  }

  bool _isSharedImport(
      String importPath, FeatureIsolationConfig config) {
    return matchesAnyGlob(importPath, config.allowShared);
  }

  bool _isException(
      String sourceFeature,
      String importPath,
      FeatureIsolationConfig config) {
    for (final exception in config.exceptions) {
      // Check if source feature matches the exception's from
      if (exception.from.contains(sourceFeature)) {
        if (matchesAnyGlob(importPath, exception.allow)) {
          return true;
        }
      }
    }
    return false;
  }

  String? _resolveToRelative(
      String uri, String sourceFile, ProjectContext context) {
    if (uri.startsWith('package:${context.packageName}/')) {
      return 'lib/${uri.substring('package:${context.packageName}/'.length)}';
    }
    if (uri.startsWith('package:')) return null; // External package

    // Relative import: resolve based on source file
    final resolved =
        p.normalize(p.join(p.dirname(sourceFile), uri));
    return context.relativePath(resolved);
  }
}
