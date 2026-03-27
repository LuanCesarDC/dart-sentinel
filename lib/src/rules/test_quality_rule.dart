import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Analyzes test files for common anti-patterns:
///
/// - empty-test: test body with no statements
/// - no-assertion: test that runs code but never calls expect/verify/throwsA
/// - test-too-long: test with >50 lines
/// - duplicate-test-name: two tests with the same name in the same file
/// - skipped-test: test with skip: parameter
class TestQualityRule extends AnalyzerRule {
  @override
  String get name => 'test-quality';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;

      // Only analyze test files
      final relativePath = context.relativePath(file);
      if (!relativePath.contains('test/')) continue;
      if (!relativePath.endsWith('_test.dart')) continue;

      final visitor = _TestQualityVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _TestQualityVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];
  final List<String> _testNames = [];

  _TestQualityVisitor(this.filePath, this.unit);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name != 'test' && name != 'testWidgets') {
      super.visitMethodInvocation(node);
      return;
    }

    final args = node.argumentList.arguments;
    if (args.isEmpty) {
      super.visitMethodInvocation(node);
      return;
    }

    // Get test name
    final nameArg = args.first;
    String? testName;
    if (nameArg is StringLiteral) {
      testName = nameArg.stringValue;
    }

    final line = unit.lineInfo.getLocation(node.offset).lineNumber;

    // Check for skipped tests
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == 'skip') {
        issues.add(
          Issue(
            rule: 'test-quality',
            message: "test '${testName ?? '?'}' is skipped",
            file: filePath,
            line: line,
            severity: Severity.warning,
          ),
        );
      }
    }

    // Check for duplicate test names
    if (testName != null) {
      if (_testNames.contains(testName)) {
        issues.add(
          Issue(
            rule: 'test-quality',
            message: "duplicate test name: '$testName'",
            file: filePath,
            line: line,
            severity: Severity.warning,
          ),
        );
      }
      _testNames.add(testName);
    }

    // Find the callback argument (Function/closure)
    Expression? callback;
    for (final arg in args) {
      if (arg is FunctionExpression) {
        callback = arg;
        break;
      }
      if (arg is NamedExpression && arg.expression is FunctionExpression) {
        callback = arg.expression;
        break;
      }
    }
    // Also check second positional arg
    if (callback == null && args.length >= 2 && args[1] is FunctionExpression) {
      callback = args[1] as FunctionExpression;
    }

    if (callback is FunctionExpression) {
      final body = callback.body;

      // Check empty test
      if (body is BlockFunctionBody) {
        final block = body.block;
        if (block.statements.isEmpty) {
          issues.add(
            Issue(
              rule: 'test-quality',
              message: "test '${testName ?? '?'}' has an empty body",
              file: filePath,
              line: line,
              severity: Severity.warning,
            ),
          );
        } else {
          // Check for no assertions
          final assertionChecker = _AssertionChecker();
          body.accept(assertionChecker);
          if (!assertionChecker.hasAssertion) {
            issues.add(
              Issue(
                rule: 'test-quality',
                message: "test '${testName ?? '?'}' has no assertions",
                file: filePath,
                line: line,
                severity: Severity.warning,
              ),
            );
          }

          // Check test length
          final bodySource = body.toSource();
          final bodyLines = bodySource.split('\n').length;
          if (bodyLines > 50) {
            issues.add(
              Issue(
                rule: 'test-quality',
                message:
                    "test '${testName ?? '?'}' is $bodyLines lines long "
                    '(consider splitting, max: 50)',
                file: filePath,
                line: line,
                severity: Severity.info,
              ),
            );
          }
        }
      }
    }

    super.visitMethodInvocation(node);
  }
}

class _AssertionChecker extends RecursiveAstVisitor<void> {
  bool hasAssertion = false;

  static const _assertionNames = {
    'expect',
    'expectLater',
    'verify',
    'verifyNever',
    'verifyInOrder',
    'throwsA',
    'expectAsync0',
    'expectAsync1',
    'expectAsync2',
    'fail',
    'check',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_assertionNames.contains(node.methodName.name)) {
      hasAssertion = true;
    }
    super.visitMethodInvocation(node);
  }
}
