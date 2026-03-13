/// Main entry point — delegates to analyze.dart or mcp_server.dart.
///
/// `dart run dart_sentinel`         → CLI analysis
/// `dart run dart_sentinel --mcp`   → MCP server over stdio
import 'analyze.dart' as analyze;
import 'mcp_server.dart' as mcp;

Future<void> main(List<String> args) async {
  if (args.contains('--mcp')) {
    mcp.main();
  } else {
    await analyze.main(args);
  }
}
