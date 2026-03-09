import 'package:path/path.dart' as p;

/// A simple glob matcher that supports:
/// - `*` matches any single path segment (not crossing `/`)
/// - `**` matches zero or more path segments
/// - `?` matches a single character
class GlobMatcher {
  final String pattern;
  final RegExp _regex;

  GlobMatcher(this.pattern) : _regex = _compileGlob(pattern);

  /// Check if a relative path matches this glob pattern.
  bool matches(String path) {
    // Normalize separators to forward slashes
    final normalized = path.replaceAll(r'\', '/');
    return _regex.hasMatch(normalized);
  }

  static RegExp _compileGlob(String pattern) {
    final normalized = pattern.replaceAll(r'\', '/');
    final buffer = StringBuffer('^');

    int i = 0;
    while (i < normalized.length) {
      final char = normalized[i];

      if (char == '*') {
        if (i + 1 < normalized.length && normalized[i + 1] == '*') {
          // ** matches zero or more path segments
          if (i + 2 < normalized.length && normalized[i + 2] == '/') {
            buffer.write('(?:.+/)?');
            i += 3;
          } else {
            buffer.write('.*');
            i += 2;
          }
        } else {
          // * matches anything except /
          buffer.write('[^/]*');
          i++;
        }
      } else if (char == '?') {
        buffer.write('[^/]');
        i++;
      } else if (char == '.') {
        buffer.write(r'\.');
        i++;
      } else if (char == '{') {
        buffer.write('(?:');
        i++;
      } else if (char == '}') {
        buffer.write(')');
        i++;
      } else if (char == ',') {
        buffer.write('|');
        i++;
      } else {
        buffer.write(char);
        i++;
      }
    }

    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  @override
  String toString() => 'GlobMatcher($pattern)';
}

/// Checks if a path matches any of the given glob patterns.
bool matchesAnyGlob(String path, List<String> patterns) {
  for (final pattern in patterns) {
    if (GlobMatcher(pattern).matches(path)) {
      return true;
    }
  }
  return false;
}

/// Checks if a file path is a generated Dart file.
bool isGeneratedFile(String filePath) {
  final name = p.basename(filePath);
  return name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.gr.dart') ||
      name.endsWith('.g2.dart') ||
      name.endsWith('.mocks.dart') ||
      name.endsWith('.config.dart') ||
      name.endsWith('.mapper.dart');
}
