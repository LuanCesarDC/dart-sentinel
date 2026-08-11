import 'dart:io';

import 'package:dart_sentinel/src/core/issue.dart';
import 'package:dart_sentinel/src/core/project_context.dart';
import 'package:dart_sentinel/src/rules/complexity_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('counts actual source lines, not AST-unparsed lines', () async {
    final tmpDir = await Directory.systemTemp.createTemp(
      'complexity_loc_test_',
    );
    addTearDown(() => tmpDir.deleteSync(recursive: true));

    File(p.join(tmpDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_app
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    final libDir = Directory(p.join(tmpDir.path, 'lib'))..createSync();

    // 610 real lines — must trip the 600-line error threshold.
    final lines = List.generate(610, (i) => 'final v$i = $i;');
    File(p.join(libDir.path, 'huge.dart')).writeAsStringSync(lines.join('\n'));

    final context = await ProjectContext.build(tmpDir.path);
    final issues = ComplexityRule().run(context);

    final locIssue = issues.where((i) => i.message.contains('lines of code'));
    expect(locIssue, isNotEmpty);
    expect(locIssue.first.severity, Severity.error);
  });
}
