import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects function/method calls where the same argument expression
/// is passed to two different parameters.
class NoEqualArgumentsRule extends AnalyzerRule {
  @override
  String get name => 'no-equal-arguments';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      final visitor = _EqualArgsVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _EqualArgsVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _EqualArgsVisitor(this.filePath, this.unit);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _checkArgs(node.argumentList, node.methodName.name, node.offset);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _checkArgs(node.argumentList, node.function.toSource(), node.offset);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _checkArgs(
      node.argumentList,
      node.constructorName.toSource(),
      node.offset,
    );
    super.visitInstanceCreationExpression(node);
  }

  void _checkArgs(ArgumentList argList, String callName, int offset) {
    final args = argList.arguments;
    if (args.length < 2) return;

    // Only check positional args (named args are self-documenting)
    final positional = args.where((a) => a is! NamedExpression).toList();
    if (positional.length < 2) return;

    final seen = <String>{};
    for (final arg in positional) {
      final source = arg.toSource();
      // Skip simple literals — `null`, `true`, `false`, `0`, `1`, `''`
      if (_isTrivialLiteral(source)) continue;

      if (!seen.add(source)) {
        final line = unit.lineInfo.getLocation(offset).lineNumber;
        issues.add(Issue(
          rule: 'no-equal-arguments',
          message:
              'same argument "$source" passed twice to "$callName"',
          file: filePath,
          line: line,
          severity: Severity.warning,
        ));
        break;
      }
    }
  }

  bool _isTrivialLiteral(String source) {
    return source == 'null' ||
        source == 'true' ||
        source == 'false' ||
        source == '0' ||
        source == '1' ||
        source == "''" ||
        source == '""';
  }
}
