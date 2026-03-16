import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/plugin/lint_codes.dart';

// Rules
import 'src/plugin/rules/async_safety_plugin_rule.dart';
import 'src/plugin/rules/build_complexity_plugin_rule.dart';
import 'src/plugin/rules/complexity_plugin_rule.dart';
import 'src/plugin/rules/dead_todo_plugin_rule.dart';
import 'src/plugin/rules/dispose_check_plugin_rule.dart';
import 'src/plugin/rules/empty_catch_plugin_rule.dart';
import 'src/plugin/rules/generic_naming_plugin_rule.dart';
import 'src/plugin/rules/passthrough_function_plugin_rule.dart';
import 'src/plugin/rules/redundant_comment_plugin_rule.dart';
import 'src/plugin/rules/single_method_class_plugin_rule.dart';
import 'src/plugin/rules/lazy_null_check_plugin_rule.dart';
import 'src/plugin/rules/verbose_logging_plugin_rule.dart';

// Fixes
import 'src/plugin/fixes/async_safety_fix.dart';
import 'src/plugin/fixes/dead_todo_fix.dart';
import 'src/plugin/fixes/empty_catch_fix.dart';
import 'src/plugin/fixes/redundant_comment_fix.dart';

/// Plugin entry point — required by analysis_server_plugin.
final plugin = DartSentinelPlugin();

class DartSentinelPlugin extends Plugin {
  @override
  String get name => 'dart_sentinel';

  @override
  void register(PluginRegistry registry) {
    // ── Rules ──
    registry.registerLintRule(EmptyCatchPluginRule());
    registry.registerLintRule(DeadTodoPluginRule());
    registry.registerLintRule(RedundantCommentPluginRule());
    registry.registerLintRule(AsyncSafetyPluginRule());
    registry.registerLintRule(DisposeCheckPluginRule());
    registry.registerLintRule(GenericNamingPluginRule());
    registry.registerLintRule(VerboseLoggingPluginRule());
    registry.registerLintRule(SingleMethodClassPluginRule());
    registry.registerLintRule(PassthroughFunctionPluginRule());
    registry.registerLintRule(ComplexityPluginRule());
    registry.registerLintRule(BuildComplexityPluginRule());
    registry.registerLintRule(LazyNullCheckPluginRule());

    // ── Quick fixes ──
    registry.registerFixForRule(SentinelCodes.emptyCatch, EmptyCatchFix.new);
    registry.registerFixForRule(
      SentinelCodes.emptyCatchPrintOnly,
      EmptyCatchFix.new,
    );
    registry.registerFixForRule(SentinelCodes.deadTodo, DeadTodoFix.new);
    registry.registerFixForRule(
      SentinelCodes.redundantComment,
      RedundantCommentFix.new,
    );
    registry.registerFixForRule(SentinelCodes.asyncSafety, AsyncSafetyFix.new);
  }
}
