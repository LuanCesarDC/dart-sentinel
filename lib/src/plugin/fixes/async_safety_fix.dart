import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

/// Quick fix: inserts `if (!mounted) return;` after the nearest `await`.
class AsyncSafetyFix extends ResolvedCorrectionProducer {
  AsyncSafetyFix({required super.context});

  static const _fix = FixKind(
    'sentinel.fix.asyncSafety.addMountedCheck',
    50,
    'Add mounted check after await',
  );

  @override
  FixKind get fixKind => _fix;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // Find the statement containing the flagged node
    final stmt = _enclosingStatement(node);
    if (stmt == null) return;

    // Walk backward to find the preceding await expression statement
    final parent = stmt.parent;
    if (parent is! Block) return;

    final stmts = parent.statements;
    final idx = stmts.indexOf(stmt);

    // Find the closest preceding await
    ExpressionStatement? awaitStmt;
    for (var i = idx - 1; i >= 0; i--) {
      final s = stmts[i];
      if (s is ExpressionStatement && _containsAwait(s)) {
        awaitStmt = s;
        break;
      }
    }

    final insertAfter = awaitStmt ?? (idx > 0 ? stmts[idx - 1] : null);
    if (insertAfter == null) return;

    final indent = utils.getLinePrefix(stmt.offset);

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(
        insertAfter.end,
        '\n${indent}if (!mounted) return;',
      );
    });
  }

  Statement? _enclosingStatement(AstNode? n) {
    while (n != null) {
      if (n is Statement) return n;
      n = n.parent;
    }
    return null;
  }

  bool _containsAwait(AstNode n) {
    if (n is AwaitExpression) return true;
    for (final child in n.childEntities) {
      if (child is AstNode && _containsAwait(child)) return true;
    }
    return false;
  }
}
