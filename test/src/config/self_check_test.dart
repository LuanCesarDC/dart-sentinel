import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_project.dart';

void main() {
  test('flags a deny pattern that matches no import', () async {
    final context = await buildFixture({
      'analyzer.yaml': '''
architecture:
  banned_imports:
    - paths: ["lib/**"]
      deny: ["package:other_app/**/x_repository.dart"]
''',
      'lib/a.dart': 'class A {}\n',
    });
    final messages = selfCheck(context);
    expect(messages.single, contains('other_app'));
    expect(messages.single, contains('"fixture"'));
  });

  test('a relative import keeps a package: pattern live', () async {
    final context = await buildFixture({
      'analyzer.yaml': '''
architecture:
  banned_imports:
    - paths: ["lib/**"]
      deny: ["package:fixture/m/x_repository.dart"]
''',
      'lib/m/x_repository.dart': 'class X {}\n',
      'lib/v/s.dart': "import '../m/x_repository.dart';\nclass S {}\n",
    });
    expect(selfCheck(context), isEmpty);
  });

  test('flags a deny_files pattern that matches no file', () async {
    final context = await buildFixture({
      'analyzer.yaml': '''
architecture:
  layers:
    view:
      paths: ["lib/v/**"]
      can_depend_on: ["model"]
      deny_files: ["*_repo.dart"]
''',
      'lib/v/s.dart': 'class S {}\n',
    });
    expect(selfCheck(context).single, contains('deny_files'));
  });
}
