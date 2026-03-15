import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

/// Quick fix: adds `rethrow;` inside an empty catch block.
class EmptyCatchFix extends ResolvedCorrectionProducer {
  EmptyCatchFix({required super.context});

  static const _fix = FixKind(
    'sentinel.fix.emptyCatch.addRethrow',
    50,
    'Add rethrow',
  );

  @override
  FixKind get fixKind => _fix;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final catchNode = _findCatchClause(node);
    if (catchNode == null) return;

    final body = catchNode.body;
    final indent = utils.getLinePrefix(catchNode.offset);

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(body.leftBracket.offset, body.length),
        '{\n$indent  rethrow;\n$indent}',
      );
    });
  }

  CatchClause? _findCatchClause(AstNode? n) {
    while (n != null) {
      if (n is CatchClause) return n;
      n = n.parent;
    }
    return null;
  }
}
