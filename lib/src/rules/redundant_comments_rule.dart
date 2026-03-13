import 'package:analyzer/dart/ast/ast.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects comments that repeat what the code already says.
///
/// Flags patterns like:
/// - `// Create a list of strings` before `final items = <String>[];`
/// - `// Return the result` before `return result;`
/// - `// Loop through items` before `for (final item in items)`
class RedundantCommentsRule extends AnalyzerRule {
  @override
  String get name => 'redundant-comments';

  @override
  Severity get defaultSeverity => Severity.info;

  /// Patterns that indicate a comment is just restating the code.
  static final _trivialPatterns = [
    RegExp(r'^//\s*(create|initialize|init)\s+(a|an|the|new)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(return|returns)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(set|sets)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(get|gets)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(loop|iterate|go)\s+(through|over|for)\s+', caseSensitive: false),
    RegExp(r'^//\s*(check|validate)\s+(if|that|the|whether)\s+', caseSensitive: false),
    RegExp(r'^//\s*(call|invoke)\s+(the|a)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(add|append|push|insert)\s+(the|a|an|new)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(remove|delete|drop)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(import|export|include)\s+', caseSensitive: false),
    RegExp(r'^//\s*(this|the)\s+(method|function|class|variable|field)\s+', caseSensitive: false),
    RegExp(r'^//\s*(constructor|destructor|dispose|getter|setter)\s*$', caseSensitive: false),
  ];

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      issues.addAll(_checkUnit(entry.value, relativePath));
    }
    return issues;
  }

  List<Issue> _checkUnit(CompilationUnit unit, String filePath) {
    final issues = <Issue>[];
    final source = unit.toSource();
    final lines = source.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip non-comment lines and doc comments
      if (!line.startsWith('//') || line.startsWith('///')) continue;

      // Skip TODOs, FIXMEs (handled by dead-todos)
      if (RegExp(r'^//\s*(TODO|FIXME|HACK|XXX)\b', caseSensitive: false)
          .hasMatch(line)) continue;

      if (!_matchesTrivialPattern(line)) continue;

      // Check if the comment's identifiers overlap with the next code line
      final nextCodeLine = _nextNonCommentLine(lines, i);
      if (nextCodeLine != null && _hasHighOverlap(line, nextCodeLine)) {
        issues.add(Issue(
          rule: name,
          message: 'Comment restates the code — remove or add insight.',
          file: filePath,
          line: i + 1,
          severity: defaultSeverity,
        ));
      }
    }
    return issues;
  }

  bool _matchesTrivialPattern(String line) {
    return _trivialPatterns.any((p) => p.hasMatch(line));
  }

  String? _nextNonCommentLine(List<String> lines, int fromIndex) {
    for (var i = fromIndex + 1; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('//')) continue;
      return trimmed;
    }
    return null;
  }

  bool _hasHighOverlap(String comment, String codeLine) {
    final commentWords = _extractWords(comment.replaceFirst(RegExp(r'^//\s*'), ''));
    final codeWords = _extractWords(codeLine);

    if (commentWords.isEmpty || codeWords.isEmpty) return false;

    final matches = commentWords.where((w) => codeWords.contains(w)).length;
    return matches >= 2 || (commentWords.length <= 3 && matches >= 1);
  }

  Set<String> _extractWords(String text) {
    return RegExp(r'[a-zA-Z]{2,}')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((w) => !_stopWords.contains(w))
        .toSet();
  }

  static const _stopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
    'this', 'that', 'it', 'if', 'then', 'else', 'new', 'var',
    'final', 'const', 'void', 'null', 'true', 'false', 'int',
    'string', 'double', 'bool', 'list', 'map', 'set', 'async',
    'await', 'return', 'class', 'each', 'all', 'and', 'or',
  };
}
