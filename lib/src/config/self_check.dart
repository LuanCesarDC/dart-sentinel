import 'package:analyzer/dart/ast/ast.dart';

import '../core/project_context.dart';
import '../utils/glob_matcher.dart';
import '../utils/import_spellings.dart';
import 'analyzer_config.dart';

/// Looks for `analyzer.yaml` patterns that can never match anything — the
/// silent failure where a project looks clean only because a rule isn't
/// checking what the author thinks it is.
///
/// Returns one message per dead pattern; empty when every pattern is live.
List<String> selfCheck(ProjectContext context) {
  final config = context.config;
  final spellings = _allImportSpellings(context);
  final files = context.allFiles.map(context.relativePath).toList();
  final messages = <String>[];

  for (final banned in config.bannedImports) {
    final scope = files.where((f) => matchesAnyGlob(f, banned.paths));
    if (scope.isEmpty) {
      messages.add(
        'banned_imports ${banned.paths}: "paths" matches no file in the '
        'project.',
      );
      continue;
    }
    for (final pattern in banned.deny) {
      final glob = GlobMatcher(pattern);
      if (!spellings.any(glob.matches)) {
        messages.add(
          'banned_imports deny "$pattern": matches no import in the project'
          '${_spellingHint(pattern, context.packageName)}.',
        );
      }
    }
  }

  final layers = config.layerConfig?.layers.values ?? const <LayerDefinition>[];
  for (final layer in layers) {
    for (final pattern in layer.denyFiles) {
      final glob = pattern.contains('/') ? pattern : '**/$pattern';
      if (!files.any((f) => matchesAnyGlob(f, [glob]))) {
        messages.add(
          'layers.${layer.name}.deny_files "$pattern": matches no file in '
          'the project.',
        );
      }
    }
  }
  return messages;
}

Set<String> _allImportSpellings(ProjectContext context) {
  final spellings = <String>{};
  for (final entry in context.parsedUnits.entries) {
    final source = context.relativePath(entry.key);
    for (final directive in entry.value.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      spellings.addAll(
        importSpellings(
          importUri: uri,
          sourceRelativePath: source,
          packageName: context.packageName,
        ),
      );
    }
  }
  return spellings;
}

String _spellingHint(String pattern, String packageName) {
  if (!pattern.startsWith('package:')) return '';
  if (pattern.startsWith('package:$packageName/')) return '';
  return ' (this project is "$packageName", not the package in the pattern)';
}
