import 'package:analyzer/dart/ast/ast.dart';

/// Reads call arguments uniformly: analyzer 13+ models `name: value` as a
/// [NamedArgument] instead of wrapping an [Expression] in `NamedExpression`.
extension ArgumentAccess on Argument {
  /// True for `name: value` arguments.
  bool get isNamedArgument => this is NamedArgument;

  /// The `name` of a named argument, or null for a positional one.
  String? get argumentName {
    final self = this;
    return self is NamedArgument ? self.name.lexeme : null;
  }

  /// The value expression, without the `name:` prefix.
  Expression get valueExpression {
    final self = this;
    return self is NamedArgument ? self.argumentExpression : self as Expression;
  }
}
