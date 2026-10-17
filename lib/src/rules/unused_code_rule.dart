import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/graph_utils.dart';

/// Detects unused top-level declarations (classes, functions, enums, typedefs,
/// mixins, extensions, top-level variables) across the project.
///
/// A symbol is considered "used" if it is referenced from any reachable file
/// (from entrypoints). Private symbols (_name) used within the same file are
/// ignored.
class UnusedCodeRule extends AnalyzerRule {
  @override
  String get name => 'unused-code';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    if (context.entrypoints.isEmpty) return [];

    // 1. Collect reachable files from entrypoints
    final reachable = reachableFromAll(
      context.entrypoints,
      context.importGraph,
    );

    // 2. Collect all top-level declarations from lib/ files
    final declarations = <_DeclaredSymbol>[];
    for (final file in context.allFiles) {
      if (!file.startsWith(context.libRoot)) continue;
      final unit = context.parsedUnits[file];
      if (unit == null) continue;
      declarations.addAll(_collectDeclarations(file, unit, context));
    }

    // 3. Collect all symbol references from all scanned files
    // (not just reachable — bin/ files import the barrel but aren't
    // reachable from it; they still count as usage)
    final usedSymbols = <String, Set<String>>{}; // file → set of symbol names
    for (final file in context.allFiles) {
      final unit = context.parsedUnits[file];
      if (unit == null) continue;
      final refs = _collectReferences(unit);
      usedSymbols[file] = refs;
    }

    // 4. Build import-based visibility: which files can see which declarations
    // A declaration in file X is visible to file Y if Y (transitively) imports X
    final revGraph = reverseGraph(context.importGraph);

    // 5. Check which declarations are used
    final issues = <Issue>[];
    for (final decl in declarations) {
      if (decl.isPrivate) continue; // Skip private; only matters within file
      if (decl.isEntryPoint) continue; // main() and @pragma('vm:entry-point')
      if (!reachable.contains(decl.file)) {
        continue; // Not reachable = dead-files handles this
      }

      // Check: is this symbol name referenced in any file that imports the declaring file?
      final importers = reachableFromAll([decl.file], revGraph);
      bool used = false;

      for (final importer in importers) {
        if (importer == decl.file) continue;
        final refs = usedSymbols[importer];
        if (refs != null && decl.isReferencedIn(refs)) {
          // Check show/hide combinators
          if (_isSymbolVisibleViaImport(
            context,
            importer,
            decl.file,
            decl.name,
          )) {
            used = true;
            break;
          }
        }
      }

      // Also check if used in same file (public but only used locally)
      if (!used) {
        final localRefs = usedSymbols[decl.file];
        if (localRefs != null && decl.isReferencedIn(localRefs)) {
          used = true;
        }
      }

      if (!used) {
        issues.add(
          Issue(
            rule: name,
            message: "${decl.kind} '${decl.name}' is declared but never used",
            file: context.relativePath(decl.file),
            line: decl.line,
            severity: defaultSeverity,
          ),
        );
      }
    }

    return issues;
  }

  List<_DeclaredSymbol> _collectDeclarations(
    String file,
    CompilationUnit unit,
    ProjectContext context,
  ) {
    final symbols = <_DeclaredSymbol>[];
    for (final decl in unit.declarations) {
      switch (decl) {
        case ClassDeclaration():
          symbols.add(
            _DeclaredSymbol(
              name: decl.namePart.typeName.lexeme,
              file: file,
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: 'Class',
            ),
          );
        case FunctionDeclaration():
          symbols.add(
            _DeclaredSymbol(
              name: decl.name.lexeme,
              file: file,
              isEntryPoint:
                  decl.name.lexeme == 'main' || _hasEntryPointPragma(decl),
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: decl.isGetter
                  ? 'Getter'
                  : decl.isSetter
                  ? 'Setter'
                  : 'Function',
            ),
          );
        case EnumDeclaration():
          symbols.add(
            _DeclaredSymbol(
              name: decl.namePart.typeName.lexeme,
              file: file,
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: 'Enum',
            ),
          );
        case MixinDeclaration():
          symbols.add(
            _DeclaredSymbol(
              name: decl.name.lexeme,
              file: file,
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: 'Mixin',
            ),
          );
        case TypeAlias():
          symbols.add(
            _DeclaredSymbol(
              name: decl.name.lexeme,
              file: file,
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: 'Typedef',
            ),
          );
        case TopLevelVariableDeclaration():
          for (final v in decl.variables.variables) {
            symbols.add(
              _DeclaredSymbol(
                name: v.name.lexeme,
                file: file,
                line: unit.lineInfo.getLocation(v.offset).lineNumber,
                kind: 'Variable',
              ),
            );
          }
        case ExtensionDeclaration():
          final extName = decl.name;
          if (extName != null) {
            symbols.add(
              _DeclaredSymbol(
                name: extName.lexeme,
                file: file,
                memberNames: _extensionMemberNames(decl),
                line: unit.lineInfo.getLocation(decl.offset).lineNumber,
                kind: 'Extension',
              ),
            );
          }
        case ExtensionTypeDeclaration():
          symbols.add(
            _DeclaredSymbol(
              name: decl.namePart.typeName.lexeme,
              file: file,
              line: unit.lineInfo.getLocation(decl.offset).lineNumber,
              kind: 'ExtensionType',
            ),
          );
      }
    }
    return symbols;
  }

  bool _hasEntryPointPragma(AnnotatedNode node) => node.metadata.any(
    (annotation) =>
        annotation.name.name == 'pragma' &&
        annotation.arguments?.arguments.firstOrNull?.toSource() ==
            "'vm:entry-point'",
  );

  /// Extension members are called through the receiver (`value.member()`),
  /// so the extension's own name never appears at the call site.
  Set<String> _extensionMemberNames(ExtensionDeclaration decl) {
    final names = <String>{};
    for (final member in decl.body.members) {
      if (member is MethodDeclaration) names.add(member.name.lexeme);
      if (member is FieldDeclaration) {
        names.addAll(member.fields.variables.map((v) => v.name.lexeme));
      }
    }
    return names;
  }

  Set<String> _collectReferences(CompilationUnit unit) {
    final visitor = _ReferenceCollector();
    unit.accept(visitor);
    return visitor.references;
  }

  /// Check if a symbol from [declaringFile] is visible in [importingFile]
  /// considering show/hide combinators.
  bool _isSymbolVisibleViaImport(
    ProjectContext context,
    String importingFile,
    String declaringFile,
    String symbolName,
  ) {
    final unit = context.parsedUnits[importingFile];
    if (unit == null) return true; // Conservative: assume visible

    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;

      // Check if this import resolves to the declaring file
      // Simple heuristic: check if the import graph maps to it
      final imports = context.importGraph[importingFile];
      if (imports == null || !imports.contains(declaringFile)) continue;

      // Check combinators
      for (final combinator in directive.combinators) {
        if (combinator is ShowCombinator) {
          final shown = combinator.shownNames.map((n) => n.name).toSet();
          if (!shown.contains(symbolName)) return false;
        }
        if (combinator is HideCombinator) {
          final hidden = combinator.hiddenNames.map((n) => n.name).toSet();
          if (hidden.contains(symbolName)) return false;
        }
      }
    }

    return true;
  }
}

class _DeclaredSymbol {
  final String name;
  final String file;
  final int line;
  final String kind;
  final bool isEntryPoint;
  final Set<String> memberNames;

  _DeclaredSymbol({
    required this.name,
    required this.file,
    required this.line,
    required this.kind,
    this.isEntryPoint = false,
    this.memberNames = const {},
  });

  bool isReferencedIn(Set<String> references) =>
      references.contains(name) || memberNames.any(references.contains);

  bool get isPrivate => name.startsWith('_');
}

/// Collects all identifier references in a compilation unit.
class _ReferenceCollector extends RecursiveAstVisitor<void> {
  final Set<String> references = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    references.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    references.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}
