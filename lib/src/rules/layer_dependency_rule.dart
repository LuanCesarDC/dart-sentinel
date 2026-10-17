import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Validates that imports respect the defined architectural layers.
///
/// Each layer specifies which other layers it can depend on.
/// Imports that violate this are flagged.
class LayerDependencyRule extends AnalyzerRule {
  @override
  String get name => 'layer-dependency';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  List<Issue> run(ProjectContext context) {
    final layerConfig = context.config.layerConfig;
    if (layerConfig == null) return [];

    final issues = <Issue>[];
    for (final file in context.allFiles) {
      issues.addAll(_checkFile(file, context));
    }
    return issues;
  }

  List<Issue> _checkFile(String file, ProjectContext context) {
    final layerConfig = context.config.layerConfig!;
    final relativePath = context.relativePath(file);
    final unit = context.parsedUnits[file];
    if (unit == null) return [];

    final sourceLayer = _findLayer(relativePath, layerConfig);
    if (sourceLayer == null) return [];

    final source = (relativePath: relativePath, unit: unit, layer: sourceLayer);
    final issues = <Issue>[];
    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      final issue = _checkLayerImport(directive, source, file, context);
      if (issue != null) issues.add(issue);
    }
    return issues;
  }

  Issue? _checkLayerImport(
    ImportDirective directive,
    ({String relativePath, CompilationUnit unit, LayerDefinition layer}) source,
    String sourceFile,
    ProjectContext context,
  ) {
    final layerConfig = context.config.layerConfig!;
    final uri = directive.uri.stringValue;
    if (uri == null) return null;
    if (uri.startsWith('dart:')) return null;

    final importRelative = _resolveToRelative(uri, sourceFile, context);
    if (importRelative == null) return null;

    final targetLayer = _findLayer(importRelative, layerConfig);
    if (targetLayer == null) return null;
    if (source.layer.name == targetLayer.name) return null;
    if (source.layer.canDependOn.contains(targetLayer.name)) return null;

    final line = source.unit.lineInfo.getLocation(directive.offset).lineNumber;
    return Issue(
      rule: name,
      message:
          'Layer "${source.layer.name}" cannot depend on "${targetLayer.name}" '
          '(import: $uri)',
      file: source.relativePath,
      line: line,
      severity: defaultSeverity,
    );
  }

  /// The most specific layer matching [relativePath]: when `lib/core/**` and
  /// `lib/core/*/model/**` both match, the longer literal pattern wins, so
  /// declaration order in `analyzer.yaml` doesn't matter.
  LayerDefinition? _findLayer(String relativePath, LayerConfig config) {
    LayerDefinition? best;
    var bestSpecificity = -1;
    for (final layer in config.layers.values) {
      for (final pattern in layer.paths) {
        if (!matchesAnyGlob(relativePath, [pattern])) continue;
        final specificity = pattern.replaceAll(RegExp(r'[*?{},]'), '').length;
        if (specificity > bestSpecificity) {
          best = layer;
          bestSpecificity = specificity;
        }
      }
    }
    return best;
  }

  String? _resolveToRelative(
    String uri,
    String sourceFile,
    ProjectContext context,
  ) {
    if (uri.startsWith('package:${context.packageName}/')) {
      return 'lib/${uri.substring('package:${context.packageName}/'.length)}';
    }
    if (uri.contains(':')) return null; // other packages and dart: imports
    return context.relativePath(
      p.normalize(p.join(p.dirname(sourceFile), uri)),
    );
  }
}
