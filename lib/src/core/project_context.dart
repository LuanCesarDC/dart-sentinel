import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/analyzer_config.dart';
import '../utils/glob_matcher.dart';

/// Shared analysis context built once and reused by all rules.
///
/// Contains the parsed ASTs, import graph, and project metadata.
class ProjectContext {
  /// The package name from pubspec.yaml
  final String packageName;

  /// Absolute path to the project root.
  final String projectRoot;

  /// Absolute path to the lib directory.
  final String libRoot;

  /// Absolute paths to all entrypoint files.
  final List<String> entrypoints;

  /// Exclude patterns from config.
  final Set<String> excludePatterns;

  /// Import graph: file → set of files it imports/exports/parts.
  final Map<String, Set<String>> importGraph;

  /// Raw import URIs per file: file → { uri strings as written in source }.
  final Map<String, Set<String>> rawImports;

  /// Cached parsed compilation units: file → AST.
  final Map<String, CompilationUnit> parsedUnits;

  /// All dart files discovered in the project (absolute paths).
  final List<String> allFiles;

  /// The analyzer configuration.
  final AnalyzerConfig config;

  ProjectContext._({
    required this.packageName,
    required this.projectRoot,
    required this.libRoot,
    required this.entrypoints,
    required this.excludePatterns,
    required this.importGraph,
    required this.rawImports,
    required this.parsedUnits,
    required this.allFiles,
    required this.config,
  });

  /// Build a [ProjectContext] by scanning the project at [projectRoot].
  static Future<ProjectContext> build(
    String projectRoot, {
    String? targetPath,
  }) async {
    final packageName = _readPackageName(projectRoot);
    final libRoot = p.join(projectRoot, 'lib');
    final config = AnalyzerConfig.load(projectRoot);
    final excludePatterns = _buildExcludePatterns(config);
    final dirsToScan = _dirsToScan(projectRoot, libRoot, config);
    final allFiles =
        await _collectDartFiles(dirsToScan, projectRoot, excludePatterns);
    final entrypoints =
        await _detectEntrypoints(config, projectRoot, libRoot);
    final resolver = _ImportResolver(projectRoot, packageName);
    final parseResult = _parseAndBuildGraph(allFiles, resolver);

    return ProjectContext._(
      packageName: packageName,
      projectRoot: projectRoot,
      libRoot: libRoot,
      entrypoints: entrypoints,
      excludePatterns: excludePatterns,
      importGraph: parseResult.importGraph,
      rawImports: parseResult.rawImports,
      parsedUnits: parseResult.parsedUnits,
      allFiles: allFiles,
      config: config,
    );
  }

  /// Get the relative path of a file from the project root.
  String relativePath(String absolutePath) {
    return p.relative(absolutePath, from: projectRoot);
  }

  // ── Build helpers ──

  static String _readPackageName(String projectRoot) {
    final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw StateError('pubspec.yaml not found at $projectRoot');
    }
    final content = pubspecFile.readAsStringSync();
    final name = _extractPackageName(content);
    if (name == null) {
      throw StateError('Could not determine package name from pubspec.yaml');
    }
    return name;
  }

  static Set<String> _buildExcludePatterns(AnalyzerConfig config) {
    return {
      '**/*.g.dart',
      '**/*.freezed.dart',
      '**/*.gr.dart',
      '**/*.g2.dart',
      '**/*.mocks.dart',
      '**/*.config.dart',
      '**/*.mapper.dart',
      ...config.excludePatterns,
    };
  }

  static List<Directory> _dirsToScan(
      String projectRoot, String libRoot, AnalyzerConfig config) {
    final dirs = <Directory>[Directory(libRoot)];
    for (final extra in config.extraScanDirs) {
      final dir = Directory(p.join(projectRoot, extra));
      if (dir.existsSync()) dirs.add(dir);
    }
    return dirs;
  }

  static Future<List<String>> _collectDartFiles(
    List<Directory> dirsToScan,
    String projectRoot,
    Set<String> excludePatterns,
  ) async {
    final allFiles = <String>[];
    for (final dir in dirsToScan) {
      if (!dir.existsSync()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = p.normalize(entity.path);
        final relative = p.relative(normalized, from: projectRoot);
        if (_matchesExclude(relative, excludePatterns)) continue;
        allFiles.add(normalized);
      }
    }
    return allFiles;
  }

  static Future<List<String>> _detectEntrypoints(
    AnalyzerConfig config,
    String projectRoot,
    String libRoot,
  ) async {
    if (config.entrypoints.isNotEmpty) {
      return _resolveConfiguredEntrypoints(config.entrypoints, projectRoot);
    }
    return _autoDetectEntrypoints(libRoot);
  }

  static List<String> _resolveConfiguredEntrypoints(
      List<String> entrypoints, String projectRoot) {
    final result = <String>[];
    for (final ep in entrypoints) {
      final epPath = p.normalize(p.join(projectRoot, ep));
      if (File(epPath).existsSync()) result.add(epPath);
    }
    return result;
  }

  static Future<List<String>> _autoDetectEntrypoints(String libRoot) async {
    final entrypoints = <String>[];
    final libDir = Directory(libRoot);
    if (!libDir.existsSync()) return entrypoints;
    await for (final entity in libDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('main') && name.endsWith('.dart')) {
        entrypoints.add(p.normalize(entity.path));
      }
    }
    return entrypoints;
  }

  static ({
    Map<String, Set<String>> importGraph,
    Map<String, Set<String>> rawImports,
    Map<String, CompilationUnit> parsedUnits,
  }) _parseAndBuildGraph(List<String> files, _ImportResolver resolver) {
    final importGraph = <String, Set<String>>{};
    final rawImports = <String, Set<String>>{};
    final parsedUnits = <String, CompilationUnit>{};

    for (final file in files) {
      final unit = _tryParseFile(file);
      if (unit == null) {
        importGraph[file] = {};
        rawImports[file] = {};
        continue;
      }
      parsedUnits[file] = unit;
      final resolved = <String>{};
      final raw = <String>{};

      for (final directive in unit.directives) {
        if (directive is! UriBasedDirective) continue;
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        raw.add(uri);
        final resolvedPath = resolver.resolve(uri, file);
        if (resolvedPath != null && File(resolvedPath).existsSync()) {
          resolved.add(p.normalize(resolvedPath));
        }
      }

      importGraph[file] = resolved;
      rawImports[file] = raw;
    }

    return (
      importGraph: importGraph,
      rawImports: rawImports,
      parsedUnits: parsedUnits,
    );
  }

  static CompilationUnit? _tryParseFile(String file) {
    try {
      return parseFile(
        path: file,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;
    } catch (_) {
      return null;
    }
  }

  static bool _matchesExclude(
      String relativePath, Set<String> excludePatterns) {
    return matchesAnyGlob(relativePath, excludePatterns.toList());
  }

  static String? _extractPackageName(String pubspecContent) {
    try {
      final yaml = loadYaml(pubspecContent);
      if (yaml is YamlMap && yaml['name'] != null) {
        return yaml['name'].toString();
      }
    } catch (_) {}

    final regex = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true);
    final match = regex.firstMatch(pubspecContent);
    return match?.group(1);
  }
}

/// Resolves import URIs to absolute file paths within the project.
class _ImportResolver {
  final String projectRoot;
  final String packageName;

  _ImportResolver(this.projectRoot, this.packageName);

  String? resolve(String uri, String currentFile) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final parts = uri.substring(8).split('/');
      if (parts.isEmpty || parts.first != packageName) return null;
      return p.normalize(
          p.join(projectRoot, 'lib', parts.skip(1).join('/')));
    }
    return p.normalize(p.join(p.dirname(currentFile), uri));
  }
}
