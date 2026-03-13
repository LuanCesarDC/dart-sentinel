import 'package:path/path.dart' as p;

import '../core/project_context.dart';
import '../utils/graph_utils.dart';

/// Generates a dependency map of the project in various formats.
class DependencyMapper {
  final ProjectContext context;

  DependencyMapper(this.context);

  /// Generate a Mermaid diagram of the import graph.
  ///
  /// Groups files by directory (layer/feature) and shows
  /// inter-group dependencies with edge counts.
  String toMermaid({bool showFiles = false}) {
    final buffer = StringBuffer();
    buffer.writeln('graph TD');

    if (showFiles) {
      _mermaidFileLevel(buffer);
    } else {
      _mermaidModuleLevel(buffer);
    }

    return buffer.toString();
  }

  /// Generate a text-based summary of the dependency structure.
  String toTextSummary() {
    final buffer = StringBuffer();
    final reversed = reverseGraph(context.importGraph);
    final modules = _buildModuleGraph();

    buffer.writeln('Dependency Map');
    buffer.writeln('${'═' * 60}');
    buffer.writeln('');
    buffer.writeln(
        'Files: ${context.allFiles.length}  '
        'Modules: ${modules.keys.length}  '
        'Edges: ${_totalEdges()}');
    buffer.writeln('');

    // Module summary
    buffer.writeln('Modules:');
    final sortedModules = modules.keys.toList()..sort();
    for (final mod in sortedModules) {
      final fileCount =
          _filesInModule(mod).length;
      final deps = modules[mod]!;
      final depStr = deps.isEmpty ? '(no dependencies)' : '→ ${deps.join(', ')}';
      buffer.writeln('  $mod ($fileCount files) $depStr');
    }
    buffer.writeln('');

    // Hot spots
    buffer.writeln('Hot Spots (most dependents):');
    final spots = <_Spot>[];
    for (final file in context.allFiles) {
      final direct = reversed[file]?.length ?? 0;
      if (direct > 0) {
        spots.add(_Spot(context.relativePath(file), direct));
      }
    }
    spots.sort((a, b) => b.count.compareTo(a.count));
    for (final spot in spots.take(10)) {
      buffer.writeln('  ${spot.count.toString().padLeft(3)} ← ${spot.file}');
    }

    // Isolated clusters
    final reachable = reachableFromAll(
      context.entrypoints,
      context.importGraph,
    );
    final isolated = context.allFiles
        .where((f) => !reachable.contains(f))
        .map((f) => context.relativePath(f))
        .toList()..sort();
    if (isolated.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Isolated files (${isolated.length}):');
      for (final f in isolated) {
        buffer.writeln('  $f');
      }
    }

    return buffer.toString();
  }

  void _mermaidModuleLevel(StringBuffer buffer) {
    final modules = _buildModuleGraph();
    final ids = <String, String>{};
    var counter = 0;

    for (final mod in modules.keys) {
      final id = 'M${counter++}';
      ids[mod] = id;
      final fileCount = _filesInModule(mod).length;
      buffer.writeln('    $id["$mod\\n($fileCount files)"]');
    }

    buffer.writeln('');

    // Edges between modules
    final seen = <String>{};
    for (final entry in modules.entries) {
      final fromId = ids[entry.key]!;
      for (final dep in entry.value) {
        final toId = ids[dep];
        if (toId == null) continue;
        final edgeKey = '$fromId->$toId';
        if (seen.contains(edgeKey)) continue;
        seen.add(edgeKey);
        buffer.writeln('    $fromId --> $toId');
      }
    }
  }

  void _mermaidFileLevel(StringBuffer buffer) {
    final ids = <String, String>{};
    var counter = 0;

    // Group into subgraphs by directory
    final byModule = <String, List<String>>{};
    for (final file in context.allFiles) {
      final rel = context.relativePath(file);
      final mod = _moduleOf(rel);
      byModule.putIfAbsent(mod, () => []).add(file);
    }

    for (final entry in byModule.entries) {
      buffer.writeln('    subgraph ${_sanitize(entry.key)}');
      for (final file in entry.value) {
        final id = 'F${counter++}';
        ids[file] = id;
        final rel = context.relativePath(file);
        final name = p.basename(rel);
        buffer.writeln('        $id["$name"]');
      }
      buffer.writeln('    end');
    }

    buffer.writeln('');

    // Edges (only cross-module to keep it readable)
    for (final entry in context.importGraph.entries) {
      final fromId = ids[entry.key];
      if (fromId == null) continue;
      final fromMod = _moduleOf(context.relativePath(entry.key));
      for (final dep in entry.value) {
        final toId = ids[dep];
        if (toId == null) continue;
        final toMod = _moduleOf(context.relativePath(dep));
        if (fromMod != toMod) {
          buffer.writeln('    $fromId --> $toId');
        }
      }
    }
  }

  /// Build module-level dependency graph.
  Map<String, Set<String>> _buildModuleGraph() {
    final modules = <String, Set<String>>{};

    for (final entry in context.importGraph.entries) {
      final fromMod = _moduleOf(context.relativePath(entry.key));
      modules.putIfAbsent(fromMod, () => <String>{});

      for (final dep in entry.value) {
        final toMod = _moduleOf(context.relativePath(dep));
        if (toMod != fromMod) {
          modules[fromMod]!.add(toMod);
        }
      }
    }

    return modules;
  }

  List<String> _filesInModule(String module) {
    return context.allFiles
        .where((f) => _moduleOf(context.relativePath(f)) == module)
        .toList();
  }

  int _totalEdges() {
    return context.importGraph.values.fold<int>(0, (s, v) => s + v.length);
  }

  String _moduleOf(String relativePath) {
    final parts = relativePath.split('/');
    if (parts.length >= 3 && parts[0] == 'lib' && parts[1] == 'src') {
      return 'lib/src/${parts[2]}';
    }
    if (parts.length >= 2 && parts[0] == 'lib') {
      return 'lib';
    }
    return parts[0]; // bin, test, etc.
  }

  String _sanitize(String name) {
    return name.replaceAll('/', '_').replaceAll('.', '_');
  }
}

class _Spot {
  final String file;
  final int count;
  _Spot(this.file, this.count);
}
