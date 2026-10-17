import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

import '../helpers/fixture_project.dart';

const _config = '''
architecture:
  banned_imports:
    - paths: ["lib/features/*/view/**"]
      deny: ["package:fixture/features/**/model/*_repository.dart"]
      message: "Views must not import repositories"
''';

void main() {
  group('banned-imports', () {
    Future<List<Issue>> run(String importLine) => runRule(BannedImportsRule(), {
      'analyzer.yaml': _config,
      'lib/features/a/model/a_repository.dart': 'class ARepository {}\n',
      'lib/features/a/view/a_screen.dart': '$importLine\nclass AScreen {}\n',
    });

    test('catches the package: spelling', () async {
      final issues = await run(
        "import 'package:fixture/features/a/model/a_repository.dart';",
      );
      expect(issues, hasLength(1));
    });

    test('catches the same file through a relative import', () async {
      final issues = await run("import '../model/a_repository.dart';");
      expect(issues, hasLength(1));
    });

    test('ignores relative imports of other files', () async {
      final issues = await run("import '../model/a.dart';");
      expect(issues, isEmpty);
    });
  });
}
