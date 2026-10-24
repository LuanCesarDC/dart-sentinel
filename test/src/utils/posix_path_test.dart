import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final windows = p.Context(style: p.Style.windows);
  final posix = p.Context(style: p.Style.posix);

  test('on Windows the result uses / so exclude and layer globs match', () {
    final relative = posixRelative(
      r'C:\proj\lib\firebase_options.dart',
      from: r'C:\proj',
      context: windows,
    );
    expect(relative, 'lib/firebase_options.dart');
    expect(matchesAnyGlob(relative, ['lib/firebase_options.dart']), isTrue);
  });

  test('on POSIX a backslash in a file name is kept', () {
    final relative = posixRelative(
      '/proj/lib/odd\\name.dart',
      from: '/proj',
      context: posix,
    );
    expect(relative, 'lib/odd\\name.dart');
  });

  test('POSIX paths pass through unchanged', () {
    expect(
      posixRelative('/proj/lib/a/b.dart', from: '/proj', context: posix),
      'lib/a/b.dart',
    );
  });
}
