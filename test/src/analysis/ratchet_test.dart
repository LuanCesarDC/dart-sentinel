import 'dart:io';

import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Issue _issue(String rule, String file) => Issue(
  rule: rule,
  message: 'm',
  file: file,
  line: 1,
  severity: Severity.warning,
);

void main() {
  test('a regression names the files that got worse', () {
    final dir = Directory.systemTemp.createTempSync('sentinel_ratchet_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'baseline.json');

    Ratchet.saveBaseline([_issue('complexity', 'lib/a.dart')], path: path);
    final result = Ratchet.check([
      _issue('complexity', 'lib/a.dart'),
      _issue('complexity', 'lib/b.dart'),
      _issue('complexity', 'lib/b.dart'),
    ], path: path);

    expect(result.passed, isFalse);
    expect(result.message, contains('lib/b.dart (+2)'));
    expect(result.message, isNot(contains('lib/a.dart')));
  });

  test('a baseline without per-file counts still checks', () {
    final dir = Directory.systemTemp.createTempSync('sentinel_ratchet_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'baseline.json');
    File(path).writeAsStringSync('{"version":1,"rules":{"complexity":0}}');

    final result = Ratchet.check([
      _issue('complexity', 'lib/a.dart'),
    ], path: path);
    expect(result.passed, isFalse);
  });
}
