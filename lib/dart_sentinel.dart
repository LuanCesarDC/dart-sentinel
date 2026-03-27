/// Dart Sentinel — Static analysis & metrics for Dart/Flutter projects.
///
/// A comprehensive tool for detecting dead code, enforcing architecture rules,
/// calculating code metrics, and applying custom lint rules.
///
/// ## Quick Start
///
/// Install globally:
///
/// ```bash
/// dart pub global activate dart_sentinel
/// ```
///
/// Run:
///
/// ```bash
/// dart_sentinel              # all rules
/// dart_sentinel -o arch      # architecture only
/// dart_sentinel -o metrics   # metrics only
/// dart_sentinel -f json      # JSON output
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
export 'src/rules/lazy_null_check_rule.dart';
export 'src/rules/model_missing_methods_rule.dart';
export 'src/rules/unused_code_rule.dart';
export 'src/rules/untested_files_rule.dart';
export 'src/rules/test_coverage_rule.dart';
export 'src/rules/test_quality_rule.dart';
export 'src/rules/class_metrics_rule.dart';
export 'src/rules/pubspec_rule.dart';
export 'src/rules/avoid_global_state_rule.dart';
export 'src/rules/no_magic_number_rule.dart';
export 'src/rules/no_equal_then_else_rule.dart';
export 'src/rules/avoid_commented_out_code_rule.dart';
export 'src/rules/no_equal_arguments_rule.dart';
export 'src/rules/avoid_self_compare_rule.dart';
export 'src/rules/avoid_returning_widgets_rule.dart';
export 'src/rules/flutter_anti_patterns_rule.dart';
export 'src/rules/misused_dependencies_rule.dart';

// Analysis
export 'src/analysis/dependency_mapper.dart';
export 'src/analysis/impact_analyzer.dart';
export 'src/analysis/migration_tracker.dart';
export 'src/analysis/ratchet.dart';
export 'src/analysis/l10n_scanner.dart';

// Output
export 'src/output/output.dart';

// MCP
export 'src/mcp/sentinel_server.dart';

// Utils
export 'src/utils/glob_matcher.dart';
export 'src/utils/graph_utils.dart';
export 'src/analysis/model_generator.dart';
export 'src/core/file_hash_cache.dart';
