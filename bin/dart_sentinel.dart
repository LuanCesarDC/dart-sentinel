// Main entry point — delegates to analyze.dart, mcp_server.dart, or subcommands.
//
// `dart_sentinel`                          → CLI analysis
// `dart_sentinel --mcp`                    → MCP server over stdio
// `dart_sentinel generate-ai-config`       → Generate AI integration files
// `dart_sentinel hook-edit`                → Claude Code PostToolUse hook
// `dart_sentinel hook-stop`                → Claude Code Stop hook
// `dart_sentinel setup-hooks`              → write Claude Code hook config
import 'analyze.dart' as analyze;
import 'generate_ai_config.dart' as gen_ai;
import 'hook_edit.dart' as hook_edit;
import 'hook_stop.dart' as hook_stop;
import 'mcp_server.dart' as mcp;
import 'setup_hooks.dart' as setup_hooks;

Future<void> main(List<String> args) async {
  if (args.contains('--mcp')) {
    mcp.main();
  } else if (args.isNotEmpty && args.first == 'generate-ai-config') {
    await gen_ai.main(args.sublist(1));
  } else if (args.isNotEmpty && args.first == 'hook-edit') {
    await hook_edit.main(args.sublist(1));
  } else if (args.isNotEmpty && args.first == 'hook-stop') {
    await hook_stop.main(args.sublist(1));
  } else if (args.isNotEmpty && args.first == 'setup-hooks') {
    await setup_hooks.main(args.sublist(1));
  } else {
    await analyze.main(args);
  }
}
