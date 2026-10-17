import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

String _widget(String buildBody) =>
    '''
class Button {
  Object build(Object context) {
$buildBody
  }
}
''';

void main() {
  group('build-complexity', () {
    test('an exhaustive switch expression counts once', () async {
      final issues = await runRule(BuildComplexityRule(), {
        'lib/a.dart': _widget('''
    final variant = 1;
    return switch (variant) {
      0 => 'a',
      1 => 'b',
      2 => 'c',
      3 => 'd',
      4 => 'e',
      5 => 'f',
      6 => 'g',
      _ => 'h',
    };'''),
      });
      expect(issues, isEmpty);
    });

    test('deeply nested ifs cost more than a flat switch', () async {
      final issues = await runRule(BuildComplexityRule(), {
        'lib/a.dart': _widget('''
    final n = 1;
    if (n > 0) {
      if (n > 1) {
        if (n > 2) {
          if (n > 3) {
            if (n > 4) {
              return 1;
            }
          }
        }
      }
    }
    return 0;'''),
      });
      expect(issues.single.message, contains('branches'));
    });
  });
}
