import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:dart_sentinel/src/mcp/sentinel_server.dart';

/// Starts Dart Sentinel as an MCP server over stdio.
///
/// Usage:
///   dart run dart_sentinel:mcp_server
///
/// Or via the main entry point:
///   dart run dart_sentinel --mcp
void main() {
  SentinelMCPServer(stdioChannel(input: stdin, output: stdout));
}
