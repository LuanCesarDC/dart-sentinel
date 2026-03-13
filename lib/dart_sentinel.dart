/// Dart Sentinel — Static analysis & metrics for Dart/Flutter projects.
///
/// A comprehensive tool for detecting dead code, enforcing architecture rules,
/// calculating code metrics, and applying custom lint rules.
///
/// ## Quick Start
///
/// Add to your `pubspec.yaml`:
///
/// ```yaml
/// dev_dependencies:
///   dart_sentinel:
///     git:
///       url: https://github.com/LuanCesarDC/dart-linter-and-metrics.git
/// ```
///
/// Run:
///
/// ```bash
/// dart run dart_sentinel              # all rules
/// dart run dart_sentinel -o arch      # architecture only
/// dart run dart_sentinel -o metrics   # metrics only
/// dart run dart_sentinel -f json      # JSON output
/// ```
library dart_sentinel;

// Core
export 'src/core/issue.dart';
export 'src/core/project_context.dart';
export 'src/core/rule.dart';
export 'src/core/runner.dart';

// Config
export 'src/config/analyzer_config.dart';

// Rules
export 'src/rules/async_safety_rule.dart';
export 'src/rules/banned_imports_rule.dart';
export 'src/rules/banned_symbols_rule.dart';
export 'src/rules/build_complexity_rule.dart';
export 'src/rules/complexity_rule.dart';
export 'src/rules/dead_exports_rule.dart';
export 'src/rules/dead_files_rule.dart';
export 'src/rules/dispose_check_rule.dart';
export 'src/rules/feature_isolation_rule.dart';
export 'src/rules/import_cycle_rule.dart';
export 'src/rules/layer_dependency_rule.dart';
export 'src/rules/empty_catch_rule.dart';
export 'src/rules/dead_todos_rule.dart';
export 'src/rules/generic_naming_rule.dart';
export 'src/rules/redundant_comments_rule.dart';
export 'src/rules/verbose_logging_rule.dart';
export 'src/rules/single_method_class_rule.dart';
export 'src/rules/passthrough_function_rule.dart';

// Output
export 'src/output/output.dart';

// MCP
export 'src/mcp/sentinel_server.dart';

// Utils
export 'src/utils/glob_matcher.dart';
export 'src/utils/graph_utils.dart';
