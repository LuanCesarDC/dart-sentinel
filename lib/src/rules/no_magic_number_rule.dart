import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects numeric literals used directly in code rather than as named
/// constants. Exempt: 0, 1, -1, 2 (common divisors/multipliers), and
/// values used in const declarations.
class NoMagicNumberRule extends AnalyzerRule {
  @override
  String get name => 'no-magic-number';

  @override
  Severity get defaultSeverity => Severity.info;

  static const _allowedInt = {0, 1, -1, 2};
  static final _allowedDouble = {0.0, 1.0};

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      // Skip test files — magic numbers in tests are fine
      if (relativePath.contains('test/')) continue;

      final visitor = _MagicNumberVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _MagicNumberVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _MagicNumberVisitor(this.filePath, this.unit);

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    if (_isExempt(node, node.value ?? 0)) return;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    issues.add(Issue(
      rule: 'no-magic-number',
      message: 'magic number ${node.value} — extract to a named constant',
      file: filePath,
      line: line,
      severity: Severity.info,
    ));
    super.visitIntegerLiteral(node);
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (_isExempt(node, node.value)) return;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    issues.add(Issue(
      rule: 'no-magic-number',
      message: 'magic number ${node.value} — extract to a named constant',
      file: filePath,
      line: line,
      severity: Severity.info,
    ));
    super.visitDoubleLiteral(node);
  }

  bool _isExempt(AstNode node, num value) {
    if (value is int && NoMagicNumberRule._allowedInt.contains(value)) return true;
    if (value is double && NoMagicNumberRule._allowedDouble.contains(value)) return true;

    // Allow in const declarations
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is VariableDeclarationList && (parent.isConst || parent.isFinal)) {
        return true;
      }
      if (parent is VariableDeclaration) {
        parent = parent.parent;
        continue;
      }
      if (parent is NamedExpression || parent is ArgumentList) {
        // Named args like `width: 300` are common in Flutter
        return true;
      }
      if (parent is ListLiteral || parent is SetOrMapLiteral) {
        return true;
      }
      if (parent is DefaultFormalParameter) return true;
      if (parent is ConstructorDeclaration) return true;
      if (parent is Annotation) return true;
      break;
    }
    return false;
  }
}
