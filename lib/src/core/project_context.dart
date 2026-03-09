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
  ///
  /// If [targetPath] is provided, only that subdirectory (under lib/) is scanned
  /// for metrics, but the full graph is still built for dead-file analysis.
  static Future<ProjectContext> build(
    String projectRoot, {
    String? targetPath,
  }) async {
    // Read pubspec
    final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw StateError('pubspec.yaml not found at $projectRoot');
    }
    final pubspecContent = pubspecFile.readAsStringSync();
    final packageName = _extractPackageName(pubspecContent);
    if (packageName == null) {
      throw StateError('Could not determine package name from pubspec.yaml');
    }

    final libRoot = p.join(projectRoot, 'lib');

    // Load config
    final config = AnalyzerConfig.load(projectRoot);

    // Collect all exclude patterns (config + default generated patterns)
    final excludePatterns = <String>{
      '**/*.g.dart',
      '**/*.freezed.dart',
      '**/*.gr.dart',
      '**/*.g2.dart',
      '**/*.mocks.dart',
      '**/*.config.dart',
      '**/*.mapper.dart',
      ...config.excludePatterns,
    };

    // Collect all Dart files
    final allFiles = <String>[];
    final dirsToScan = <Directory>[Directory(libRoot)];

    // Add extra scan dirs
    for (final extra in config.extraScanDirs) {
      final dir = Directory(p.join(projectRoot, extra));
      if (dir.existsSync()) {
        dirsToScan.add(dir);
      }
    }

    for (final dir in dirsToScan) {
      if (!dir.existsSync()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final normalized = p.normalize(entity.path);
          final relative = p.relative(normalized, from: projectRoot);

          // Skip excluded files
          if (_matchesExclude(relative, excludePatterns)) continue;

          allFiles.add(normalized);
        }
      }
    }

    // Find entrypoints
    final entrypoints = <String>[];
    if (config.entrypoints.isNotEmpty) {
      for (final ep in config.entrypoints) {
        final epPath = p.normalize(p.join(projectRoot, ep));
        if (File(epPath).existsSync()) {
          entrypoints.add(epPath);
        }
      }
    } else {
      // Auto-detect: main*.dart in lib/
      final libDir = Directory(libRoot);
      if (libDir.existsSync()) {
        await for (final entity in libDir.list()) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('main') && name.endsWith('.dart')) {
              entrypoints.add(p.normalize(entity.path));
            }
          }
        }
      }
    }

    // Parse all files and build import graph
    final importGraph = <String, Set<String>>{};
    final rawImports = <String, Set<String>>{};
    final parsedUnits = <String, CompilationUnit>{};

    for (final file in allFiles) {
      try {
        final result = parseFile(
          path: file,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
        parsedUnits[file] = result.unit;

        final imports = <String>{};
        final rawUris = <String>{};

        for (final directive in result.unit.directives) {
          if (directive is UriBasedDirective) {
            final uri = directive.uri.stringValue;
            if (uri == null) continue;

            rawUris.add(uri);

            final resolved = _resolveImport(
              uri,
              file,
              projectRoot,
              packageName,
            );

            if (resolved != null && File(resolved).existsSync()) {
              imports.add(p.normalize(resolved));
            }
          }
        }

        importGraph[file] = imports;
        rawImports[file] = rawUris;
      } catch (_) {
        // Skip unparseable files
        importGraph[file] = {};
        rawImports[file] = {};
      }
    }

    return ProjectContext._(
      packageName: packageName,
      projectRoot: projectRoot,
      libRoot: libRoot,
      entrypoints: entrypoints,
      excludePatterns: excludePatterns,
      importGraph: importGraph,
      rawImports: rawImports,
      parsedUnits: parsedUnits,
      allFiles: allFiles,
      config: config,
    );
  }

  /// Get the relative path of a file from the project root.
  String relativePath(String absolutePath) {
    return p.relative(absolutePath, from: projectRoot);
  }

  /// Check if a file path (relative to projectRoot) matches any exclude pattern.
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

    // Fallback: regex
    final regex = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true);
    final match = regex.firstMatch(pubspecContent);
    return match?.group(1);
  }

  static String? _resolveImport(
    String uri,
    String currentFile,
    String projectRoot,
    String packageName,
  ) {
    if (uri.startsWith('dart:')) return null;

    if (uri.startsWith('package:')) {
      final parts = uri.substring(8).split('/');
      if (parts.isEmpty) return null;

      final pkg = parts.first;
      if (pkg != packageName) return null;

      final relative = parts.skip(1).join('/');
      return p.normalize(p.join(projectRoot, 'lib', relative));
    }

    // Relative import
    return p.normalize(p.join(p.dirname(currentFile), uri));
  }
}
