import '../utils/glob_matcher.dart';
import 'analyzer_config.dart';

/// Warnings about layers that match no file and `lib/` folders that fall
/// outside every layer — the usual sign of a template that doesn't fit the
/// project's real structure.
List<String> layerCoverageWarnings(
  AnalyzerConfig config,
  Iterable<String> relativeFiles,
) {
  final layerConfig = config.layerConfig;
  if (layerConfig == null) return const [];

  final libFiles = relativeFiles
      .where((file) => file.startsWith('lib/'))
      .toList();
  final warnings = <String>[];
  final coveredFiles = <String>{};

  for (final layer in layerConfig.layers.values) {
    final matches = libFiles
        .where((file) => matchesAnyGlob(file, layer.paths))
        .toList();
    if (matches.isEmpty) {
      warnings.add(
        "layer '${layer.name}' matches no file (paths: ${layer.paths.join(', ')})",
      );
    }
    coveredFiles.addAll(matches);
  }

  final uncoveredFolders = <String>{
    for (final file in libFiles)
      if (!coveredFiles.contains(file) && _topFolder(file) != null)
        _topFolder(file)!,
  };
  for (final folder in uncoveredFolders.toList()..sort()) {
    warnings.add('$folder/ is outside every layer — its imports are unchecked');
  }
  return warnings;
}

/// First folder under `lib/` (or under `lib/src/`, the common wrapper).
const _plainDepth = 2;
const _srcWrappedDepth = 3;

String? _topFolder(String libRelativePath) {
  final segments = libRelativePath.split('/');
  final depth = segments.length > 1 && segments[1] == 'src'
      ? _srcWrappedDepth
      : _plainDepth;
  return segments.length > depth ? segments.take(depth).join('/') : null;
}
