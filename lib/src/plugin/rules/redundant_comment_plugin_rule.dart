import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';

/// Plugin rule: detects comments that just restate what the code does.
class RedundantCommentPluginRule extends AnalysisRule {
  RedundantCommentPluginRule()
      : super(
          name: 'redundant_comment',
          description: 'Detects comments that restate the code.',
        );

  @override
  DiagnosticCode get diagnosticCode => SentinelCodes.redundantComment;

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

  static const _stopWords = {
    'a', 'an', 'the', 'is', 'to', 'of', 'in', 'for', 'on', 'at',
    'by', 'and', 'or', 'if', 'it', 'as', 'be', 'do', 'no', 'so',
    'up', 'we', 'my', 'me', 'he', 'am',
  };

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final RedundantCommentPluginRule rule;
  _Visitor(this.rule);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    var token = node.beginToken;
    final endToken = node.endToken;

    while (true) {
      _checkComments(token.precedingComments, token);
      if (identical(token, endToken)) break;
      final next = token.next;
      if (next == null) break;
      token = next;
    }
  }

  void _checkComments(Token? comment, Token codeToken) {
    while (comment != null) {
      final text = comment.lexeme;
      if (text.startsWith('//') &&
          !text.startsWith('///') &&
          !RegExp(r'^//\s*(TODO|FIXME|HACK|XXX)\b', caseSensitive: false).hasMatch(text)) {
        if (RedundantCommentPluginRule._trivialPatterns.any((p) => p.hasMatch(text))) {
          // Check overlap with the next code token's text
          final codeText = codeToken.lexeme;
          if (_hasHighOverlap(text, codeText)) {
            rule.reportAtOffset(comment.offset, comment.length);
          }
        }
      }
      comment = comment.next;
    }
  }

  bool _hasHighOverlap(String comment, String codeLine) {
    final commentWords = _extractWords(comment.replaceFirst(RegExp(r'^//\s*'), ''));
    final codeWords = _extractWords(codeLine);
    if (commentWords.isEmpty || codeWords.isEmpty) return false;
    final matches = commentWords.where((w) => codeWords.contains(w)).length;
    return matches >= 2 || (commentWords.length <= 3 && matches >= 1);
  }

  Set<String> _extractWords(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .where((w) => !RedundantCommentPluginRule._stopWords.contains(w))
        .toSet();
  }
}
