import 'dart:convert';

import '../core/issue.dart';

/// SARIF 2.1.0 — GitHub Code Scanning, Azure DevOps and most IDEs read it.
class SarifOutput {
  static String format(List<Issue> issues, {String version = ''}) {
    final rules = {for (final issue in issues) issue.rule}.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'dart_sentinel',
              if (version.isNotEmpty) 'version': version,
              'informationUri': 'https://github.com/LuanCesarDC/dart-sentinel',
              'rules': [
                for (final rule in rules) {'id': rule, 'name': rule},
              ],
            },
          },
          'results': [for (final issue in issues) _result(issue)],
        },
      ],
    });
  }

  static Map<String, Object> _result(Issue issue) => {
    'ruleId': issue.rule,
    'level': switch (issue.severity) {
      Severity.error => 'error',
      Severity.warning => 'warning',
      Severity.info => 'note',
    },
    'message': {'text': issue.message},
    'locations': [
      {
        'physicalLocation': {
          'artifactLocation': {'uri': issue.file},
          'region': {'startLine': issue.line > 0 ? issue.line : 1},
        },
      },
    ],
  };
}

/// GitHub Actions workflow commands: issues show as annotations on the PR.
class GithubOutput {
  static String format(List<Issue> issues) {
    final lines = [
      for (final issue in issues)
        '::${_command(issue.severity)} file=${issue.file}'
            '${issue.line > 0 ? ',line=${issue.line}' : ''}'
            ',title=${issue.rule}::${_escape(issue.message)}',
    ];
    return lines.join('\n');
  }

  static String _command(Severity severity) => switch (severity) {
    Severity.error => 'error',
    Severity.warning => 'warning',
    Severity.info => 'notice',
  };

  static String _escape(String text) => text
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
}

/// Code Climate JSON, which GitLab renders as its Code Quality report.
class CodeClimateOutput {
  static String format(List<Issue> issues) =>
      const JsonEncoder.withIndent('  ').convert([
        for (final issue in issues)
          {
            'type': 'issue',
            'check_name': issue.rule,
            'description': issue.message,
            'categories': ['Complexity'],
            'severity': switch (issue.severity) {
              Severity.error => 'critical',
              Severity.warning => 'major',
              Severity.info => 'minor',
            },
            'fingerprint': _fingerprint(issue),
            'location': {
              'path': issue.file,
              'lines': {'begin': issue.line > 0 ? issue.line : 1},
            },
          },
      ]);

  /// Stable across runs for the same rule, file and message.
  static String _fingerprint(Issue issue) => base64Url.encode(
    utf8.encode('${issue.rule}|${issue.file}|${issue.message}'),
  );
}

/// A single self-contained HTML page, to open locally or publish as a CI
/// artifact.
class HtmlOutput {
  static String format(List<Issue> issues, {Duration? elapsed}) {
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings = issues.where((i) => i.severity == Severity.warning).length;
    final infos = issues.length - errors - warnings;
    final rows = StringBuffer();
    for (final issue in issues) {
      rows.writeln(
        '<tr class="${issue.severity}"><td>${issue.severity}</td>'
        '<td>${_escape(issue.rule)}</td>'
        '<td>${_escape(issue.file)}${issue.line > 0 ? ':${issue.line}' : ''}</td>'
        '<td>${_escape(issue.message)}</td></tr>',
      );
    }
    return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dart Sentinel report</title>
<style>
body{font:14px system-ui,sans-serif;margin:2rem auto;max-width:1100px;padding:0 1rem;color:#1f2328}
h1{font-size:1.4rem}.cards{display:flex;gap:1rem;margin:1rem 0}
.card{border:1px solid #d0d7de;border-radius:8px;padding:.6rem 1rem}
.card b{display:block;font-size:1.6rem}
table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #eaeef2;vertical-align:top}
tr.error td:first-child{color:#cf222e}tr.warning td:first-child{color:#9a6700}tr.info td:first-child{color:#0969da}
input{padding:.4rem;width:100%;box-sizing:border-box;margin-bottom:.8rem}
@media (prefers-color-scheme:dark){body{background:#0d1117;color:#e6edf3}.card,td,th{border-color:#30363d}input{background:#161b22;color:inherit;border:1px solid #30363d}}
</style></head><body>
<h1>Dart Sentinel report</h1>
<div class="cards">
<div class="card"><b>$errors</b>errors</div>
<div class="card"><b>$warnings</b>warnings</div>
<div class="card"><b>$infos</b>infos</div>
<div class="card"><b>${issues.map((i) => i.file).toSet().length}</b>files</div>
${elapsed == null ? '' : '<div class="card"><b>${elapsed.inMilliseconds}ms</b>elapsed</div>'}
</div>
<input id="q" placeholder="Filter by rule, file or message" oninput="
const q=this.value.toLowerCase();
document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))">
<table><thead><tr><th>Severity</th><th>Rule</th><th>Location</th><th>Message</th></tr></thead>
<tbody>
$rows</tbody></table></body></html>
''';
  }

  static String _escape(String text) => const HtmlEscape().convert(text);
}
