import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer_plugin/plugin/plugin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_generated.dart';

import 'sentinel_fix_contributor.dart';

/// Old-style analyzer plugin for Dart SDK < 3.10.
///
/// Uses the `analyzer_plugin` API (tool/analyzer_plugin/ bootstrap)
/// to report diagnostics and provide quick fixes in the IDE.
class SentinelPlugin extends ServerPlugin {
  /// Tracks the diagnostics we sent per file so we can provide fixes.
  final Map<String, List<SentinelDiagnostic>> _diagnosticsByFile = {};

  SentinelPlugin({required ResourceProvider resourceProvider})
    : super(resourceProvider: resourceProvider);

  @override
  String get name => 'dart_sentinel';

  @override
  String get version => '1.0.0';

  @override
  List<String> get fileGlobsToAnalyze => ['**/*.dart'];

  // ── Analysis ──────────────────────────────────────────

  @override
  Future<void> analyzeFile({
    required AnalysisContext analysisContext,
    required String path,
  }) async {
    if (!path.endsWith('.dart')) return;

    final result = await analysisContext.currentSession.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) return;

    final diagnostics = <SentinelDiagnostic>[];
    final errors = <protocol.AnalysisError>[];

    // Run all checks
    _checkEmptyCatch(result, path, diagnostics, errors);
    _checkDeadTodo(result, path, diagnostics, errors);
    _checkGenericNaming(result, path, diagnostics, errors);
    _checkSingleMethodClass(result, path, diagnostics, errors);
    _checkVerboseLogging(result, path, diagnostics, errors);
    _checkPassthroughFunction(result, path, diagnostics, errors);
    _checkRedundantComment(result, path, diagnostics, errors);
    _checkLazyNullCheck(result, path, diagnostics, errors);

    _diagnosticsByFile[path] = diagnostics;

    channel.sendNotification(
      AnalysisErrorsParams(path, errors).toNotification(),
    );
  }

  // ── Fixes ─────────────────────────────────────────────

  @override
  Future<EditGetFixesResult> handleEditGetFixes(
    EditGetFixesParams parameters,
  ) async {
    final path = parameters.file;
    final result = await getResolvedUnitResult(path);
    final diags = _diagnosticsByFile[path] ?? [];
    final contributor = SentinelFixContributor(diags);
    final fixes = await contributor.computeFixes(result, parameters.offset);
    return EditGetFixesResult(fixes);
  }

  // ── Check: empty_catch ────────────────────────────────

  void _checkEmptyCatch(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _EmptyCatchVisitor((node, code, message, correction) {
        final loc = _location(result, node.offset, node.length);
        diagnostics.add(
          SentinelDiagnostic(
            code: code,
            offset: node.offset,
            length: node.length,
            message: message,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.WARNING,
            protocol.AnalysisErrorType.LINT,
            loc,
            message,
            code,
            correction: correction,
            hasFix: code == 'empty_catch',
          ),
        );
      }),
    );
  }

  // ── Check: dead_todo ──────────────────────────────────

  void _checkDeadTodo(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    _walkComments(result.unit, (text, offset, length) {
      final match = _todoPattern.firstMatch(text);
      if (match == null) return;
      final tag = match.group(1)!.toUpperCase();
      final body = match.group(2)?.trim() ?? '';
      if (_isTodoActionable(body)) return;

      final msg = body.isEmpty
          ? '$tag without description — add context or remove.'
          : '$tag lacks actionable context: "$body"';
      final loc = _location(result, offset, length);
      diagnostics.add(
        SentinelDiagnostic(
          code: 'dead_todo',
          offset: offset,
          length: length,
          message: msg,
        ),
      );
      errors.add(
        protocol.AnalysisError(
          protocol.AnalysisErrorSeverity.INFO,
          protocol.AnalysisErrorType.LINT,
          loc,
          msg,
          'dead_todo',
          correction:
              'Add actionable context (issue ref, author, or 3+ words).',
          hasFix: true,
        ),
      );
    });
  }

  static final _todoPattern = RegExp(
    r'//\s*(TODO|FIXME|HACK|XXX)\b[:\s]*(.*)',
    caseSensitive: false,
  );
  static final _issueRef = RegExp(r'#\d+|b/\d+|go/\w+');
  static final _authorTag = RegExp(r'\(\w+\)');

  bool _isTodoActionable(String body) {
    if (body.isEmpty) return false;
    if (_issueRef.hasMatch(body) || _authorTag.hasMatch(body)) return true;
    final words = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.length >= 3;
  }

  // ── Check: generic_naming ─────────────────────────────

  void _checkGenericNaming(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _GenericNamingVisitor((node, message) {
        // Extract name token offset for accurate highlighting
        final int nameOffset;
        final int nameLength;
        if (node is VariableDeclaration) {
          nameOffset = node.name.offset;
          nameLength = node.name.length;
        } else if (node is SimpleFormalParameter) {
          nameOffset = node.name!.offset;
          nameLength = node.name!.length;
        } else if (node is FunctionDeclaration) {
          nameOffset = node.name.offset;
          nameLength = node.name.length;
        } else if (node is MethodDeclaration) {
          nameOffset = node.name.offset;
          nameLength = node.name.length;
        } else {
          nameOffset = node.offset;
          nameLength = node.length;
        }
        final loc = _location(result, nameOffset, nameLength);
        diagnostics.add(
          SentinelDiagnostic(
            code: 'generic_naming',
            offset: nameOffset,
            length: nameLength,
            message: message,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.WARNING,
            protocol.AnalysisErrorType.LINT,
            loc,
            message,
            'generic_naming',
            correction: 'Use a more descriptive name.',
          ),
        );
      }),
    );
  }

  // ── Check: single_method_class ────────────────────────

  void _checkSingleMethodClass(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _SingleMethodClassVisitor((nameToken, className, methodName) {
        final msg =
            "Class '$className' has only one public method '$methodName' "
            "— consider using a plain function instead.";
        final loc = _location(result, nameToken.offset, nameToken.length);
        diagnostics.add(
          SentinelDiagnostic(
            code: 'single_method_class',
            offset: nameToken.offset,
            length: nameToken.length,
            message: msg,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.INFO,
            protocol.AnalysisErrorType.LINT,
            loc,
            msg,
            'single_method_class',
          ),
        );
      }),
    );
  }

  // ── Check: verbose_logging ────────────────────────────

  void _checkVerboseLogging(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _VerboseLoggingVisitor((first, last, count) {
        final msg =
            '$count consecutive log statements — '
            'consider a single structured log or removing debug noise.';
        final rangeLength = last.end - first.offset;
        final loc = _location(result, first.offset, rangeLength);
        diagnostics.add(
          SentinelDiagnostic(
            code: 'verbose_logging',
            offset: first.offset,
            length: rangeLength,
            message: msg,
            endOffset: last.end,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.INFO,
            protocol.AnalysisErrorType.LINT,
            loc,
            msg,
            'verbose_logging',
            hasFix: true,
          ),
        );
      }),
    );
  }

  // ── Check: passthrough_function ───────────────────────

  void _checkPassthroughFunction(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _PassthroughVisitor((node, delegateName) {
        final name = node is FunctionDeclaration
            ? node.name.lexeme
            : (node as MethodDeclaration).name.lexeme;
        final msg =
            "'$name' only delegates to '$delegateName' with the same "
            "arguments — consider calling '$delegateName' directly.";
        final loc = _location(result, node.offset, node.length);
        diagnostics.add(
          SentinelDiagnostic(
            code: 'passthrough_function',
            offset: node.offset,
            length: node.length,
            message: msg,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.INFO,
            protocol.AnalysisErrorType.LINT,
            loc,
            msg,
            'passthrough_function',
          ),
        );
      }),
    );
  }

  // ── Check: redundant_comment ──────────────────────────

  void _checkRedundantComment(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    _walkComments(result.unit, (text, offset, length) {
      final trimmed = text.trim();
      if (!trimmed.startsWith('//') || trimmed.startsWith('///')) return;
      if (RegExp(
        r'^//\s*(TODO|FIXME|HACK|XXX)\b',
        caseSensitive: false,
      ).hasMatch(trimmed))
        return;
      if (!_matchesTrivialPattern(trimmed)) return;

      final msg = 'Comment restates the code — remove or add insight.';
      final loc = _location(result, offset, length);
      diagnostics.add(
        SentinelDiagnostic(
          code: 'redundant_comment',
          offset: offset,
          length: length,
          message: msg,
        ),
      );
      errors.add(
        protocol.AnalysisError(
          protocol.AnalysisErrorSeverity.INFO,
          protocol.AnalysisErrorType.LINT,
          loc,
          msg,
          'redundant_comment',
          correction: 'Remove the comment or add meaningful insight.',
          hasFix: true,
        ),
      );
    });
  }

  static final _trivialPatterns = [
    RegExp(
      r'^//\s*(create|initialize|init)\s+(a|an|the|new)?\s*',
      caseSensitive: false,
    ),
    RegExp(r'^//\s*(return|returns)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(set|sets)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(r'^//\s*(get|gets)\s+(the|a|an)?\s*', caseSensitive: false),
    RegExp(
      r'^//\s*(loop|iterate|go)\s+(through|over|for)\s+',
      caseSensitive: false,
    ),
    RegExp(
      r'^//\s*(check|validate)\s+(if|that|the|whether)\s+',
      caseSensitive: false,
    ),
    RegExp(r'^//\s*(call|invoke)\s+(the|a)?\s*', caseSensitive: false),
    RegExp(
      r'^//\s*(add|append|push|insert)\s+(the|a|an|new)?\s*',
      caseSensitive: false,
    ),
    RegExp(
      r'^//\s*(remove|delete|drop)\s+(the|a|an)?\s*',
      caseSensitive: false,
    ),
  ];

  bool _matchesTrivialPattern(String line) =>
      _trivialPatterns.any((p) => p.hasMatch(line));

  // ── Check: lazy_null_check ────────────────────────────

  void _checkLazyNullCheck(
    ResolvedUnitResult result,
    String path,
    List<SentinelDiagnostic> diagnostics,
    List<protocol.AnalysisError> errors,
  ) {
    result.unit.visitChildren(
      _LazyNullCheckVisitor((node, defaultValue) {
        final msg =
            'Lazy null check: `?? $defaultValue` silently swallows null — '
            'consider handling the null case explicitly.';
        final loc = _location(result, node.offset, node.length);
        diagnostics.add(
          SentinelDiagnostic(
            code: 'lazy_null_check',
            offset: node.offset,
            length: node.length,
            message: msg,
          ),
        );
        errors.add(
          protocol.AnalysisError(
            protocol.AnalysisErrorSeverity.WARNING,
            protocol.AnalysisErrorType.LINT,
            loc,
            msg,
            'lazy_null_check',
            correction:
                'Handle the null case explicitly instead of defaulting to an '
                'empty value.',
            hasFix: false,
          ),
        );
      }),
    );
  }

  // ── Helpers ───────────────────────────────────────────

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

  /// Walk all comment tokens in the compilation unit.
  void _walkComments(
    CompilationUnit unit,
    void Function(String text, int offset, int length) callback,
  ) {
    Token? token = unit.beginToken;
    while (token != null && !token.isEof) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        callback(comment.lexeme, comment.offset, comment.length);
        comment = comment.next;
      }
      token = token.next;
    }
  }
}

// ── AST Visitors ────────────────────────────────────────

typedef _ReportCatch =
    void Function(AstNode node, String code, String message, String correction);

class _EmptyCatchVisitor extends RecursiveAstVisitor<void> {
  final _ReportCatch report;
  _EmptyCatchVisitor(this.report);

  @override
  void visitCatchClause(CatchClause node) {
    final stmts = node.body.statements;
    if (stmts.isEmpty) {
      if (_hasComment(node.body)) {
        super.visitCatchClause(node);
        return;
      }
      report(
        node,
        'empty_catch',
        'Empty catch block swallows the exception silently.',
        'Add error handling or rethrow.',
      );
    } else if (_isPrintOnly(stmts)) {
      report(
        node,
        'empty_catch_print_only',
        'Catch block only prints the error — consider logging with context or rethrowing.',
        'Add proper error handling.',
      );
    }
    super.visitCatchClause(node);
  }

  bool _isPrintOnly(List<Statement> stmts) {
    if (stmts.length != 1) return false;
    final stmt = stmts.first;
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;
    if (expr is! MethodInvocation) return false;
    return expr.methodName.name == 'print' ||
        expr.methodName.name == 'debugPrint';
  }

  bool _hasComment(Block body) {
    var token = body.leftBracket.next;
    final end = body.rightBracket;
    while (token != null && token != end) {
      if (token.precedingComments != null) return true;
      token = token.next;
    }
    return end.precedingComments != null;
  }
}

typedef _ReportNode = void Function(AstNode node, String message);

class _GenericNamingVisitor extends RecursiveAstVisitor<void> {
  final _ReportNode report;
  _GenericNamingVisitor(this.report);

  static const _genericVarNames = {
    'data',
    'item',
    'element',
    'info',
    'temp',
    'tmp',
    'obj',
    'object',
    'thing',
    'stuff',
    'foo',
    'bar',
    'baz',
    'input',
    'output',
    'result',
    'value',
    'val',
  };
  static const _genericFuncNames = {
    'handle',
    'process',
    'execute',
    'run',
    'do',
    'doStuff',
    'doSomething',
    'doWork',
    'doIt',
    'manage',
    'perform',
  };

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.lexeme;
    if (_genericVarNames.contains(name)) {
      // Skip if inside for-loop variable
      if (node.parent?.parent is ForStatement) {
        super.visitVariableDeclaration(node);
        return;
      }
      report(
        node,
        'Generic variable name "$name" — use a more descriptive name.',
      );
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final name = node.name?.lexeme;
    if (name != null && _genericVarNames.contains(name)) {
      // Skip lambda/closure params
      if (_isInLambda(node)) {
        super.visitSimpleFormalParameter(node);
        return;
      }
      report(
        node,
        'Generic parameter name "$name" — use a more descriptive name.',
      );
    }
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (_genericFuncNames.contains(name)) {
      report(
        node,
        'Generic function name "$name" — use a more descriptive name.',
      );
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (_genericFuncNames.contains(name)) {
      report(
        node,
        'Generic method name "$name" — use a more descriptive name.',
      );
    }
    super.visitMethodDeclaration(node);
  }

  bool _isInLambda(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionExpression &&
          current.parent is! FunctionDeclaration)
        return true;
      if (current is FunctionDeclaration || current is MethodDeclaration) {
        return false;
      }
      current = current.parent;
    }
    return false;
  }
}

typedef _ReportClass =
    void Function(Token nameToken, String className, String methodName);

class _SingleMethodClassVisitor extends RecursiveAstVisitor<void> {
  final _ReportClass report;
  _SingleMethodClassVisitor(this.report);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.abstractKeyword != null) return;
    if (node.extendsClause != null) return;
    if (node.withClause != null) return;
    if (node.implementsClause != null) return;

    final body = node.body;
    if (body is! BlockClassBody) return;
    final publicMethods = body.members
        .whereType<MethodDeclaration>()
        .where((m) => !m.name.lexeme.startsWith('_') && !m.isStatic)
        .toList();
    final publicFields = body.members
        .whereType<FieldDeclaration>()
        .where((f) => !f.isStatic)
        .expand((f) => f.fields.variables)
        .where((v) => !v.name.lexeme.startsWith('_'));

    if (publicMethods.length == 1 && publicFields.isEmpty) {
      // ignore: deprecated_member_use
      report(node.name, node.name.lexeme, publicMethods.first.name.lexeme);
    }
  }
}

class _VerboseLoggingVisitor extends RecursiveAstVisitor<void> {
  final void Function(Statement first, Statement last, int count) report;
  _VerboseLoggingVisitor(this.report);

  static const _logFunctions = {
    'log',
    'print',
    'debugPrint',
    'logger.info',
    'logger.warning',
    'logger.error',
    'logger.fine',
    'logger.severe',
    'logger.shout',
  };

  @override
  void visitBlock(Block node) {
    var count = 0;
    Statement? first;
    Statement? last;
    for (final stmt in node.statements) {
      if (_isLog(stmt)) {
        first ??= stmt;
        last = stmt;
        count++;
      } else {
        if (count >= 3) report(first!, last!, count);
        count = 0;
        first = null;
        last = null;
      }
    }
    if (count >= 3) report(first!, last!, count);
    super.visitBlock(node);
  }

  bool _isLog(Statement stmt) {
    if (stmt is! ExpressionStatement) return false;
    final expr = stmt.expression;
    if (expr is MethodInvocation) {
      final name = expr.methodName.name;
      final target = expr.target;
      if (target != null) {
        return _logFunctions.contains('${target.toSource()}.$name');
      }
      return _logFunctions.contains(name);
    }
    return false;
  }
}

typedef _ReportPassthrough = void Function(AstNode node, String delegateName);

class _PassthroughVisitor extends RecursiveAstVisitor<void> {
  final _ReportPassthrough report;
  _PassthroughVisitor(this.report);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Skip overrides
    for (final annotation in node.metadata) {
      if (annotation.name.name == 'override') return;
    }
    _check(
      node,
      node.functionExpression.parameters,
      node.functionExpression.body,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    for (final annotation in node.metadata) {
      if (annotation.name.name == 'override') return;
    }
    _check(node, node.parameters, node.body);
    super.visitMethodDeclaration(node);
  }

  void _check(AstNode node, FormalParameterList? params, FunctionBody body) {
    if (params == null || params.parameters.isEmpty) return;

    Expression? expr;
    if (body is BlockFunctionBody) {
      final stmts = body.block.statements;
      if (stmts.length != 1) return;
      final single = stmts.first;
      if (single is ReturnStatement) {
        expr = single.expression;
      } else if (single is ExpressionStatement) {
        expr = single.expression;
      }
    } else if (body is ExpressionFunctionBody) {
      expr = body.expression;
    }
    if (expr == null) return;

    MethodInvocation? call;
    if (expr is MethodInvocation) call = expr;
    if (call == null) return;

    final paramNames = params.parameters.map((p) => p.name?.lexeme).toList();
    final args = call.argumentList.arguments;
    if (args.length != paramNames.length) return;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? argName;
      if (arg is SimpleIdentifier) {
        argName = arg.name;
      } else if (arg is NamedExpression) {
        argName = (arg.expression is SimpleIdentifier)
            ? (arg.expression as SimpleIdentifier).name
            : null;
      }
      if (argName == null || argName != paramNames[i]) return;
    }

    final delegateName = call.target != null
        ? '${call.target!.toSource()}.${call.methodName.name}'
        : call.methodName.name;
    report(node, delegateName);
  }
}

class _LazyNullCheckVisitor extends RecursiveAstVisitor<void> {
  final void Function(BinaryExpression node, String defaultValue) report;
  _LazyNullCheckVisitor(this.report);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '??') {
      final lhs = node.leftOperand;

      // Skip idiomatic patterns
      if (lhs is IndexExpression) {
        super.visitBinaryExpression(node);
        return;
      }
      if (_hasNullAwareAccess(lhs)) {
        super.visitBinaryExpression(node);
        return;
      }
      if (lhs is AsExpression && lhs.type.question != null) {
        super.visitBinaryExpression(node);
        return;
      }
      // obj.property ?? default
      if (lhs is PropertyAccess || lhs is PrefixedIdentifier) {
        super.visitBinaryExpression(node);
        return;
      }
      // method() ?? default
      if (lhs is MethodInvocation) {
        super.visitBinaryExpression(node);
        return;
      }

      final rhs = node.rightOperand;
      final match = _matchDefault(rhs);
      if (match != null) {
        report(node, match);
      }
    }
    super.visitBinaryExpression(node);
  }

  bool _hasNullAwareAccess(Expression expr) {
    if (expr is PropertyAccess && expr.isNullAware) return true;
    if (expr is MethodInvocation && expr.isNullAware) return true;
    if (expr is PropertyAccess) return _hasNullAwareAccess(expr.target!);
    if (expr is MethodInvocation && expr.target != null) {
      return _hasNullAwareAccess(expr.target!);
    }
    return false;
  }

  String? _matchDefault(Expression expr) {
    if (expr is SimpleStringLiteral && expr.value.isEmpty) return '""';
    if (expr is IntegerLiteral && expr.value == 0) return '0';
    if (expr is DoubleLiteral && expr.value == 0.0) return '0.0';
    if (expr is BooleanLiteral && !expr.value) return 'false';
    if (expr is ListLiteral && expr.elements.isEmpty) return '[]';
    if (expr is SetOrMapLiteral && expr.elements.isEmpty) return '{}';
    return null;
  }
}
