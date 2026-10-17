import 'dart:convert';

import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

const _issues = [
  Issue(
    rule: 'complexity',
    message: 'too <complex>\nsecond line',
    file: 'lib/a.dart',
    line: 7,
    severity: Severity.warning,
  ),
  Issue(
    rule: 'layer-dependency',
    message: 'bad import',
    file: 'lib/b.dart',
    severity: Severity.error,
  ),
];

void main() {
  test('SARIF maps severity to level and defaults the line to 1', () {
    final sarif = jsonDecode(SarifOutput.format(_issues)) as Map;
    expect(sarif['version'], '2.1.0');
    final results = (sarif['runs'] as List).single['results'] as List;
    expect(results.map((r) => r['level']), ['warning', 'error']);
    expect(
      results
          .last['locations']
          .single['physicalLocation']['region']['startLine'],
      1,
    );
  });

  test('GitHub annotations escape newlines and omit a missing line', () {
    final lines = GithubOutput.format(_issues).split('\n');
    expect(lines.first, startsWith('::warning file=lib/a.dart,line=7,'));
    expect(lines.first, contains('too <complex>%0Asecond line'));
    expect(lines.last, startsWith('::error file=lib/b.dart,title='));
  });

  test('Code Climate fingerprints are stable and severity is mapped', () {
    final first = jsonDecode(CodeClimateOutput.format(_issues)) as List;
    final second = jsonDecode(CodeClimateOutput.format(_issues)) as List;
    expect(first.first['fingerprint'], second.first['fingerprint']);
    expect(first.map((i) => i['severity']), ['major', 'critical']);
  });

  test('HTML escapes messages', () {
    final html = HtmlOutput.format(_issues);
    expect(html, contains('too &lt;complex&gt;'));
    expect(html, isNot(contains('too <complex>')));
  });
}
