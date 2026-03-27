import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// File-based cache that stores content hashes of analyzed files.
///
/// If a file's hash hasn't changed since the last run, its cached
/// results can be reused. The cache is stored in
/// `.dart_sentinel/cache/file_hashes.json`.
class FileHashCache {
  final String projectRoot;
  final String _cachePath;
  Map<String, String> _hashes = {};
  Map<String, String> _currentHashes = {};

  FileHashCache(this.projectRoot)
    : _cachePath = p.join(
        projectRoot,
        '.dart_sentinel',
        'cache',
        'file_hashes.json',
      );

  /// Load the previously stored hashes from disk.
  void load() {
    final file = File(_cachePath);
    if (!file.existsSync()) return;

    try {
      final content = file.readAsStringSync();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      _hashes = parsed.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      // Corrupted cache — start fresh
      _hashes = {};
    }
  }

  /// Check whether a file has changed since the last cached run.
  ///
  /// Returns `true` if the file has been modified and needs re-analysis.
  bool hasChanged(String filePath) {
    final relative = p.relative(filePath, from: projectRoot);
    final file = File(filePath);
    if (!file.existsSync()) return true;

    // Use file size + last modified as a fast change indicator
    final stat = file.statSync();
    final currentHash = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    _currentHashes[relative] = currentHash;

    return _hashes[relative] != currentHash;
  }

  /// Save the current file hashes to disk.
  void save() {
    final dir = Directory(p.dirname(_cachePath));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File(_cachePath);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_currentHashes),
    );
  }

  /// Delete the cache file.
  void clear() {
    final file = File(_cachePath);
    if (file.existsSync()) file.deleteSync();
  }
}
