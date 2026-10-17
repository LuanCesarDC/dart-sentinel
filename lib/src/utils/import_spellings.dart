import 'package:path/path.dart' as p;

/// Every way an import of project code can be written, so a glob matches it
/// whichever spelling the author (or the importing file) used.
///
/// For `../model/a.dart` imported from `lib/features/x/view/s.dart` in package
/// `app` this yields the raw URI, `lib/features/x/model/a.dart` and
/// `package:app/features/x/model/a.dart`. Imports of other packages and
/// `dart:` libraries yield only the raw URI.
List<String> importSpellings({
  required String importUri,
  required String sourceRelativePath,
  required String packageName,
}) {
  final prefix = 'package:$packageName/';
  final String? projectPath;
  if (!importUri.contains(':')) {
    projectPath = p.posix.normalize(
      p.posix.join(p.posix.dirname(sourceRelativePath), importUri),
    );
  } else if (importUri.startsWith(prefix)) {
    projectPath = 'lib/${importUri.substring(prefix.length)}';
  } else {
    projectPath = null;
  }
  return [
    importUri,
    if (projectPath != null) projectPath,
    if (projectPath != null && projectPath.startsWith('lib/'))
      '$prefix${projectPath.substring('lib/'.length)}',
  ];
}
