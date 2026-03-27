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

  /// Model code generation configuration.
  final ModelsConfig modelsConfig;

  /// Testing enforcement configuration.
  final TestingConfig testingConfig;

  /// Banned dependency package names for pubspec validation.
  final Set<String> bannedDependencies;

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
    this.modelsConfig = const ModelsConfig(),
    this.testingConfig = const TestingConfig(),
    this.bannedDependencies = const {},
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
        ruleSeverities[entry.key.toString()] = Severity.fromString(
          entry.value.toString(),
        );
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
              exceptions.add(
                FeatureException(
                  from: e['from']?.toString() ?? '',
                  allow: allow,
                ),
              );
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
        cyclomaticComplexityWarning: _intOr(
          metricsNode['cyclomatic_complexity'],
          'warning',
          10,
        ),
        cyclomaticComplexityError: _intOr(
          metricsNode['cyclomatic_complexity'],
          'error',
          20,
        ),
        linesPerFileWarning: _intOr(
          metricsNode['lines_per_file'],
          'warning',
          300,
        ),
        linesPerFileError: _intOr(metricsNode['lines_per_file'], 'error', 600),
        linesPerMethodWarning: _intOr(
          metricsNode['lines_per_method'],
          'warning',
          50,
        ),
        linesPerMethodError: _intOr(
          metricsNode['lines_per_method'],
          'error',
          100,
        ),
        maxParametersWarning: _intOr(
          metricsNode['max_parameters'],
          'warning',
          4,
        ),
        maxParametersError: _intOr(metricsNode['max_parameters'], 'error', 7),
        maxNestingWarning: _intOr(metricsNode['max_nesting'], 'warning', 4),
        maxNestingError: _intOr(metricsNode['max_nesting'], 'error', 6),
        buildMethodLocWarning: _intOr(
          metricsNode['build_method_loc'],
          'warning',
          30,
        ),
        buildMethodLocError: _intOr(
          metricsNode['build_method_loc'],
          'error',
          60,
        ),
        buildMethodBranchesWarning: _intOr(
          metricsNode['build_method_branches'],
          'warning',
          3,
        ),
        buildMethodBranchesError: _intOr(
          metricsNode['build_method_branches'],
          'error',
          6,
        ),
        numberOfMethodsWarning: _intOr(
          metricsNode['number_of_methods'],
          'warning',
          15,
        ),
        numberOfMethodsError: _intOr(
          metricsNode['number_of_methods'],
          'error',
          30,
        ),
        weightedMethodsPerClassWarning: _intOr(
          metricsNode['weighted_methods_per_class'],
          'warning',
          30,
        ),
        weightedMethodsPerClassError: _intOr(
          metricsNode['weighted_methods_per_class'],
          'error',
          60,
        ),
        linesPerClassWarning: _intOr(
          metricsNode['lines_per_class'],
          'warning',
          200,
        ),
        linesPerClassError: _intOr(
          metricsNode['lines_per_class'],
          'error',
          500,
        ),
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
      modelsConfig: ModelsConfig.fromYaml(yaml['models']),
      testingConfig: TestingConfig.fromYaml(yaml['testing']),
      bannedDependencies: _parseStringSet(yaml['banned_dependencies']),
    );
  }

  static Set<String> _parseStringSet(dynamic node) {
    if (node is YamlList) {
      return node.map((e) => e.toString()).toSet();
    }
    return const {};
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
  final int numberOfMethodsWarning;
  final int numberOfMethodsError;
  final int weightedMethodsPerClassWarning;
  final int weightedMethodsPerClassError;
  final int linesPerClassWarning;
  final int linesPerClassError;

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
    this.numberOfMethodsWarning = 15,
    this.numberOfMethodsError = 30,
    this.weightedMethodsPerClassWarning = 30,
    this.weightedMethodsPerClassError = 60,
    this.linesPerClassWarning = 200,
    this.linesPerClassError = 500,
  });
}

/// Configuration for AI slop detection rules.
class AiSlopConfig {
  final EmptyCatchConfig emptyCatch;
  final GenericNamingConfig genericNaming;
  final DeadTodosConfig deadTodos;
  final VerboseLoggingConfig verboseLogging;
  final SingleMethodClassConfig singleMethodClass;
  final LazyNullCheckConfig lazyNullCheck;

  const AiSlopConfig({
    this.emptyCatch = const EmptyCatchConfig(),
    this.genericNaming = const GenericNamingConfig(),
    this.deadTodos = const DeadTodosConfig(),
    this.verboseLogging = const VerboseLoggingConfig(),
    this.singleMethodClass = const SingleMethodClassConfig(),
    this.lazyNullCheck = const LazyNullCheckConfig(),
  });

  factory AiSlopConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const AiSlopConfig();
    return AiSlopConfig(
      emptyCatch: EmptyCatchConfig.fromYaml(node['empty_catch']),
      genericNaming: GenericNamingConfig.fromYaml(node['generic_naming']),
      deadTodos: DeadTodosConfig.fromYaml(node['dead_todos']),
      verboseLogging: VerboseLoggingConfig.fromYaml(node['verbose_logging']),
      singleMethodClass: SingleMethodClassConfig.fromYaml(
        node['single_method_class'],
      ),
      lazyNullCheck: LazyNullCheckConfig.fromYaml(node['lazy_null_check']),
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
    'data',
    'result',
    'value',
    'item',
    'element',
    'obj',
    'temp',
    'tmp',
    'output',
    'input',
    'response',
    'res',
    'ret',
    'val',
  };

  static const _defaultDenyFuncs = {
    'processData',
    'handleData',
    'getData',
    'processItems',
    'handleResult',
    'executeTask',
    'doWork',
    'runProcess',
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
    'fix later',
    'improve',
    'clean up',
    'refactor',
    'handle edge cases',
    'add more',
    'make better',
    'temporary',
  ];

  const DeadTodosConfig({
    this.minContextWords = 5,
    this.requireReference = false,
    this.vaguePhrases = _defaultVaguePhrases,
  });

  factory DeadTodosConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const DeadTodosConfig();
    return DeadTodosConfig(
      minContextWords:
          int.tryParse(node['min_context_words']?.toString() ?? '') ?? 5,
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
    'log',
    'print',
    'debugPrint',
    'logger.info',
    'logger.warning',
    'logger.error',
    'logger.fine',
    'logger.severe',
    'logger.shout',
  };

  const VerboseLoggingConfig({
    this.maxConsecutiveLogs = 3,
    this.logFunctions = _defaultLogFunctions,
  });

  factory VerboseLoggingConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const VerboseLoggingConfig();
    return VerboseLoggingConfig(
      maxConsecutiveLogs:
          int.tryParse(node['max_consecutive_logs']?.toString() ?? '') ?? 3,
      logFunctions: node['log_functions'] is YamlList
          ? (node['log_functions'] as YamlList).map((e) => e.toString()).toSet()
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

/// Configuration for lazy null check detection.
class LazyNullCheckConfig {
  /// Flag `x ?? ""` and `x ?? ''`.
  final bool flagEmptyString;

  /// Flag `x ?? 0` and `x ?? 0.0`.
  final bool flagZero;

  /// Flag `x ?? false`.
  final bool flagFalse;

  /// Flag `x ?? []` and `x ?? {}`.
  final bool flagEmptyCollection;

  /// Ignore `map[key] ?? default` — Map subscript is nullable by design.
  final bool ignoreMapAccess;

  /// Ignore `expr?.prop ?? default` — null-propagation chains.
  final bool ignoreNullAwareAccess;

  const LazyNullCheckConfig({
    this.flagEmptyString = true,
    this.flagZero = true,
    this.flagFalse = true,
    this.flagEmptyCollection = true,
    this.ignoreMapAccess = true,
    this.ignoreNullAwareAccess = true,
  });

  factory LazyNullCheckConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const LazyNullCheckConfig();
    return LazyNullCheckConfig(
      flagEmptyString: node['flag_empty_string'] as bool? ?? true,
      flagZero: node['flag_zero'] as bool? ?? true,
      flagFalse: node['flag_false'] as bool? ?? true,
      flagEmptyCollection: node['flag_empty_collection'] as bool? ?? true,
      ignoreMapAccess: node['ignore_map_access'] as bool? ?? true,
      ignoreNullAwareAccess: node['ignore_null_aware_access'] as bool? ?? true,
    );
  }
}

/// Configuration for model code generation.
class ModelsConfig {
  /// Glob patterns for paths that contain model classes.
  final List<String> paths;

  /// Name of the toMap method (e.g. 'toMap', 'toFirestore', 'toJson').
  final String toMapName;

  /// Name of the fromMap factory (e.g. 'fromMap', 'fromFirestore', 'fromJson').
  final String fromMapName;

  /// Name of the copyWith method.
  final String copyWithName;

  /// Whether to generate == and hashCode.
  final bool equality;

  /// Whether to generate toString().
  final bool toStringMethod;

  /// Serialization style: 'map', 'json', 'firestore'.
  final String serialization;

  /// Whether model fields must be final.
  final bool immutable;

  /// Field names to exclude from copyWith.
  final List<String> excludeFromCopyWith;

  /// Field names to exclude from serialization.
  final List<String> excludeFromSerialization;

  const ModelsConfig({
    this.paths = const [],
    this.toMapName = 'toMap',
    this.fromMapName = 'fromMap',
    this.copyWithName = 'copyWith',
    this.equality = true,
    this.toStringMethod = true,
    this.serialization = 'map',
    this.immutable = true,
    this.excludeFromCopyWith = const [],
    this.excludeFromSerialization = const [],
  });

  /// Whether any model paths are configured.
  bool get isEnabled => paths.isNotEmpty;

  factory ModelsConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const ModelsConfig();

    final paths = <String>[];
    final pathsNode = node['paths'];
    if (pathsNode is YamlList) {
      for (final p in pathsNode) {
        paths.add(p.toString());
      }
    }

    final generate = node['generate'];
    String toMapName = 'toMap';
    String fromMapName = 'fromMap';
    String copyWithName = 'copyWith';
    bool equality = true;
    bool toStringMethod = true;

    if (generate is YamlMap) {
      toMapName = generate['to_map']?.toString() ?? 'toMap';
      fromMapName = generate['from_map']?.toString() ?? 'fromMap';
      copyWithName = generate['copy_with']?.toString() ?? 'copyWith';
      equality = generate['equality'] as bool? ?? true;
      toStringMethod = generate['to_string'] as bool? ?? true;
    }

    final excludeCW = <String>[];
    final ecwNode = node['exclude_from_copy_with'];
    if (ecwNode is YamlList) {
      for (final e in ecwNode) {
        excludeCW.add(e.toString());
      }
    }

    final excludeSer = <String>[];
    final esNode = node['exclude_from_serialization'];
    if (esNode is YamlList) {
      for (final e in esNode) {
        excludeSer.add(e.toString());
      }
    }

    return ModelsConfig(
      paths: paths,
      toMapName: toMapName,
      fromMapName: fromMapName,
      copyWithName: copyWithName,
      equality: equality,
      toStringMethod: toStringMethod,
      serialization: node['serialization']?.toString() ?? 'map',
      immutable: node['immutable'] as bool? ?? true,
      excludeFromCopyWith: excludeCW,
      excludeFromSerialization: excludeSer,
    );
  }
}

/// Configuration for testing enforcement.
class TestingConfig {
  /// Directory containing tests.
  final String testDir;

  /// Naming convention: 'suffix' (user_service.dart → user_service_test.dart).
  final String convention;

  /// Glob patterns for files to exclude from test requirements.
  final List<String> exclude;

  /// Glob patterns — only enforce tests for these paths.
  final List<String> requireFor;

  /// Coverage configuration.
  final CoverageConfig coverage;

  const TestingConfig({
    this.testDir = 'test',
    this.convention = 'suffix',
    this.exclude = const [],
    this.requireFor = const [],
    this.coverage = const CoverageConfig(),
  });

  factory TestingConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const TestingConfig();

    final exclude = <String>[];
    final excludeNode = node['exclude'];
    if (excludeNode is YamlList) {
      for (final e in excludeNode) {
        exclude.add(e.toString());
      }
    }

    final requireFor = <String>[];
    final reqNode = node['require_for'];
    if (reqNode is YamlList) {
      for (final r in reqNode) {
        requireFor.add(r.toString());
      }
    }

    return TestingConfig(
      testDir: node['test_dir']?.toString() ?? 'test',
      convention: node['convention']?.toString() ?? 'suffix',
      exclude: exclude,
      requireFor: requireFor,
      coverage: CoverageConfig.fromYaml(node['coverage']),
    );
  }
}

/// Configuration for test coverage thresholds.
class CoverageConfig {
  /// Path to lcov.info file.
  final String file;

  /// Minimum global coverage percent.
  final int globalMin;

  /// Minimum per-file coverage percent.
  final int perFileMin;

  /// Glob patterns to exclude from coverage.
  final List<String> exclude;

  /// Path-specific coverage overrides (glob → min percent).
  final Map<String, int> enforceFor;

  const CoverageConfig({
    this.file = 'coverage/lcov.info',
    this.globalMin = 60,
    this.perFileMin = 40,
    this.exclude = const [],
    this.enforceFor = const {},
  });

  factory CoverageConfig.fromYaml(dynamic node) {
    if (node is! YamlMap) return const CoverageConfig();

    final exclude = <String>[];
    final exNode = node['exclude'];
    if (exNode is YamlList) {
      for (final e in exNode) {
        exclude.add(e.toString());
      }
    }

    final enforceFor = <String, int>{};
    final efNode = node['enforce_for'];
    if (efNode is YamlList) {
      for (final item in efNode) {
        if (item is YamlMap) {
          for (final entry in item.entries) {
            enforceFor[entry.key.toString()] =
                int.tryParse(entry.value.toString()) ?? 60;
          }
        }
      }
    }

    return CoverageConfig(
      file: node['file']?.toString() ?? 'coverage/lcov.info',
      globalMin: int.tryParse(node['global_min']?.toString() ?? '') ?? 60,
      perFileMin: int.tryParse(node['per_file_min']?.toString() ?? '') ?? 40,
      exclude: exclude,
      enforceFor: enforceFor,
    );
  }
}
