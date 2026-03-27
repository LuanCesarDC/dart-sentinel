// Main entry point — delegates to analyze.dart, mcp_server.dart, or subcommands.
//
// `dart_sentinel`                          → CLI analysis
// `dart_sentinel --mcp`                    → MCP server over stdio
// `dart_sentinel generate-ai-config`       → Generate AI integration files
import 'analyze.dart' as analyze;
import 'generate_ai_config.dart' as gen_ai;
import 'mcp_server.dart' as mcp;

Future<void> main(List<String> args) async {
  if (args.contains('--mcp')) {
    mcp.main();
  } else if (args.isNotEmpty && args.first == 'generate-ai-config') {
    await gen_ai.main(args.sublist(1));
  } else {
    await analyze.main(args);
  }
}
