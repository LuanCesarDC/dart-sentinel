import 'package:analyzer/dart/ast/ast.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects TODO/FIXME/HACK comments without actionable context.
class DeadTodosRule extends AnalyzerRule {
  @override
  String get name => 'dead-todos';

  @override
  Severity get defaultSeverity => Severity.info;

  static final _todoPattern = RegExp(
    r'//\s*(TODO|FIXME|HACK|XXX)\b[:\s]*(.*)',
    caseSensitive: false,
  );

  static final _issueRef = RegExp(r'#\d+');
  static final _authorTag = RegExp(r'\(\w+\)');

  @override
  List<Issue> run(ProjectContext context) {
    final config = context.config.aiSlop.deadTodos;
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final relativePath = context.relativePath(entry.key);
      issues.addAll(_checkUnit(entry.value, relativePath, config));
    }
    return issues;
  }

  List<Issue> _checkUnit(
    CompilationUnit unit, String filePath, DeadTodosConfig config,
  ) {
    final issues = <Issue>[];
    final source = unit.toSource();
    final lines = source.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final match = _todoPattern.firstMatch(lines[i]);
      if (match == null) continue;

      final tag = match.group(1)!.toUpperCase();
      final body = match.group(2)?.trim() ?? '';

      if (_isActionable(body, config)) continue;

      final lineNum = i + 1;
      issues.add(Issue(
        rule: name,
        message: body.isEmpty
            ? '$tag without description — add context or remove.'
            : '$tag lacks actionable context: "$body"',
        file: filePath,
        line: lineNum,
        severity: defaultSeverity,
      ));
    }
    return issues;
  }

  bool _isActionable(String body, DeadTodosConfig config) {
    if (body.isEmpty) return false;

    // Has issue reference (#123) or author tag (luan)
    if (_issueRef.hasMatch(body) || _authorTag.hasMatch(body)) return true;

    // Check minimum word count
    final words = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length < config.minContextWords) return false;

    // Check for vague phrases
    final lower = body.toLowerCase();
    for (final phrase in config.vaguePhrases) {
      if (lower.contains(phrase)) return false;
    }

    return true;
  }
}
