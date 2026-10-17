// Fixtures for false positives reported against real apps. The count of
// issues each snippet produces must not grow.
import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

void main() {
  group('unused-code', () {
    test('extension used only through its members is not flagged', () async {
      final issues = await runRule(UnusedCodeRule(), {
        'lib/main.dart':
            "import 'ext.dart';\nvoid main() { print('a'.shout()); }\n",
        'lib/ext.dart':
            'extension StringShout on String {\n  String shout() => toUpperCase();\n}\n',
      });
      expect(issues, isEmpty);
    });

    test('extension whose members are never called is flagged', () async {
      final issues = await runRule(UnusedCodeRule(), {
        'lib/main.dart': "import 'ext.dart';\nvoid main() {}\n",
        'lib/ext.dart':
            'extension StringShout on String {\n  String shout() => toUpperCase();\n}\n',
      });
      expect(issues.single.message, contains('StringShout'));
    });

    test('entry-point pragma and main are never reported', () async {
      final issues = await runRule(UnusedCodeRule(), {
        'lib/main.dart': "import 'bg.dart';\nvoid main() {}\n",
        'lib/bg.dart':
            "@pragma('vm:entry-point')\nvoid callbackDispatcher() {}\n",
      });
      expect(issues, isEmpty);
    });
  });

  group('generic-naming', () {
    test(
      'named parameters, constants, fields and overrides are allowed',
      () async {
        final issues = await runRule(GenericNamingRule(), {
          'lib/a.dart': '''
const result = 1;
class Box {
  final int value;
  Box({required int data}) : value = data;
  @override
  bool operator ==(Object other) => other is Box;
  @override
  int get hashCode => 0;
  @override
  String format(String input) => input;
}
''',
        });
        expect(issues, isEmpty);
      },
    );

    test('a plain local variable named data is still flagged', () async {
      final issues = await runRule(GenericNamingRule(), {
        'lib/a.dart': 'int f() {\n  final data = 1;\n  return data;\n}\n',
      });
      expect(issues, hasLength(1));
    });
  });

  group('no-equal-arguments', () {
    test('symmetric geometry constructors are allowed', () async {
      final issues = await runRule(NoEqualArgumentsRule(), {
        'lib/a.dart': '''
class EdgeInsets { EdgeInsets.fromLTRB(double a, double b, double c, double d); }
class Offset { Offset(double x, double y); }
void f(double pad) {
  EdgeInsets.fromLTRB(pad, 1, pad, 2);
  Offset(pad, pad);
}
''',
      });
      expect(issues, isEmpty);
    });

    test('ignore list is extendable from analyzer.yaml', () async {
      final context = await buildFixture({
        'analyzer.yaml':
            'ai_slop:\n  no_equal_arguments:\n    ignore: [pair]\n',
        'lib/a.dart':
            'void pair(int a, int b) {}\nvoid f(int x) { pair(x, x); }\n',
      });
      expect(NoEqualArgumentsRule().run(context), isEmpty);
    });
  });

  group('dispose-check', () {
    test('ref.onDispose tear-off and closure count as cleanup', () async {
      final issues = await runRule(DisposeCheckRule(), {
        'lib/a.dart': '''
class TextEditingController { void dispose() {} }
class Notifier {
  final controller = TextEditingController();
  final other = TextEditingController();
  void build(dynamic ref) {
    ref.onDispose(controller.dispose);
    ref.onDispose(() { other.dispose(); });
  }
}
''',
      });
      expect(issues, isEmpty);
    });
  });

  group('untested-files', () {
    test('widget test outside the mirrored path counts', () async {
      final issues = await runRule(UntestedFilesRule(), {
        'lib/ui/home.dart': 'class Home {}\n',
        'test/widgets/home_test.dart': 'void main() {}\n',
      });
      expect(issues, isEmpty);
    });

    test('integration_test files count', () async {
      final issues = await runRule(UntestedFilesRule(), {
        'lib/ui/home.dart': 'class Home {}\n',
        'test/placeholder_test.dart': 'void main() {}\n',
        'integration_test/home_test.dart': 'void main() {}\n',
      });
      expect(issues, isEmpty);
    });
  });

  group('misused-dependencies', () {
    test(
      'annotation packages are exempt when build_runner is present',
      () async {
        final issues = await runRule(MisusedDependenciesRule(), {
          'pubspec.yaml': '''
name: fixture
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  json_annotation: ^4.0.0
  freezed_annotation: ^2.0.0
dev_dependencies:
  build_runner: ^2.0.0
''',
          'lib/a.dart': 'class A {}\n',
        });
        expect(issues, isEmpty);
      },
    );
  });
}
