import 'issue.dart';

final _lineIgnore = RegExp(
  r'sentinel-ignore:\s*([a-z0-9\-]+(?:\s*,\s*[a-z0-9\-]+)*)',
);
final _fileIgnore = RegExp(
  r'sentinel-ignore-file:\s*([a-z0-9\-]+(?:\s*,\s*[a-z0-9\-]+)*)',
);

/// True when [issue] is silenced by a comment in [lines] (the file's source):
///
/// - `// sentinel-ignore: rule — reason` on the offending line or the one above
/// - `// sentinel-ignore-file: rule — reason` anywhere in the file
///
/// Several rules may be comma-separated; `all` silences every rule.
bool isSuppressed(Issue issue, List<String> lines) {
  bool covers(Match? match) {
    if (match == null) return false;
    final rules = match.group(1)!.split(',').map((r) => r.trim());
    return rules.contains(issue.rule) || rules.contains('all');
  }

  if (lines.any((line) => covers(_fileIgnore.firstMatch(line)))) return true;
  if (issue.line <= 0) return false;

  final index = issue.line - 1;
  final candidates = [
    if (index > 0) lines[index - 1],
    if (index < lines.length) lines[index],
  ];
  return candidates.any((line) => covers(_lineIgnore.firstMatch(line)));
}
