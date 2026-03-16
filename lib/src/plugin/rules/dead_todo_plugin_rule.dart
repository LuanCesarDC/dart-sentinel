import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects TODO/FIXME comments without actionable context.
class DeadTodoPluginRule extends AnalysisRule {
  DeadTodoPluginRule()
    : super(
        name: 'dead_todo',
        description:
            'Detects TODO/FIXME comments without descriptions or context.',
      );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.deadTodo;

  static final _todoPattern = RegExp(
    r'//\s*(TODO|FIXME|HACK|XXX)\b(?:\s*[:(\s]\s*)?(.*)$',
    caseSensitive: false,
  );

  static final _issueRef = RegExp(r'#\d+|b/\d+|go/');
  static final _authorTag = RegExp(r'\([a-zA-Z]+\)');

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final DeadTodoPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Walk all tokens to find comments (comments are attached to tokens)
    var token = node.beginToken;
    final endToken = node.endToken;

    while (true) {
      _checkComments(token.precedingComments);
      if (identical(token, endToken)) break;
      final next = token.next;
      if (next == null) break;
      token = next;
    }
  }

  void _checkComments(Token? comment) {
    while (comment != null) {
      final text = comment.lexeme;
      if (text.startsWith('//')) {
        _checkTodoComment(text, comment.offset, comment.length);
      }
      comment = comment.next;
    }
  }

  void _checkTodoComment(String text, int offset, int length) {
    final match = DeadTodoPluginRule._todoPattern.firstMatch(text);
    if (match == null) return;

    final body = match.group(2)?.trim() ?? '';

    if (body.isEmpty) {
      rule.reportAtOffset(
        offset,
        length,
        arguments: ['TODO without description — add context or remove.'],
      );
      return;
    }

    if (DeadTodoPluginRule._issueRef.hasMatch(body)) return;
    if (DeadTodoPluginRule._authorTag.hasMatch(body)) return;

    final words = body.split(RegExp(r'\s+')).where((w) => w.length > 1);
    if (words.length < 3) {
      rule.reportAtOffset(
        offset,
        length,
        arguments: ["TODO lacks actionable context: '$body'"],
      );
    }
  }
}
