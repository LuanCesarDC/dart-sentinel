import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_project.dart';

const _layersConfig = '''
architecture:
  layers:
    feature:
      paths: ["lib/features/**"]
''';

void main() {
  test('relativePath always uses / separators', () async {
    final context = await buildFixture({
      'lib/features/a/view/a_screen.dart': 'class A {}\n',
    });
    final relative = context.allFiles.map(context.relativePath).toList();
    expect(relative, contains('lib/features/a/view/a_screen.dart'));
    expect(relative.where((path) => path.contains(r'\')), isEmpty);
  });

  test('a layer that matches real files raises no coverage warning', () async {
    final context = await buildFixture({
      'analyzer.yaml': _layersConfig,
      'lib/features/a/view/a_screen.dart': 'class A {}\n',
    });
    final warnings = layerCoverageWarnings(
      context.config,
      context.allFiles.map(context.relativePath),
    );
    expect(warnings, isEmpty);
  });
}
