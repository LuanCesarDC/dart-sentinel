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
    final reverseImports = reverseGraph(context.importGraph);
    final issues = <Issue>[];
    for (final file in context.allFiles) {
      if (context.parsedUnits[file] == null) continue;
      issues.addAll(_findDeadExports(file, context, reverseImports));
    }
    return issues;
  }

  List<Issue> _findDeadExports(
      String file,
      ProjectContext context,
      Map<String, Set<String>> reverseImports) {
    final unit = context.parsedUnits[file]!;
    final issues = <Issue>[];

    for (final directive in unit.directives) {
      if (directive is! ExportDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;

      final resolved = _resolveUri(uri, context.projectRoot, context.packageName);
      if (resolved == null) continue;

      final importers = reverseImports[file] ?? {};
      if (importers.isEmpty) {
        final line = directive.offset > 0
            ? _lineNumber(unit, directive.offset)
            : 0;
        issues.add(Issue(
          rule: name,
          message: 'Export of "$uri" is not used — no file imports this barrel/file',
          file: context.relativePath(file),
          line: line,
          severity: defaultSeverity,
        ));
      }
    }
    return issues;
  }

  String? _resolveUri(
      String uri, String projectRoot, String packageName) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final parts = uri.substring(8).split('/');
      if (parts.isEmpty || parts.first != packageName) return null;
      return '$projectRoot/lib/${parts.skip(1).join('/')}';
    }
    return null;
  }

  int _lineNumber(CompilationUnit unit, int offset) {
    return unit.lineInfo.getLocation(offset).lineNumber;
  }
}
