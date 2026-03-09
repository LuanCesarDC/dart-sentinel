/// Severity levels for analysis issues.
enum Severity {
  info,
  warning,
  error;

  @override
  String toString() => name;

  /// Parse a severity from a string (case-insensitive).
  static Severity fromString(String value) {
    switch (value.toLowerCase()) {
      case 'info':
        return Severity.info;
      case 'warning':
        return Severity.warning;
      case 'error':
        return Severity.error;
      default:
        return Severity.warning;
    }
  }
}

/// Represents a single analysis issue found by a rule.
class Issue implements Comparable<Issue> {
  /// The rule that produced this issue (e.g. 'banned-imports').
  final String rule;

  /// Human-readable message describing the issue.
  final String message;

  /// The file path where the issue was found.
  final String file;

  /// The line number (1-based) where the issue occurs.
  final int line;

  /// The severity of this issue.
  final Severity severity;

  const Issue({
    required this.rule,
    required this.message,
    required this.file,
    this.line = 0,
    required this.severity,
  });

  @override
  int compareTo(Issue other) {
    // Sort by severity (error first), then file, then line
    final severityCompare =
        other.severity.index.compareTo(severity.index);
    if (severityCompare != 0) return severityCompare;

    final fileCompare = file.compareTo(other.file);
    if (fileCompare != 0) return fileCompare;

    return line.compareTo(other.line);
  }

  Map<String, dynamic> toJson() => {
        'rule': rule,
        'message': message,
        'file': file,
        'line': line,
        'severity': severity.toString(),
      };

  @override
  String toString() {
    final loc = line > 0 ? ':$line' : '';
    final icon = switch (severity) {
      Severity.error => '✖',
      Severity.warning => '⚠',
      Severity.info => 'ℹ',
    };
    return '$icon [$rule] $file$loc: $message';
  }
}
