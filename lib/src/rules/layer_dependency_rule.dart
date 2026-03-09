import 'package:analyzer/dart/ast/ast.dart';

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
      final relativePath = context.relativePath(file);
      final unit = context.parsedUnits[file];
      if (unit == null) continue;

      // Determine which layer this file belongs to
      final sourceLayer = _findLayer(relativePath, layerConfig);
      if (sourceLayer == null) continue;

      // Check each import
      for (final directive in unit.directives) {
        if (directive is! ImportDirective) continue;

        final uri = directive.uri.stringValue;
        if (uri == null || uri.startsWith('dart:')) continue;

        // Resolve the import to a relative path
        final importRelative = _resolveToRelative(uri, context);
        if (importRelative == null) continue;

        // Determine which layer the imported file belongs to
        final targetLayer = _findLayer(importRelative, layerConfig);
        if (targetLayer == null) continue;

        // Same layer is always OK
        if (sourceLayer.name == targetLayer.name) continue;

        // Check if the source layer is allowed to depend on the target layer
        if (!sourceLayer.canDependOn.contains(targetLayer.name)) {
          final line =
              unit.lineInfo.getLocation(directive.offset).lineNumber;

          issues.add(Issue(
            rule: name,
            message:
                'Layer "${sourceLayer.name}" cannot depend on "${targetLayer.name}" '
                '(import: $uri)',
            file: relativePath,
            line: line,
            severity: defaultSeverity,
          ));
        }
      }
    }

    return issues;
  }

  LayerDefinition? _findLayer(String relativePath, LayerConfig config) {
    for (final layer in config.layers.values) {
      if (matchesAnyGlob(relativePath, layer.paths)) {
        return layer;
      }
    }
    return null;
  }

  String? _resolveToRelative(String uri, ProjectContext context) {
    if (uri.startsWith('package:${context.packageName}/')) {
      return 'lib/${uri.substring('package:${context.packageName}/'.length)}';
    }
    // For relative imports, we'd need the source file path, but since
    // we're just checking layers, we can check the resolved graph
    return null;
  }
}
