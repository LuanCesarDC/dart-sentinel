import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

const _layers = '''
architecture:
  layers:
    core:
      paths: ["lib/core/**"]
      can_depend_on: ["core"]
    core_model:
      paths: ["lib/core/*/model/**"]
      can_depend_on: []
    core_view_model:
      paths: ["lib/core/*/view_model/**"]
      can_depend_on: ["core_model"]
''';

void main() {
  group('layer-dependency', () {
    test('a more specific sub-layer wins over an earlier broad one', () async {
      final issues = await runRule(LayerDependencyRule(), {
        'analyzer.yaml': _layers,
        'lib/core/xp/model/xp.dart': 'class Xp {}\n',
        'lib/core/xp/view_model/xp_vm.dart':
            "import 'package:fixture/core/xp/model/xp.dart';\nclass XpVm { Xp? x; }\n",
        'lib/core/xp/model/bad.dart':
            "import 'package:fixture/core/xp/view_model/xp_vm.dart';\nclass Bad {}\n",
      });
      expect(issues.single.file, 'lib/core/xp/model/bad.dart');
      expect(issues.single.message, contains('core_model'));
    });

    test('relative imports are checked too', () async {
      final issues = await runRule(LayerDependencyRule(), {
        'analyzer.yaml': _layers,
        'lib/core/xp/view_model/xp_vm.dart': 'class XpVm {}\n',
        'lib/core/xp/model/bad.dart':
            "import '../view_model/xp_vm.dart';\nclass Bad {}\n",
      });
      expect(issues, hasLength(1));
    });
  });
}
