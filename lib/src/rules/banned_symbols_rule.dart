import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../utils/glob_matcher.dart';

/// Enforces banned symbol rules based on architecture configuration.
///
/// Unlike `banned-imports` which checks import URIs, this rule checks
/// actual symbol usage — class constructors, function calls, and type
/// references — within source code. This is useful when the banned and
/// preferred symbols come from the same import (e.g. `ElevatedButton`
/// vs `MoovzButton` both from `package:flutter/material.dart`).
class BannedSymbolsRule extends AnalyzerRule {
  @override
  String get name => 'banned-symbols';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  List<Issue> run(ProjectContext context) {
    final configs = context.config.bannedSymbols;
    if (configs.isEmpty) return [];

    final issues = <Issue>[];
    for (final file in context.allFiles) {
      issues.addAll(_checkFile(file, configs, context));
    }
    return issues;
  }

  List<Issue> _checkFile(
    String file,
    List<BannedSymbolConfig> configs,
    ProjectContext context,
  ) {
    final relativePath = context.relativePath(file);
    final unit = context.parsedUnits[file];
    if (unit == null) return [];

    // Collect which deny sets apply to this file
    final applicableRules = _applicableRules(relativePath, configs);
    if (applicableRules.isEmpty) return [];

    // Build a single deny → config lookup for fast matching
    final denyMap = <String, BannedSymbolConfig>{};
    for (final config in applicableRules) {
      for (final symbol in config.deny) {
        denyMap[symbol] = config;
      }
    }

    final visitor = _BannedSymbolVisitor(relativePath, unit, denyMap);
    unit.visitChildren(visitor);
    return visitor.issues;
  }

  List<BannedSymbolConfig> _applicableRules(
    String relativePath, List<BannedSymbolConfig> configs,
  ) {
    return configs.where((c) {
      return c.paths.any((p) => GlobMatcher(p).matches(relativePath));
    }).toList();
  }
}

class _BannedSymbolVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final CompilationUnit unit;
  final Map<String, BannedSymbolConfig> denyMap;
  final List<Issue> issues = [];

  /// Track already-reported offsets to avoid duplicate issues for the same
  /// AST node (e.g. both NamedType and InstanceCreationExpression).
  final Set<int> _reportedOffsets = {};

  _BannedSymbolVisitor(this.filePath, this.unit, this.denyMap);

  // ── Constructor calls: ElevatedButton(...), ElevatedButton.icon(...) ──

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name2.lexeme;
    _check(typeName, node.constructorName.offset);
    super.visitInstanceCreationExpression(node);
  }

  // ── Function calls: showDialog(...), showModalBottomSheet(...) ──

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Top-level function calls: showDialog(...)
    if (node.target == null) {
      _check(node.methodName.name, node.methodName.offset);
    }
    // Static method calls: SomeClass.method(...)
    if (node.target is SimpleIdentifier) {
      _check((node.target as SimpleIdentifier).name, node.target!.offset);
    }
    super.visitMethodInvocation(node);
  }

  // ── Type references in annotations, parameters, variables ──

  @override
  void visitNamedType(NamedType node) {
    _check(node.name2.lexeme, node.offset);
    super.visitNamedType(node);
  }

  void _check(String symbolName, int offset) {
    if (_reportedOffsets.contains(offset)) return;
    final config = denyMap[symbolName];
    if (config == null) return;
    _reportedOffsets.add(offset);

    final line = unit.lineInfo.getLocation(offset).lineNumber;
    final suggest =
        config.suggest.isNotEmpty ? ' Use ${config.suggest} instead.' : '';
    final message = config.message.isNotEmpty
        ? '${config.message}$suggest'
        : 'Banned symbol: $symbolName.$suggest';

    issues.add(Issue(
      rule: 'banned-symbols',
      message: message,
      file: filePath,
      line: line,
      severity: Severity.warning,
    ));
  }
}
