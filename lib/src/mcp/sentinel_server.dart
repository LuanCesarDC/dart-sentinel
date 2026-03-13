import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import '../config/analyzer_config.dart';
import '../core/issue.dart';
import '../utils/glob_matcher.dart';
import '../core/project_context.dart';
import '../core/rule.dart';
import '../core/runner.dart';
import '../analysis/impact_analyzer.dart';
import '../analysis/dependency_mapper.dart';
import '../analysis/migration_tracker.dart';
import '../rules/async_safety_rule.dart';
import '../rules/banned_imports_rule.dart';
import '../rules/banned_symbols_rule.dart';
import '../rules/build_complexity_rule.dart';
import '../rules/complexity_rule.dart';
import '../rules/dead_exports_rule.dart';
import '../rules/dead_files_rule.dart';
import '../rules/dispose_check_rule.dart';
import '../rules/feature_isolation_rule.dart';
import '../rules/import_cycle_rule.dart';
import '../rules/layer_dependency_rule.dart';
import '../rules/empty_catch_rule.dart';
import '../rules/dead_todos_rule.dart';
import '../rules/generic_naming_rule.dart';
import '../rules/redundant_comments_rule.dart';
import '../rules/verbose_logging_rule.dart';
import '../rules/single_method_class_rule.dart';
import '../rules/passthrough_function_rule.dart';

/// MCP Server for Dart Sentinel.
///
/// Exposes static analysis tools and architecture resources via the
/// Model Context Protocol, allowing AI agents to analyze Dart/Flutter
/// projects and get structured results.
base class SentinelMCPServer extends MCPServer
    with ToolsSupport, ResourcesSupport {
  SentinelMCPServer(StreamChannel<String> channel)
      : super.fromStreamChannel(
          channel,
          implementation: Implementation(
            name: 'dart-sentinel',
            version: '1.0.0',
          ),
          instructions:
              'Dart Sentinel analyzes Dart/Flutter projects for architecture '
              'violations, dead code, complexity metrics, and lint issues. '
              'Use the `analyze` tool to run analysis on a project. '
              'Use `check_import` to verify if a specific import is allowed. '
              'Read resources for current config and architecture definition.',
        ) {
    _registerTools();
    _registerResources();
  }

  // ── Tools ──────────────────────────────────────────────────────────

  void _registerTools() {
    registerTool(_analyzeTool, _handleAnalyze);
    registerTool(_analyzeFileTool, _handleAnalyzeFile);
    registerTool(_checkImportTool, _handleCheckImport);
    registerTool(_getArchitectureTool, _handleGetArchitecture);
    registerTool(_impactAnalysisTool, _handleImpactAnalysis);
    registerTool(_dependencyMapTool, _handleDependencyMap);
    registerTool(_migrationsTool, _handleMigrations);
  }

  // ── analyze ──

  static final _analyzeTool = Tool(
    name: 'analyze',
    description:
        'Run Dart Sentinel analysis on a project. Returns all issues found '
        'grouped by file, with severity, rule name, line, and message.',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
        'only': Schema.string(
          description:
              'Run only a specific category: arch, dead, metrics, lint, or all.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleAnalyze(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final category = args['only'] as String? ?? 'all';

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final issues = _runAnalysis(context, category);

    return CallToolResult(content: [TextContent(text: _formatIssues(issues))]);
  }

  // ── analyze_file ──

  static final _analyzeFileTool = Tool(
    name: 'analyze_file',
    description:
        'Analyze a single file for all rule violations. '
        'Returns issues only for the specified file.',
    inputSchema: ObjectSchema(
      properties: {
        'file': Schema.string(
          description: 'Absolute path to the Dart file to analyze.',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
      required: ['file'],
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleAnalyzeFile(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final filePath = args['file'] as String;
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final projectCtx = await ProjectContext.build(projectRoot);
    final allIssues = _runAnalysis(projectCtx, 'all');
    final relativePath = projectCtx.relativePath(filePath);
    final fileIssues =
        allIssues.where((i) => i.file == relativePath).toList();

    return CallToolResult(
      content: [TextContent(text: _formatIssues(fileIssues))],
    );
  }

  // ── check_import ──

  static final _checkImportTool = Tool(
    name: 'check_import',
    description:
        'Check if a specific import is allowed from a given file, '
        'based on the layer-dependency, banned-imports, and '
        'feature-isolation rules defined in analyzer.yaml.',
    inputSchema: ObjectSchema(
      properties: {
        'from_file': Schema.string(
          description:
              'Relative path of the file that contains the import '
              '(e.g. "lib/src/rules/complexity_rule.dart").',
        ),
        'import_uri': Schema.string(
          description:
              'The import URI to check '
              '(e.g. "package:flutter/material.dart" or "../core/issue.dart").',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
      required: ['from_file', 'import_uri'],
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleCheckImport(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final fromFile = args['from_file'] as String;
    final importUri = args['import_uri'] as String;
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final configFile = File('$projectRoot/analyzer.yaml');
    if (!configFile.existsSync()) {
      return _errorResult('No analyzer.yaml found at $projectRoot');
    }

    final config = AnalyzerConfig.load(projectRoot);
    final violations = [
      ..._checkBannedImports(config, fromFile, importUri),
      ..._checkLayerDeps(config, fromFile, importUri),
    ];

    final allowed = violations.isEmpty;
    return CallToolResult(content: [
      TextContent(
        text: _prettyJson.convert({
          'allowed': allowed,
          'from': fromFile,
          'import': importUri,
          if (!allowed) 'violations': violations,
        }),
      ),
    ]);
  }

  // ── get_architecture ──

  static final _getArchitectureTool = Tool(
    name: 'get_architecture',
    description:
        'Return the architecture definition from analyzer.yaml: '
        'layers, banned imports, and feature isolation config.',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleGetArchitecture(
      CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final configFile = File('$projectRoot/analyzer.yaml');
    if (!configFile.existsSync()) {
      return _errorResult('No analyzer.yaml found at $projectRoot');
    }

    final config = AnalyzerConfig.load(projectRoot);
    return CallToolResult(content: [
      TextContent(text: _prettyJson.convert(_architectureToJson(config))),
    ]);
  }

  // ── Resources ──────────────────────────────────────────────────────

  // ── impact_analysis ──

  static final _impactAnalysisTool = Tool(
    name: 'impact_analysis',
    description:
        'Analyze the blast radius of changing specific files. '
        'Shows all files affected transitively. '
        'If no files are provided, returns hot spots (files with most dependents).',
    inputSchema: ObjectSchema(
      properties: {
        'files': Schema.list(
          items: Schema.string(
            description: 'Relative file path to analyze.',
          ),
          description: 'List of changed file paths to analyze impact for.',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleImpactAnalysis(
      CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final filesList = args['files'] as List<dynamic>?;

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final analyzer = ImpactAnalyzer(context);

    if (filesList == null || filesList.isEmpty) {
      final spots = analyzer.hotSpots();
      return CallToolResult(content: [
        TextContent(text: _prettyJson.convert(
          spots.map((s) => {
            'file': s.file,
            'directDependents': s.directDependents,
            'transitiveDependents': s.transitiveDependents,
          }).toList(),
        )),
      ]);
    }

    final files = filesList.cast<String>();
    final report = analyzer.analyze(files);
    return CallToolResult(content: [
      TextContent(text: _prettyJson.convert({
        'changedFiles': report.changedFiles,
        'totalAffected': report.totalAffected,
        'totalFiles': report.totalFiles,
        'impactPercent': report.impactPercent.toStringAsFixed(1),
        'affectedByCategory': report.affectedByCategory,
        'affectedFiles': report.affectedFiles,
      })),
    ]);
  }

  // ── dependency_map ──

  static final _dependencyMapTool = Tool(
    name: 'dependency_map',
    description:
        'Generate a dependency map of the project. '
        'Returns a Mermaid diagram or text summary of the module structure.',
    inputSchema: ObjectSchema(
      properties: {
        'format': Schema.string(
          description:
              'Output format: "mermaid" for Mermaid diagram, '
              '"text" for text summary (default: text).',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleDependencyMap(
      CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final format = args['format'] as String? ?? 'text';

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final mapper = DependencyMapper(context);

    final mapText = format == 'mermaid' ? mapper.toMermaid() : mapper.toTextSummary();
    return CallToolResult(content: [TextContent(text: mapText)]);
  }

  // ── migrations ──

  static final _migrationsTool = Tool(
    name: 'migrations',
    description:
        'Track migration progress for banned-symbols rules. '
        'Shows remaining usages and completion percentage.',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleMigrations(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final tracker = MigrationTracker(context);
    final report = tracker.track();

    return CallToolResult(content: [
      TextContent(text: _prettyJson.convert(report.toJson())),
    ]);
  }

  void _registerResources() {
    addResource(
      Resource(
        uri: 'sentinel://config',
        name: 'Dart Sentinel Configuration',
        description: 'The current analyzer.yaml configuration file contents.',
        mimeType: 'text/yaml',
      ),
      _handleReadConfig,
    );

    addResource(
      Resource(
        uri: 'sentinel://report',
        name: 'Latest Analysis Report',
        description:
            'The most recent analysis report in JSON format '
            '(from .dart_sentinel/report.json).',
        mimeType: 'application/json',
      ),
      _handleReadReport,
    );

    addResource(
      Resource(
        uri: 'sentinel://architecture',
        name: 'Architecture Definition',
        description:
            'A structured summary of the project architecture: '
            'layers, allowed dependencies, banned imports, '
            'and feature isolation rules.',
        mimeType: 'application/json',
      ),
      _handleReadArchitecture,
    );
  }

  FutureOr<ReadResourceResult> _handleReadConfig(
      ReadResourceRequest request) {
    final configFile = File('${Directory.current.path}/analyzer.yaml');
    final content =
        configFile.existsSync() ? configFile.readAsStringSync() : '';
    return ReadResourceResult(contents: [
      TextResourceContents(uri: request.uri, text: content),
    ]);
  }

  FutureOr<ReadResourceResult> _handleReadReport(
      ReadResourceRequest request) {
    final reportFile =
        File('${Directory.current.path}/.dart_sentinel/report.json');
    final content =
        reportFile.existsSync() ? reportFile.readAsStringSync() : '{}';
    return ReadResourceResult(contents: [
      TextResourceContents(
        uri: request.uri,
        text: content,
        mimeType: 'application/json',
      ),
    ]);
  }

  FutureOr<ReadResourceResult> _handleReadArchitecture(
      ReadResourceRequest request) {
    final projectRoot = Directory.current.path;
    final configFile = File('$projectRoot/analyzer.yaml');
    if (!configFile.existsSync()) {
      return ReadResourceResult(contents: [
        TextResourceContents(uri: request.uri, text: '{}'),
      ]);
    }

    final config = AnalyzerConfig.load(projectRoot);
    return ReadResourceResult(contents: [
      TextResourceContents(
        uri: request.uri,
        text: _prettyJson.convert(_architectureToJson(config)),
        mimeType: 'application/json',
      ),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────

  List<Issue> _runAnalysis(ProjectContext context, String category) {
    final allRules = <AnalyzerRule>[
      DeadFilesRule(),
      DeadExportsRule(),
      BannedImportsRule(),
      BannedSymbolsRule(),
      LayerDependencyRule(),
      FeatureIsolationRule(),
      ImportCycleRule(),
      ComplexityRule(),
      BuildComplexityRule(),
      DisposeCheckRule(),
      AsyncSafetyRule(),
      EmptyCatchRule(),
      DeadTodosRule(),
      GenericNamingRule(),
      RedundantCommentsRule(),
      VerboseLoggingRule(),
      SingleMethodClassRule(),
      PassthroughFunctionRule(),
    ];
    final runner = RuleRunner(rules: allRules, config: context.config);
    if (category == 'all') return runner.runAll(context);
    return runner.runCategory(context, category);
  }

  String _formatIssues(List<Issue> issues) {
    if (issues.isEmpty) {
      return _prettyJson.convert({
        'status': 'clean',
        'issues': <Object>[],
        'summary': {'total': 0, 'errors': 0, 'warnings': 0, 'infos': 0},
      });
    }

    return _prettyJson.convert({
      'status': 'issues_found',
      'issues': issues
          .map((i) => {
                'rule': i.rule,
                'severity': i.severity.toString(),
                'file': i.file,
                'line': i.line,
                'message': i.message,
              })
          .toList(),
      'summary': {
        'total': issues.length,
        'errors': issues.where((i) => i.severity == Severity.error).length,
        'warnings': issues.where((i) => i.severity == Severity.warning).length,
        'infos': issues.where((i) => i.severity == Severity.info).length,
        'files': issues.map((i) => i.file).toSet().length,
      },
    });
  }

  Map<String, Object?> _architectureToJson(AnalyzerConfig config) {
    return {
      'layers': config.layerConfig?.layers.values.map((l) => {
            'name': l.name,
            'paths': l.paths,
            'can_depend_on': l.canDependOn,
          }).toList() ??
          [],
      'banned_imports': config.bannedImports.map((b) => {
        'paths': b.paths,
        'deny': b.deny,
        'message': b.message,
      }).toList(),
      'banned_symbols': config.bannedSymbols.map((s) => {
        'paths': s.paths,
        'deny': s.deny,
        'suggest': s.suggest,
        'message': s.message,
      }).toList(),
      'feature_isolation': config.featureIsolation != null
          ? {
              'enabled': config.featureIsolation!.enabled,
              'paths': config.featureIsolation!.paths,
              'allow_shared': config.featureIsolation!.allowShared,
            }
          : null,
    };
  }

  static const _prettyJson = JsonEncoder.withIndent('  ');

  List<Map<String, String>> _checkBannedImports(
    AnalyzerConfig config, String fromFile, String importUri,
  ) {
    final results = <Map<String, String>>[];
    for (final banned in config.bannedImports) {
      final matchesPath = banned.paths.any(
        (p) => GlobMatcher(p).matches(fromFile),
      );
      if (!matchesPath) continue;
      final matchesDeny = banned.deny.any(
        (d) => GlobMatcher(d).matches(importUri),
      );
      if (!matchesDeny) continue;
      results.add({
        'rule': 'banned-imports',
        'message': banned.message.isNotEmpty
            ? '${banned.message} (import: $importUri)'
            : 'Banned import: $importUri',
      });
    }
    return results;
  }

  List<Map<String, String>> _checkLayerDeps(
    AnalyzerConfig config, String fromFile, String importUri,
  ) {
    if (config.layerConfig == null) return const [];
    final layers = config.layerConfig!.layers;
    final sourceLayer = _findLayer(layers, fromFile);
    if (sourceLayer == null) return const [];

    final results = <Map<String, String>>[];
    for (final layer in layers.values) {
      if (layer.name == sourceLayer.name) continue;
      final matches = layer.paths.any(
        (p) => GlobMatcher(p).matches(importUri),
      );
      if (!matches) continue;
      if (sourceLayer.canDependOn.contains(layer.name)) continue;
      results.add({
        'rule': 'layer-dependency',
        'message': 'Layer "${sourceLayer.name}" cannot depend on '
            '"${layer.name}" (import: $importUri)',
      });
    }
    return results;
  }

  LayerDefinition? _findLayer(
    Map<String, LayerDefinition> layers, String filePath,
  ) {
    for (final layer in layers.values) {
      if (layer.paths.any((p) => GlobMatcher(p).matches(filePath))) {
        return layer;
      }
    }
    return null;
  }

  CallToolResult _errorResult(String message) => CallToolResult(
        isError: true,
        content: [TextContent(text: message)],
      );
}
