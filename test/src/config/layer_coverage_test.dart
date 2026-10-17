import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

void main() {
  test('no layers configured means no warnings', () {
    expect(
      layerCoverageWarnings(const AnalyzerConfig(), ['lib/a/b.dart']),
      isEmpty,
    );
  });

  test('lib/src wrapper is unwrapped when naming uncovered folders', () {
    const config = AnalyzerConfig(
      layerConfig: LayerConfig(
        layers: {
          'ui': LayerDefinition(
            name: 'ui',
            paths: ['lib/src/ui/**'],
            canDependOn: [],
          ),
        },
      ),
    );
    final warnings = layerCoverageWarnings(config, [
      'lib/src/ui/a.dart',
      'lib/src/plugin/x/b.dart',
    ]);
    expect(warnings.single, contains('lib/src/plugin/'));
  });
}
