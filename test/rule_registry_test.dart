import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../bin/rule_registry.dart';

void main() {
  test('allSentinelRules has no duplicate rule names and covers key rules', () {
    final rules = allSentinelRules();
    final names = rules.map((r) => r.name).toList();

    expect(names.toSet().length, names.length, reason: 'no duplicate rule names');
    expect(names, contains('dead-files'));
    expect(names, contains('layer-dependency'));
    expect(names, contains('dispose-check'));
    expect(names, contains('complexity'));
    expect(names, contains('flutter-anti-patterns'));
    expect(rules.length, 35);
  });
}
