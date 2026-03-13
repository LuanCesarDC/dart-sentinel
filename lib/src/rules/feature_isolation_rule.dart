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
      issues.addAll(_checkFile(file, context));
    }
    return issues;
  }

  List<Issue> _checkFile(String file, ProjectContext context) {
    final config = context.config.featureIsolation!;
    final relativePath = context.relativePath(file);
    final unit = context.parsedUnits[file];
    if (unit == null) return [];

    final sourceFeature = _extractFeature(relativePath, config);
    if (sourceFeature == null) return [];

    final source = (
      relativePath: relativePath,
      absolutePath: file,
      feature: sourceFeature,
      unit: unit,
    );
    final issues = <Issue>[];
    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      final issue = _checkImportDirective(directive, source, context);
      if (issue != null) issues.add(issue);
    }
    return issues;
  }

  Issue? _checkImportDirective(
      ImportDirective directive,
      ({String relativePath, String absolutePath, String feature, CompilationUnit unit}) source,
      ProjectContext context) {
    final config = context.config.featureIsolation!;
    final uri = directive.uri.stringValue;
    if (uri == null) return null;
    if (uri.startsWith('dart:')) return null;

    final importRelative = _resolveToRelative(uri, source.absolutePath, context);
    if (importRelative == null) return null;
    if (_isSharedImport(importRelative, config)) return null;

    final targetFeature = _extractFeature(importRelative, config);
    if (targetFeature == null) return null;
    if (targetFeature == source.feature) return null;
    if (_isException(source.feature, importRelative, config)) return null;

    final line = source.unit.lineInfo.getLocation(directive.offset).lineNumber;
    return Issue(
      rule: name,
      message:
          'Feature "${source.feature}" cannot import from feature "$targetFeature". '
          'Use shared layers instead. (import: $uri)',
      file: source.relativePath,
      line: line,
      severity: defaultSeverity,
    );
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
