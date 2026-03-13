import 'package:path/path.dart' as p;

import '../core/project_context.dart';
import '../utils/graph_utils.dart';

/// Analyzes the impact of changing a set of files.
///
/// Given a list of changed files, computes the transitive set of
/// all files that depend on them (directly or transitively).
class ImpactAnalyzer {
  final ProjectContext context;

  ImpactAnalyzer(this.context);

  /// Compute impact of changing [changedFiles].
  ///
  /// Returns an [ImpactReport] with the full transitive dependent set.
  ImpactReport analyze(List<String> changedFiles) {
    final reversed = reverseGraph(context.importGraph);
    final resolved = _resolveFiles(changedFiles);
    final allAffected = <String>{};

    for (final file in resolved) {
      final dependents = reachableFrom(file, reversed);
      dependents.remove(file); // don't count the file itself
      allAffected.addAll(dependents);
    }

    // Compute direct dependents (depth 1) for each changed file
    final directDeps = <String, Set<String>>{};
    for (final file in resolved) {
      directDeps[file] = reversed[file] ?? {};
    }

    // Categorize affected files by relative path patterns
    final categorized = _categorize(allAffected);

    return ImpactReport(
      changedFiles: resolved.map((f) => context.relativePath(f)).toList(),
      totalAffected: allAffected.length,
      totalFiles: context.allFiles.length,
      directDependents: directDeps.map(
        (k, v) => MapEntry(
          context.relativePath(k),
          v.map((f) => context.relativePath(f)).toSet(),
        ),
      ),
      affectedByCategory: categorized,
      affectedFiles:
          allAffected.map((f) => context.relativePath(f)).toList()..sort(),
    );
  }

  /// Compute "hot spots" — files with the most dependents.
  List<HotSpot> hotSpots({int top = 20}) {
    final reversed = reverseGraph(context.importGraph);
    final spots = <HotSpot>[];

    for (final file in context.allFiles) {
      final transitive = reachableFrom(file, reversed);
      transitive.remove(file);
      final direct = reversed[file]?.length ?? 0;
      if (transitive.isNotEmpty) {
        spots.add(HotSpot(
          file: context.relativePath(file),
          directDependents: direct,
          transitiveDependents: transitive.length,
        ));
      }
    }

    spots.sort(
        (a, b) => b.transitiveDependents.compareTo(a.transitiveDependents));
    return spots.take(top).toList();
  }

  List<String> _resolveFiles(List<String> files) {
    return files.map((f) {
      if (p.isAbsolute(f)) return f;
      return p.normalize(p.join(context.projectRoot, f));
    }).where((f) => context.importGraph.containsKey(f)).toList();
  }

  Map<String, int> _categorize(Set<String> files) {
    final categories = <String, int>{};
    for (final file in files) {
      final rel = context.relativePath(file);
      final cat = _inferCategory(rel);
      categories[cat] = (categories[cat] ?? 0) + 1;
    }
    return categories;
  }

  String _inferCategory(String relativePath) {
    final parts = relativePath.split('/');
    if (parts.length >= 3 && parts[0] == 'lib' && parts[1] == 'src') {
      return parts[2]; // e.g. 'rules', 'core', 'config', 'mcp'
    }
    if (parts.length >= 3 && parts[0] == 'lib') {
      return parts[1]; // e.g. 'features', 'services', 'core'
    }
    if (parts[0] == 'bin') return 'bin';
    if (parts[0] == 'test') return 'test';
    return 'other';
  }
}

/// Result of an impact analysis.
class ImpactReport {
  final List<String> changedFiles;
  final int totalAffected;
  final int totalFiles;
  final Map<String, Set<String>> directDependents;
  final Map<String, int> affectedByCategory;
  final List<String> affectedFiles;

  const ImpactReport({
    required this.changedFiles,
    required this.totalAffected,
    required this.totalFiles,
    required this.directDependents,
    required this.affectedByCategory,
    required this.affectedFiles,
  });

  double get impactPercent =>
      totalFiles > 0 ? (totalAffected / totalFiles) * 100 : 0;
}

/// A file with many dependents — high blast radius.
class HotSpot {
  final String file;
  final int directDependents;
  final int transitiveDependents;

  const HotSpot({
    required this.file,
    required this.directDependents,
    required this.transitiveDependents,
  });
}
