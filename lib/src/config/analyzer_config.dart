import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../core/issue.dart';

/// Configuration for the analyzer, loaded from `analyzer.yaml`.
class AnalyzerConfig {
  /// Glob patterns for files to exclude from analysis.
  final List<String> excludePatterns;

  /// Entry point files (relative to project root).
  final List<String> entrypoints;

  /// Rule severity overrides: rule name → severity.
  final Map<String, Severity> ruleSeverities;

  /// Banned imports configuration.
  final List<BannedImportConfig> bannedImports;

  /// Banned symbols configuration.
  final List<BannedSymbolConfig> bannedSymbols;

  /// Layer dependency configuration.
  final LayerConfig? layerConfig;

  /// Feature isolation configuration.
  final FeatureIsolationConfig? featureIsolation;

  /// Metrics thresholds.
  final MetricsConfig metrics;

  /// AI slop detection configuration.
  final AiSlopConfig aiSlop;

  /// Extra directories to scan beyond `lib/` (e.g., `integration_test/`, `bin/`).
  final List<String> extraScanDirs;

  const AnalyzerConfig({
    this.excludePatterns = const [],
    this.entrypoints = const [],
    this.ruleSeverities = const {},
    this.bannedImports = const [],
    this.bannedSymbols = const [],
    this.layerConfig,
    this.featureIsolation,
    this.metrics = const MetricsConfig(),
    this.aiSlop = const AiSlopConfig(),
    this.extraScanDirs = const [],
  });

  /// Load config from a YAML file. Falls back to defaults if file doesn't exist.
  factory AnalyzerConfig.load(String projectRoot) {
    final configPath = p.join(projectRoot, 'analyzer.yaml');
    final file = File(configPath);

    if (!file.existsSync()) {
      return const AnalyzerConfig();
    }

    final content = file.readAsStringSync();
    final yaml = loadYaml(content);

    if (yaml is! YamlMap) {
      return const AnalyzerConfig();
    }

    return AnalyzerConfig._fromYaml(yaml);
  }

  factory AnalyzerConfig._fromYaml(YamlMap yaml) {
    // Exclude patterns
    final excludePatterns = <String>[];
    final excludeNode = yaml['exclude'];
    if (excludeNode is YamlList) {
      for (final item in excludeNode) {
        excludePatterns.add(item.toString());
      }
    }

    // Entrypoints
    final entrypoints = <String>[];
    final entryNode = yaml['entrypoints'];
    if (entryNode is YamlList) {
      for (final item in entryNode) {
        entrypoints.add(item.toString());
      }
    }

    // Extra scan dirs
    final extraScanDirs = <String>[];
    final extraNode = yaml['extra_scan_dirs'];
    if (extraNode is YamlList) {
      for (final item in extraNode) {
        extraScanDirs.add(item.toString());
      }
    }

    // Rule severities
    final ruleSeverities = <String, Severity>{};
    final rulesNode = yaml['rules'];
    if (rulesNode is YamlMap) {
      for (final entry in rulesNode.entries) {
        ruleSeverities[entry.key.toString()] =
            Severity.fromString(entry.value.toString());
      }
    }

    // Architecture
    BannedImportConfig parseBannedImport(YamlMap m) {
      final paths = <String>[];
      if (m['paths'] is YamlList) {
        for (final p in m['paths'] as YamlList) {
          paths.add(p.toString());
        }
      }
      final deny = <String>[];
      if (m['deny'] is YamlList) {
        for (final d in m['deny'] as YamlList) {
          deny.add(d.toString());
        }
      }
      return BannedImportConfig(
        paths: paths,
        deny: deny,
        message: m['message']?.toString() ?? '',
      );
    }

    final bannedImports = <BannedImportConfig>[];
    final archNode = yaml['architecture'];
    if (archNode is YamlMap) {
      final bannedNode = archNode['banned_imports'];
      if (bannedNode is YamlList) {
        for (final item in bannedNode) {
          if (item is YamlMap) {
            bannedImports.add(parseBannedImport(item));
          }
        }
      }
    }

    // Banned symbols
    final bannedSymbols = <BannedSymbolConfig>[];
    if (archNode is YamlMap) {
      final symbolsNode = archNode['banned_symbols'];
      if (symbolsNode is YamlList) {
        for (final item in symbolsNode) {
          if (item is YamlMap) {
            bannedSymbols.add(BannedSymbolConfig.fromYaml(item));
          }
        }
      }
    }

    // Layer config
    LayerConfig? layerConfig;
    if (archNode is YamlMap) {
      final layerNode = archNode['layers'];
      if (layerNode is YamlMap) {
        final layers = <String, LayerDefinition>{};
        for (final entry in layerNode.entries) {
          final name = entry.key.toString();
          final value = entry.value;
          if (value is YamlMap) {
            final paths = <String>[];
            if (value['paths'] is YamlList) {
              for (final p in value['paths'] as YamlList) {
                paths.add(p.toString());
              }
            }
            final canDependOn = <String>[];
            if (value['can_depend_on'] is YamlList) {
              for (final d in value['can_depend_on'] as YamlList) {
                canDependOn.add(d.toString());
              }
            }
            layers[name] = LayerDefinition(
              name: name,
              paths: paths,
              canDependOn: canDependOn,
            );
          }
        }
        if (layers.isNotEmpty) {
          layerConfig = LayerConfig(layers: layers);
        }
      }
    }

    // Feature isolation
    FeatureIsolationConfig? featureIsolation;
    if (archNode is YamlMap) {
      final fiNode = archNode['feature_isolation'];
      if (fiNode is YamlMap) {
        final enabled = fiNode['enabled'] == true;
        final paths = <String>[];
        if (fiNode['paths'] is YamlList) {
          for (final p in fiNode['paths'] as YamlList) {
            paths.add(p.toString());
          }
        }
        final allowShared = <String>[];
        if (fiNode['allow_shared'] is YamlList) {
          for (final s in fiNode['allow_shared'] as YamlList) {
            allowShared.add(s.toString());
          }
        }
        final exceptions = <FeatureException>[];
        if (fiNode['exceptions'] is YamlList) {
          for (final e in fiNode['exceptions'] as YamlList) {
            if (e is YamlMap) {
              final allow = <String>[];
              if (e['allow'] is YamlList) {
                for (final a in e['allow'] as YamlList) {
                  allow.add(a.toString());
                }
              }
              exceptions.add(FeatureException(
                from: e['from']?.toString() ?? '',
                allow: allow,
              ));
            }
          }
        }
        featureIsolation = FeatureIsolationConfig(
          enabled: enabled,
          paths: paths,
          allowShared: allowShared,
          exceptions: exceptions,
        );
      }
    }

    // Metrics
    final metricsNode = yaml['metrics'];
    MetricsConfig metrics = const MetricsConfig();
    if (metricsNode is YamlMap) {
      metrics = MetricsConfig(
        cyclomaticComplexityWarning:
            _intOr(metricsNode['cyclomatic_complexity'], 'warning', 10),
        cyclomaticComplexityError:
            _intOr(metricsNode['cyclomatic_complexity'], 'error', 20),
        linesPerFileWarning:
            _intOr(metricsNode['lines_per_file'], 'warning', 300),
        linesPerFileError:
            _intOr(metricsNode['lines_per_file'], 'error', 600),
        linesPerMethodWarning:
            _intOr(metricsNode['lines_per_method'], 'warning', 50),
        linesPerMethodError:
            _intOr(metricsNode['lines_per_method'], 'error', 100),
        maxParametersWarning:
            _intOr(metricsNode['max_parameters'], 'warning', 4),
        maxParametersError:
            _intOr(metricsNode['max_parameters'], 'error', 7),
        maxNestingWarning:
            _intOr(metricsNode['max_nesting'], 'warning', 4),
        maxNestingError:
            _intOr(metricsNode['max_nesting'], 'error', 6),
        buildMethodLocWarning:
            _intOr(metricsNode['build_method_loc'], 'warning', 30),
        buildMethodLocError:
            _intOr(metricsNode['build_method_loc'], 'error', 60),
        buildMethodBranchesWarning:
            _intOr(metricsNode['build_method_branches'], 'warning', 3),
        buildMethodBranchesError:
            _intOr(metricsNode['build_method_branches'], 'error', 6),
      );
    }

    return AnalyzerConfig(
      excludePatterns: excludePatterns,
      entrypoints: entrypoints,
      ruleSeverities: ruleSeverities,
      bannedImports: bannedImports,
      bannedSymbols: bannedSymbols,
      layerConfig: layerConfig,
      featureIsolation: featureIsolation,
      metrics: metrics,
      aiSlop: AiSlopConfig.fromYaml(yaml['ai_slop']),
      extraScanDirs: extraScanDirs,
    );
  }

  static int _intOr(dynamic node, String key, int defaultValue) {
    if (node is YamlMap && node[key] != null) {
      return int.tryParse(node[key].toString()) ?? defaultValue;
    }
    return defaultValue;
  }
}

/// Configuration for a single banned-symbol rule.
class BannedSymbolConfig {
  /// Glob patterns for files this rule applies to.
  final List<String> paths;

  /// Symbol names that are banned (e.g. 'ElevatedButton', 'showDialog').
  final List<String> deny;

  /// Suggested replacement symbol (informational).
  final String suggest;

  /// Message to display when the rule is violated.
  final String message;

  const BannedSymbolConfig({
    required this.paths,
    required this.deny,
    this.suggest = '',
    this.message = '',
  });

  factory BannedSymbolConfig.fromYaml(YamlMap m) {
    final paths = <String>[];
    if (m['paths'] is YamlList) {
      for (final p in m['paths'] as YamlList) {
        paths.add(p.toString());
      }
    }
    final deny = <String>[];
    if (m['deny'] is YamlList) {
      for (final d in m['deny'] as YamlList) {
        deny.add(d.toString());
      }
    }
    return BannedSymbolConfig(
      paths: paths,
      deny: deny,
      suggest: m['suggest']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
    );
  }
}

/// Configuration for a single banned-import rule.
class BannedImportConfig {
  /// Glob patterns for files this rule applies to.
  final List<String> paths;

  /// Glob patterns for imports that are banned.
  final List<String> deny;

  /// Message to display when the rule is violated.
  final String message;

  const BannedImportConfig({
    required this.paths,
    required this.deny,
    required this.message,
  });
}

/// Configuration for layer dependency validation.
class LayerConfig {
  final Map<String, LayerDefinition> layers;

  const LayerConfig({required this.layers});
}

/// Definition of a single architectural layer.
class LayerDefinition {
  final String name;
  final List<String> paths;
  final List<String> canDependOn;

  const LayerDefinition({
    required this.name,
    required this.paths,
    required this.canDependOn,
  });
}

/// Configuration for feature isolation enforcement.
class FeatureIsolationConfig {
  final bool enabled;
  final List<String> paths;
  final List<String> allowShared;
  final List<FeatureException> exceptions;

  const FeatureIsolationConfig({
    this.enabled = true,
    this.paths = const [],
    this.allowShared = const [],
    this.exceptions = const [],
  });
}

/// An exception to the feature isolation rule.
class FeatureException {
  final String from;
  final List<String> allow;

  const FeatureException({required this.from, required this.allow});
}

/// Metrics threshold configuration.
class MetricsConfig {
  final int cyclomaticComplexityWarning;
  final int cyclomaticComplexityError;
  final int linesPerFileWarning;
  final int linesPerFileError;
  final int linesPerMethodWarning;
  final int linesPerMethodError;
  final int maxParametersWarning;
  final int maxParametersError;
  final int maxNestingWarning;
  final int maxNestingError;
  final int buildMethodLocWarning;
  final int buildMethodLocError;
  final int buildMethodBranchesWarning;
  final int buildMethodBranchesError;

  const MetricsConfig({
    this.cyclomaticComplexityWarning = 10,
    this.cyclomaticComplexityError = 20,
    this.linesPerFileWarning = 300,
    this.linesPerFileError = 600,
    this.linesPerMethodWarning = 50,
    this.linesPerMethodError = 100,
    this.maxParametersWarning = 4,
    this.maxParametersError = 7,
    this.maxNestingWarning = 4,
    this.maxNestingError = 6,
    this.buildMethodLocWarning = 30,
    this.buildMethodLocError = 60,
    this.buildMethodBranchesWarning = 3,
    this.buildMethodBranchesError = 6,
  });
}

/// Configuration for AI slop detection rules.
class AiSlopConfig {
  final EmptyCatchConfig emptyCatch;
  final GenericNamingConfig genericNaming;
  final DeadTodosConfig deadTodos;
  final VerboseLoggingConfig verboseLogging;
  final SingleMethodClassConfig singleMethodClass;

  const AiSlopConfig({
    this.emptyCatch = const EmptyCatchConfig(),
    this.genericNaming = const GenericNamingConfig(),
    this.deadTodos = const DeadTodosConfig(),
    this.verboseLogging = const VerboseLoggingConfig(),
    this.singleMethodClass = const SingleMethodClassConfig(),
  });

  factory AiSlopConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const AiSlopConfig();
    return AiSlopConfig(
      emptyCatch: EmptyCatchConfig.fromYaml(node['empty_catch']),
      genericNaming: GenericNamingConfig.fromYaml(node['generic_naming']),
      deadTodos: DeadTodosConfig.fromYaml(node['dead_todos']),
      verboseLogging: VerboseLoggingConfig.fromYaml(node['verbose_logging']),
      singleMethodClass:
          SingleMethodClassConfig.fromYaml(node['single_method_class']),
    );
  }
}

class EmptyCatchConfig {
  final bool allowEmptyWithComment;
  final bool flagPrintOnly;

  const EmptyCatchConfig({
    this.allowEmptyWithComment = true,
    this.flagPrintOnly = true,
  });

  factory EmptyCatchConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const EmptyCatchConfig();
    return EmptyCatchConfig(
      allowEmptyWithComment: node['allow_empty_with_comment'] as bool? ?? true,
      flagPrintOnly: node['flag_print_only'] as bool? ?? true,
    );
  }
}

class GenericNamingConfig {
  final Set<String> denyVariableNames;
  final Set<String> denyFunctionNames;
  final bool allowInLoops;
  final bool allowInLambdas;

  static const _defaultDenyVars = {
    'data', 'result', 'value', 'item', 'element', 'obj',
    'temp', 'tmp', 'output', 'input', 'response', 'res', 'ret', 'val',
  };

  static const _defaultDenyFuncs = {
    'processData', 'handleData', 'getData', 'processItems',
    'handleResult', 'executeTask', 'doWork', 'runProcess',
  };

  const GenericNamingConfig({
    this.denyVariableNames = _defaultDenyVars,
    this.denyFunctionNames = _defaultDenyFuncs,
    this.allowInLoops = true,
    this.allowInLambdas = true,
  });

  factory GenericNamingConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const GenericNamingConfig();
    return GenericNamingConfig(
      denyVariableNames: _readStringSet(
        node['deny_variable_names'],
        GenericNamingConfig._defaultDenyVars,
      ),
      denyFunctionNames: _readStringSet(
        node['deny_function_names'],
        GenericNamingConfig._defaultDenyFuncs,
      ),
      allowInLoops: node['allow_in_loops'] as bool? ?? true,
      allowInLambdas: node['allow_in_lambdas'] as bool? ?? true,
    );
  }

  static Set<String> _readStringSet(dynamic node, Set<String> defaults) {
    if (node is! YamlList) return defaults;
    return node.map((e) => e.toString()).toSet();
  }
}

class DeadTodosConfig {
  final int minContextWords;
  final bool requireReference;
  final List<String> vaguePhrases;

  static const _defaultVaguePhrases = [
    'fix later', 'improve', 'clean up', 'refactor',
    'handle edge cases', 'add more', 'make better', 'temporary',
  ];

  const DeadTodosConfig({
    this.minContextWords = 5,
    this.requireReference = false,
    this.vaguePhrases = _defaultVaguePhrases,
  });

  factory DeadTodosConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const DeadTodosConfig();
    return DeadTodosConfig(
      minContextWords: int.tryParse(
            node['min_context_words']?.toString() ?? '',
          ) ?? 5,
      requireReference: node['require_reference'] as bool? ?? false,
      vaguePhrases: node['vague_phrases'] is YamlList
          ? (node['vague_phrases'] as YamlList)
              .map((e) => e.toString())
              .toList()
          : _defaultVaguePhrases,
    );
  }
}

class VerboseLoggingConfig {
  final int maxConsecutiveLogs;
  final Set<String> logFunctions;

  static const _defaultLogFunctions = {
    'log', 'print', 'debugPrint',
    'logger.info', 'logger.warning', 'logger.error',
    'logger.fine', 'logger.severe', 'logger.shout',
  };

  const VerboseLoggingConfig({
    this.maxConsecutiveLogs = 3,
    this.logFunctions = _defaultLogFunctions,
  });

  factory VerboseLoggingConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const VerboseLoggingConfig();
    return VerboseLoggingConfig(
      maxConsecutiveLogs: int.tryParse(
            node['max_consecutive_logs']?.toString() ?? '',
          ) ?? 3,
      logFunctions: node['log_functions'] is YamlList
          ? (node['log_functions'] as YamlList)
              .map((e) => e.toString())
              .toSet()
          : _defaultLogFunctions,
    );
  }
}

class SingleMethodClassConfig {
  final bool ignoreIfExtends;
  final bool ignoreIfHasConstructorParams;

  const SingleMethodClassConfig({
    this.ignoreIfExtends = true,
    this.ignoreIfHasConstructorParams = true,
  });

  factory SingleMethodClassConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const SingleMethodClassConfig();
    return SingleMethodClassConfig(
      ignoreIfExtends: node['ignore_if_extends'] as bool? ?? true,
      ignoreIfHasConstructorParams:
          node['ignore_if_has_constructor_params'] as bool? ?? true,
    );
  }
}
