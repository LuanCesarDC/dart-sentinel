import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../core/issue.dart';
import '../core/project_context.dart';

/// Raw metrics of one file, independent of any threshold.
class FileMetrics {
  final String file;
  final int loc;
  final int methods;
  final int maxComplexity;
  final double averageComplexity;

  /// 0–100, higher is easier to maintain. See [CodeMetrics.maintainability].
  final double maintainability;

  const FileMetrics({
    required this.file,
    required this.loc,
    required this.methods,
    required this.maxComplexity,
    required this.averageComplexity,
    required this.maintainability,
  });

  Map<String, Object> toJson() => {
    'file': file,
    'loc': loc,
    'methods': methods,
    'maxComplexity': maxComplexity,
    'averageComplexity': double.parse(averageComplexity.toStringAsFixed(2)),
    'maintainability': double.parse(maintainability.toStringAsFixed(1)),
  };
}

/// Computes [FileMetrics] for every parsed file of a project.
class CodeMetrics {
  final ProjectContext context;

  CodeMetrics(this.context);

  List<FileMetrics> collect() => [
    for (final entry in context.parsedUnits.entries)
      _forFile(
        context.relativePath(entry.key),
        entry.value,
        context.fileContents[entry.key] ?? '',
      ),
  ];

  FileMetrics _forFile(String path, CompilationUnit unit, String source) {
    final complexities = _MethodComplexities();
    unit.accept(complexities);
    final values = complexities.values;
    final maxComplexity = values.isEmpty ? 0 : values.reduce(math.max);
    final average = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    final loc = countLines(source);
    return FileMetrics(
      file: path,
      loc: loc,
      methods: values.length,
      maxComplexity: maxComplexity,
      averageComplexity: average,
      maintainability: maintainability(
        halsteadVolume: _volume(unit),
        complexity: average,
        loc: loc,
      ),
    );
  }

  /// Lines that hold code: not blank, not a comment.
  static int countLines(String source) => source
      .split('\n')
      .map((line) => line.trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('//') &&
            !line.startsWith('/*') &&
            !line.startsWith('*'),
      )
      .length;

  /// Maintainability index (Oman & Hagemeister), rescaled to 0–100 as Visual
  /// Studio does. Halstead volume is approximated from tokens — every token
  /// is an operator or an operand — so values are comparable between files of
  /// one project, not with other tools.
  static double maintainability({
    required double halsteadVolume,
    required double complexity,
    required int loc,
  }) {
    if (loc == 0) return 100;
    final raw =
        171 -
        5.2 * math.log(math.max(halsteadVolume, 1)) -
        0.23 * complexity -
        16.2 * math.log(loc);
    return (raw * 100 / 171).clamp(0, 100).toDouble();
  }

  double _volume(CompilationUnit unit) {
    final distinct = <String>{};
    var total = 0;
    Token? token = unit.beginToken;
    while (token != null && !token.isEof) {
      distinct.add(token.lexeme);
      total++;
      token = token.next;
    }
    if (distinct.length < 2) return 1;
    return total * math.log(distinct.length) / math.ln2;
  }
}

/// Rough remediation time, in minutes, to clear [issues]. A planning aid, not
/// a measurement: errors cost 30 min, warnings 15, infos 5.
int estimateDebtMinutes(Iterable<Issue> issues) => issues.fold(
  0,
  (sum, issue) =>
      sum +
      switch (issue.severity) {
        Severity.error => 30,
        Severity.warning => 15,
        Severity.info => 5,
      },
);

class _MethodComplexities extends RecursiveAstVisitor<void> {
  final List<int> values = [];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    values.add(_complexityOf(node.functionExpression.body));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    values.add(_complexityOf(node.body));
    super.visitMethodDeclaration(node);
  }

  int _complexityOf(FunctionBody body) {
    final counter = _BranchCounter();
    body.accept(counter);
    return 1 + counter.branches;
  }
}

class _BranchCounter extends RecursiveAstVisitor<void> {
  int branches = 0;

  @override
  void visitIfStatement(IfStatement node) {
    branches++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    branches++;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    branches++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    branches++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    branches++;
    super.visitSwitchCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    branches++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    branches++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||' || op == '??') branches++;
    super.visitBinaryExpression(node);
  }
}
