import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// A file that declares a single public type should be named after it:
/// `HomePage` lives in `home_page.dart`. Generated files are skipped.
class PreferMatchFileNameRule extends AnalyzerRule {
  @override
  String get name => 'prefer-match-file-name';

  @override
  Severity get defaultSeverity => Severity.info;

  static final _generated = RegExp(r'\.(g|freezed|gr|config|mocks)\.dart$');

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];
    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      if (!relativePath.startsWith('lib/')) continue;
      if (_generated.hasMatch(relativePath)) continue;

      final types = _publicTypes(entry.value);
      if (types.length != 1) continue;
      final expected = p.basenameWithoutExtension(relativePath);
      if (_normalize(types.single.name) == _normalize(expected)) continue;

      issues.add(
        Issue(
          rule: name,
          message:
              '"${types.single.name}" is the only public type here — name the '
              'file after it (${_snakeCase(types.single.name)}.dart)',
          file: relativePath,
          line: entry.value.lineInfo
              .getLocation(types.single.offset)
              .lineNumber,
          severity: defaultSeverity,
        ),
      );
    }
    return issues;
  }

  List<({String name, int offset})> _publicTypes(CompilationUnit unit) {
    final types = <({String name, int offset})>[];
    for (final declaration in unit.declarations) {
      final token = switch (declaration) {
        ClassDeclaration() => declaration.namePart.typeName,
        EnumDeclaration() => declaration.namePart.typeName,
        MixinDeclaration() => declaration.name,
        _ => null,
      };
      if (token == null || token.lexeme.startsWith('_')) continue;
      types.add((name: token.lexeme, offset: declaration.offset));
    }
    return types;
  }

  String _normalize(String name) => name.replaceAll('_', '').toLowerCase();

  String _snakeCase(String name) => name
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'),
        (match) => '_${match[1]}',
      )
      .toLowerCase();
}
