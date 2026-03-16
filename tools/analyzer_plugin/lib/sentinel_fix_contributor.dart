import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';

/// Provides quick fixes for Sentinel diagnostics.
///
/// Unlike the standard FixContributor pattern, this works with custom plugin
/// diagnostics rather than analyzer diagnostics.
class SentinelFixContributor {
  final List<SentinelDiagnostic> diagnostics;
  SentinelFixContributor(this.diagnostics);

  /// Compute fixes for diagnostics at [offset] in the given [result].
  Future<List<AnalysisErrorFixes>> computeFixes(
    ResolvedUnitResult result,
    int offset,
  ) async {
    final line = result.lineInfo.getLocation(offset).lineNumber;
    final fixes = <AnalysisErrorFixes>[];

    for (final diag in diagnostics) {
      final diagLine = result.lineInfo.getLocation(diag.offset).lineNumber;
      if (diagLine != line) continue;

      final diagFixes = await _fixesForDiagnostic(diag, result);
      if (diagFixes.isEmpty) continue;

      final loc = _location(result, diag.offset, diag.length);
      final severity =
          diag.code == 'empty_catch' || diag.code == 'empty_catch_print_only'
          ? protocol.AnalysisErrorSeverity.WARNING
          : protocol.AnalysisErrorSeverity.INFO;

      fixes.add(
        AnalysisErrorFixes(
          protocol.AnalysisError(
            severity,
            protocol.AnalysisErrorType.LINT,
            loc,
            diag.message,
            diag.code,
            hasFix: true,
          ),
          fixes: diagFixes,
        ),
      );
    }

    return fixes;
  }

  Future<List<PrioritizedSourceChange>> _fixesForDiagnostic(
    SentinelDiagnostic diag,
    ResolvedUnitResult result,
  ) async {
    switch (diag.code) {
      case 'empty_catch':
        return _fixEmptyCatch(diag, result);
      case 'dead_todo':
        return _fixRemoveLine(diag, result, 'Remove dead TODO');
      case 'redundant_comment':
        return _fixRemoveLine(diag, result, 'Remove redundant comment');
      case 'verbose_logging':
        return _fixVerboseLogging(diag, result);
      default:
        return [];
    }
  }

  /// Fix: add `rethrow;` to empty catch block.
  Future<List<PrioritizedSourceChange>> _fixEmptyCatch(
    SentinelDiagnostic diag,
    ResolvedUnitResult result,
  ) async {
    final content = result.content;
    // Find the opening `{` of the catch body after the diagnostic offset
    final catchOffset = diag.offset;
    var braceIdx = content.indexOf('{', catchOffset);
    if (braceIdx < 0) return [];

    // Find the matching `}`
    var closeIdx = content.indexOf('}', braceIdx + 1);
    if (closeIdx < 0) return [];

    // Compute indentation
    var lineStart = braceIdx;
    while (lineStart > 0 && content[lineStart - 1] != '\n') {
      lineStart--;
    }
    final indent = content
        .substring(lineStart, braceIdx)
        .replaceAll(RegExp(r'\S.*'), '');

    final builder = ChangeBuilder(session: result.session);
    await builder.addDartFileEdit(result.path, (fileBuilder) {
      fileBuilder.addSimpleReplacement(
        SourceRange(braceIdx, closeIdx - braceIdx + 1),
        '{\n$indent  rethrow;\n$indent}',
      );
    });

    return [
      PrioritizedSourceChange(
        50,
        builder.sourceChange..message = 'Add rethrow',
      ),
    ];
  }

  /// Fix: remove the entire line containing the diagnostic.
  Future<List<PrioritizedSourceChange>> _fixRemoveLine(
    SentinelDiagnostic diag,
    ResolvedUnitResult result,
    String message,
  ) async {
    final content = result.content;
    var lineStart = diag.offset;
    while (lineStart > 0 && content[lineStart - 1] != '\n') {
      lineStart--;
    }
    var lineEnd = diag.offset;
    while (lineEnd < content.length && content[lineEnd] != '\n') {
      lineEnd++;
    }
    if (lineEnd < content.length) lineEnd++; // include \n

    final builder = ChangeBuilder(session: result.session);
    await builder.addDartFileEdit(result.path, (fileBuilder) {
      fileBuilder.addDeletion(SourceRange(lineStart, lineEnd - lineStart));
    });

    return [
      PrioritizedSourceChange(50, builder.sourceChange..message = message),
    ];
  }

  /// Fix: combine consecutive prints into a single structured print.
  Future<List<PrioritizedSourceChange>> _fixVerboseLogging(
    SentinelDiagnostic diag,
    ResolvedUnitResult result,
  ) async {
    final content = result.content;
    final rangeEnd = diag.endOffset ?? (diag.offset + diag.length);

    // Find all lines in the range
    var regionStart = diag.offset;
    while (regionStart > 0 && content[regionStart - 1] != '\n') {
      regionStart--;
    }
    var regionEnd = rangeEnd;
    while (regionEnd < content.length && content[regionEnd] != '\n') {
      regionEnd++;
    }
    if (regionEnd < content.length) regionEnd++; // include \n

    final region = content.substring(regionStart, regionEnd);
    final lines = region.split('\n').where((l) => l.trim().isNotEmpty).toList();

    // Extract the argument from each print/debugPrint/log call
    final args = <String>[];
    final printPattern = RegExp(
      r'^\s*(?:print|debugPrint|log|logger\.\w+)\((.+)\);\s*$',
    );
    for (final line in lines) {
      final match = printPattern.firstMatch(line);
      if (match != null) {
        args.add(match.group(1)!.trim());
      }
    }

    if (args.isEmpty) return [];

    // Compute indentation from first line
    final indentMatch = RegExp(r'^(\s*)').firstMatch(lines.first);
    final indent = indentMatch?.group(1) ?? '  ';

    // Build replacement: print([...].join('\n'))
    final buffer = StringBuffer();
    buffer.writeln('${indent}print([');
    for (var i = 0; i < args.length; i++) {
      final comma = i < args.length - 1 ? ',' : ',';
      buffer.writeln('$indent  ${args[i]}$comma');
    }
    buffer.write("$indent].join('\\n'));");

    final builder = ChangeBuilder(session: result.session);
    await builder.addDartFileEdit(result.path, (fileBuilder) {
      fileBuilder.addSimpleReplacement(
        SourceRange(regionStart, regionEnd - regionStart),
        '${buffer.toString()}\n',
      );
    });

    return [
      PrioritizedSourceChange(
        50,
        builder.sourceChange..message = 'Combine into single print',
      ),
    ];
  }

  protocol.Location _location(
    ResolvedUnitResult result,
    int offset,
    int length,
  ) {
    final lineInfo = result.lineInfo;
    final start = lineInfo.getLocation(offset);
    final end = lineInfo.getLocation(offset + length);
    return protocol.Location(
      result.path,
      offset,
      length,
      start.lineNumber,
      start.columnNumber,
      endLine: end.lineNumber,
      endColumn: end.columnNumber,
    );
  }
}

/// Represents a diagnostic reported by the plugin.
class SentinelDiagnostic {
  final String code;
  final int offset;
  final int length;
  final String message;

  /// For diagnostics spanning multiple statements (e.g. verbose_logging),
  /// the end offset of the last statement in the range.
  final int? endOffset;

  const SentinelDiagnostic({
    required this.code,
    required this.offset,
    required this.length,
    required this.message,
    this.endOffset,
  });
}
