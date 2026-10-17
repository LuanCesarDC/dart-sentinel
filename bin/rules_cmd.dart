// `dart_sentinel rules` — lists every rule with its category, default
// severity and whether the project's analyzer.yaml turns it off or changes it.
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';

import 'rule_registry.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.');
  final projectRoot =
      parser.parse(args)['project'] as String? ?? Directory.current.path;
  final config = AnalyzerConfig.load(projectRoot);

  final rules = allSentinelRules()
    ..sort((a, b) {
      final byCategory = categoryOf(a.name).compareTo(categoryOf(b.name));
      return byCategory != 0 ? byCategory : a.name.compareTo(b.name);
    });

  print('Rules (${rules.length}) — all run by default; `rule: off` disables:');
  print('');
  for (final rule in rules) {
    final off = config.disabledRules.contains(rule.name);
    final severity = config.ruleSeverities[rule.name] ?? rule.defaultSeverity;
    final state = off ? 'off' : severity.name;
    final marker = off ? '○' : '●';
    print(
      '  $marker ${rule.name.padRight(26)} '
      '${categoryOf(rule.name).padRight(8)} $state',
    );
  }
}
