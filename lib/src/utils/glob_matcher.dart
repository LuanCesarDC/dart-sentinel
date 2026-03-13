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
      i += _appendGlobToken(normalized, i, buffer);
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  static int _appendGlobToken(String pattern, int i, StringBuffer buffer) {
    final char = pattern[i];
    switch (char) {
      case '*':
        return _appendStarToken(pattern, i, buffer);
      case '?':
        buffer.write('[^/]');
        return 1;
      case '.':
        buffer.write(r'\.');
        return 1;
      case '{':
        buffer.write('(?:');
        return 1;
      case '}':
        buffer.write(')');
        return 1;
      case ',':
        buffer.write('|');
        return 1;
      default:
        buffer.write(char);
        return 1;
    }
  }

  static int _appendStarToken(String pattern, int i, StringBuffer buffer) {
    final isDoubleStar =
        i + 1 < pattern.length && pattern[i + 1] == '*';
    if (!isDoubleStar) {
      buffer.write('[^/]*');
      return 1;
    }
    final hasTrailingSlash =
        i + 2 < pattern.length && pattern[i + 2] == '/';
    if (hasTrailingSlash) {
      buffer.write('(?:.+/)?');
      return 3;
    }
    buffer.write('.*');
    return 2;
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
