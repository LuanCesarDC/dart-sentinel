/// Folder names (lowercase) whose presence under `lib/` hints at a template.
const Map<String, Set<String>> _templateSignals = {
  'flutter_official': {'ui', 'data', 'domain', 'routing'},
  'clean_architecture': {'domain', 'data', 'presentation'},
  'clean_bloc': {'features', 'domain', 'presentation', 'bloc'},
  'bloc': {'bloc', 'blocs', 'cubit', 'cubits'},
  'riverpod': {'providers', 'riverpod', 'features'},
  'provider': {'providers', 'screens', 'services'},
  'mvvm_repository_service': {
    'viewmodels',
    'view_models',
    'repositories',
    'services',
    'views',
  },
  'mvc': {'controllers', 'views', 'models'},
  'ddd': {'domain', 'application', 'infrastructure'},
  'stacked': {'ui', 'services', 'app'},
  'modular': {'modules', 'shared'},
  'getx': {'modules', 'bindings', 'controllers'},
};

const _matchWeight = 100;

const String fallbackTemplate = 'starter';

/// Picks the template whose expected folders overlap most with [libFolders].
///
/// Returns [fallbackTemplate] when fewer than two folders match, since a
/// single shared name (`services`) says too little about the architecture.
String recommendTemplate(Iterable<String> libFolders) {
  final folders = libFolders.map((f) => f.toLowerCase()).toSet();
  var best = fallbackTemplate;
  var bestScore = 1;
  for (final entry in _templateSignals.entries) {
    final matched = entry.value.intersection(folders).length;
    final score = matched * _matchWeight - (entry.value.length - matched);
    if (matched >= 2 && score > bestScore) {
      best = entry.key;
      bestScore = score;
    }
  }
  return best;
}
