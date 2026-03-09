import 'package:analyzer/dart/ast/ast.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/graph_utils.dart';

/// Detects export directives that no other file imports.
///
/// Useful for finding stale barrel files or exports that are no longer needed.
class DeadExportsRule extends AnalyzerRule {
  @override
  String get name => 'dead-exports';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    // Build a reverse graph to see who imports each file
    final reverseImports = reverseGraph(context.importGraph);

    for (final file in context.allFiles) {
      final unit = context.parsedUnits[file];
      if (unit == null) continue;

      for (final directive in unit.directives) {
        if (directive is! ExportDirective) continue;

        final uri = directive.uri.stringValue;
        if (uri == null) continue;

        // Resolve the exported file
        final resolved = _resolveUri(
          uri,
          file,
          context.projectRoot,
          context.packageName,
        );
        if (resolved == null) continue;

        // Check if the exporting file itself is imported by anyone
        // other than through this export chain
        final importers = reverseImports[file] ?? {};

        if (importers.isEmpty) {
          issues.add(Issue(
            rule: name,
            message: 'Export of "$uri" is not used — no file imports this barrel/file',
            file: context.relativePath(file),
            line: directive.offset > 0
                ? _lineNumber(context.parsedUnits[file]!, directive.offset)
                : 0,
            severity: defaultSeverity,
          ));
        }
      }
    }

    return issues;
  }

  String? _resolveUri(
    String uri,
    String currentFile,
    String projectRoot,
    String packageName,
  ) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final parts = uri.substring(8).split('/');
      if (parts.isEmpty || parts.first != packageName) return null;
      final relative = parts.skip(1).join('/');
      return '$projectRoot/lib/$relative';
    }
    return null;
  }

  int _lineNumber(CompilationUnit unit, int offset) {
    return unit.lineInfo.getLocation(offset).lineNumber;
  }
}
