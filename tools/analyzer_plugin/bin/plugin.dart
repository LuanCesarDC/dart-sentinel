import 'dart:isolate';

import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/starter.dart';
import 'package:dart_sentinel_analyzer_plugin/sentinel_plugin.dart';

void main(List<String> args, SendPort sendPort) {
  ServerPluginStarter(
    SentinelPlugin(resourceProvider: PhysicalResourceProvider.INSTANCE),
  ).start(sendPort);
}
