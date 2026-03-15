import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

/// Quick fix: removes a dead TODO comment line.
class DeadTodoFix extends ResolvedCorrectionProducer {
  DeadTodoFix({required super.context});

  static const _fix = FixKind(
    'sentinel.fix.deadTodo.remove',
    50,
    'Remove dead TODO',
  );

  @override
  FixKind get fixKind => _fix;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final d = diagnostic;
    if (d == null) return;

    final offset = d.problemMessage.offset;
    final content = unitResult.content;

    // Find start of the line
    var lineStart = offset;
    while (lineStart > 0 && content[lineStart - 1] != '\n') {
      lineStart--;
    }

    // Find end of the line (including newline)
    var lineEnd = offset;
    while (lineEnd < content.length && content[lineEnd] != '\n') {
      lineEnd++;
    }
    if (lineEnd < content.length) lineEnd++; // include the \n

    await builder.addDartFileEdit(file, (builder) {
      builder.addDeletion(SourceRange(lineStart, lineEnd - lineStart));
    });
  }
}
