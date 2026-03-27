import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';

/// Detects common Flutter anti-patterns:
///
/// - `shrinkWrap: true` inside scrollable contexts (ListView, GridView)
/// - `Expanded(child: SizedBox())` instead of `Spacer()`
/// - Creating new Future inline in FutureBuilder (triggers rebuild loops)
/// - `super.initState()` not called first / `super.dispose()` not called last
class FlutterAntiPatternsRule extends AnalyzerRule {
  @override
  String get name => 'flutter-anti-patterns';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final issues = <Issue>[];

    for (final entry in context.parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;
      final relativePath = context.relativePath(file);

      // Only check files that import Flutter
      final hasFlutter = unit.directives.any(
        (d) =>
            d is ImportDirective &&
            d.uri.stringValue != null &&
            d.uri.stringValue!.startsWith('package:flutter/'),
      );
      if (!hasFlutter) continue;

      final visitor = _FlutterPatternVisitor(relativePath, unit);
      unit.accept(visitor);
      issues.addAll(visitor.issues);
    }

    return issues;
  }
}

class _FlutterPatternVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final List<Issue> issues = [];

  _FlutterPatternVisitor(this.filePath, this.unit);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;

    // ── avoid-shrink-wrap-in-lists ──
    if (typeName == 'ListView' || typeName == 'GridView') {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression &&
            arg.name.label.name == 'shrinkWrap' &&
            arg.expression.toSource() == 'true') {
          final line = unit.lineInfo.getLocation(arg.offset).lineNumber;
          issues.add(
            Issue(
              rule: 'flutter-anti-patterns',
              message:
                  '$typeName with shrinkWrap: true — '
                  'consider using Sliver variants instead',
              file: filePath,
              line: line,
              severity: Severity.warning,
            ),
          );
        }
      }
    }

    // ── avoid-expanded-as-spacer ──
    if (typeName == 'Expanded' || typeName == 'Flexible') {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression && arg.name.label.name == 'child') {
          final child = arg.expression;
          if (child is InstanceCreationExpression) {
            final childType = child.constructorName.type.name.lexeme;
            if (childType == 'SizedBox' || childType == 'Container') {
              // Check if child has no meaningful args besides key
              final childArgs = child.argumentList.arguments.where(
                (a) => a is! NamedExpression || a.name.label.name != 'key',
              );
              if (childArgs.isEmpty) {
                final line = unit.lineInfo.getLocation(node.offset).lineNumber;
                issues.add(
                  Issue(
                    rule: 'flutter-anti-patterns',
                    message:
                        '$typeName(child: $childType()) — use Spacer() instead',
                    file: filePath,
                    line: line,
                    severity: Severity.info,
                  ),
                );
              }
            }
          }
        }
      }
    }

    // ── pass-existing-future-to-future-builder ──
    if (typeName == 'FutureBuilder') {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression && arg.name.label.name == 'future') {
          final expr = arg.expression;
          // Check if it's a method call creating a new future inline
          if (expr is MethodInvocation || expr is InstanceCreationExpression) {
            final line = unit.lineInfo.getLocation(arg.offset).lineNumber;
            issues.add(
              Issue(
                rule: 'flutter-anti-patterns',
                message:
                    'FutureBuilder receives a new Future on every build — '
                    'store the Future in a variable (e.g. in initState)',
                file: filePath,
                line: line,
                severity: Severity.warning,
              ),
            );
          }
        }
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final methodName = node.name.lexeme;

    // ── proper-super-calls ──
    if (methodName == 'initState' || methodName == 'dispose') {
      final body = node.body;
      if (body is BlockFunctionBody) {
        final stmts = body.block.statements;
        if (stmts.isEmpty) {
          super.visitMethodDeclaration(node);
          return;
        }

        if (methodName == 'initState') {
          // super.initState() should be called first
          final first = stmts.first;
          if (!_isSuperCall(first, 'initState')) {
            final line = unit.lineInfo.getLocation(node.offset).lineNumber;
            issues.add(
              Issue(
                rule: 'flutter-anti-patterns',
                message:
                    'super.initState() should be the first call in initState()',
                file: filePath,
                line: line,
                severity: Severity.warning,
              ),
            );
          }
        } else if (methodName == 'dispose') {
          // super.dispose() should be called last
          final last = stmts.last;
          if (!_isSuperCall(last, 'dispose')) {
            final line = unit.lineInfo.getLocation(node.offset).lineNumber;
            issues.add(
              Issue(
                rule: 'flutter-anti-patterns',
                message: 'super.dispose() should be the last call in dispose()',
                file: filePath,
                line: line,
                severity: Severity.warning,
              ),
            );
          }
        }
      }
    }

    super.visitMethodDeclaration(node);
  }

  bool _isSuperCall(Statement stmt, String methodName) {
    if (stmt is ExpressionStatement) {
      final expr = stmt.expression;
      if (expr is MethodInvocation) {
        return expr.target is SuperExpression &&
            expr.methodName.name == methodName;
      }
    }
    return false;
  }
}
