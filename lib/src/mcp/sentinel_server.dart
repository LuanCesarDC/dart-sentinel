import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
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
import '../analysis/l10n_scanner.dart';
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
import '../rules/lazy_null_check_rule.dart';
import '../rules/model_missing_methods_rule.dart';
import '../rules/unused_code_rule.dart';
import '../rules/untested_files_rule.dart';
import '../rules/test_coverage_rule.dart';
import '../rules/test_quality_rule.dart';
import '../rules/class_metrics_rule.dart';
import '../rules/pubspec_rule.dart';
import '../rules/avoid_global_state_rule.dart';
import '../rules/no_magic_number_rule.dart';
import '../rules/no_equal_then_else_rule.dart';
import '../rules/avoid_commented_out_code_rule.dart';
import '../rules/no_equal_arguments_rule.dart';
import '../rules/avoid_self_compare_rule.dart';
import '../rules/avoid_returning_widgets_rule.dart';
import '../rules/flutter_anti_patterns_rule.dart';
import '../rules/misused_dependencies_rule.dart';
import '../analysis/model_generator.dart';

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
        implementation: Implementation(name: 'dart-sentinel', version: '1.0.0'),
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
    registerTool(_scanHardcodedStringsTool, _handleScanHardcodedStrings);
    registerTool(_l10nStatusTool, _handleL10nStatus);
    registerTool(_generateL10nTool, _handleGenerateL10n);
    registerTool(_generateModelScaffoldTool, _handleGenerateModelScaffold);
    registerTool(_generateModelUpdateTool, _handleGenerateModelUpdate);
    registerTool(_generateTestScaffoldTool, _handleGenerateTestScaffold);
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
    final fileIssues = allIssues.where((i) => i.file == relativePath).toList();

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
    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'allowed': allowed,
            'from': fromFile,
            'import': importUri,
            if (!allowed) 'violations': violations,
          }),
        ),
      ],
    );
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

  Future<CallToolResult> _handleGetArchitecture(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final configFile = File('$projectRoot/analyzer.yaml');
    if (!configFile.existsSync()) {
      return _errorResult('No analyzer.yaml found at $projectRoot');
    }

    final config = AnalyzerConfig.load(projectRoot);
    return CallToolResult(
      content: [
        TextContent(text: _prettyJson.convert(_architectureToJson(config))),
      ],
    );
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
          items: Schema.string(description: 'Relative file path to analyze.'),
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

  Future<CallToolResult> _handleImpactAnalysis(CallToolRequest request) async {
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
      return CallToolResult(
        content: [
          TextContent(
            text: _prettyJson.convert(
              spots
                  .map(
                    (s) => {
                      'file': s.file,
                      'directDependents': s.directDependents,
                      'transitiveDependents': s.transitiveDependents,
                    },
                  )
                  .toList(),
            ),
          ),
        ],
      );
    }

    final files = filesList.cast<String>();
    final report = analyzer.analyze(files);
    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'changedFiles': report.changedFiles,
            'totalAffected': report.totalAffected,
            'totalFiles': report.totalFiles,
            'impactPercent': report.impactPercent.toStringAsFixed(1),
            'affectedByCategory': report.affectedByCategory,
            'affectedFiles': report.affectedFiles,
          }),
        ),
      ],
    );
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

  Future<CallToolResult> _handleDependencyMap(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final format = args['format'] as String? ?? 'text';

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final mapper = DependencyMapper(context);

    final mapText = format == 'mermaid'
        ? mapper.toMermaid()
        : mapper.toTextSummary();
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

    return CallToolResult(
      content: [TextContent(text: _prettyJson.convert(report.toJson()))],
    );
  }

  // ── scan_hardcoded_strings ──

  static final _scanHardcodedStringsTool = Tool(
    name: 'scan_hardcoded_strings',
    description:
        'Scan all Dart files for hardcoded UI strings that should be localized. '
        'Uses AST analysis to find string literals inside Text(), AppBar(title:), '
        'InputDecoration(hintText:), Tooltip(message:), and other UI widgets. '
        'Returns each string with file, line, value, and widget context.',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
        'files': Schema.list(
          description:
              'Optional list of specific file paths to scan. '
              'If omitted, scans all Dart files in the project.',
          items: Schema.string(),
        ),
      },
    ),
    annotations: ToolAnnotations(readOnlyHint: true, idempotentHint: true),
  );

  Future<CallToolResult> _handleScanHardcodedStrings(
    CallToolRequest request,
  ) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final filesList = args['files'] as List<dynamic>?;

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final scanner = L10nScanner(context);

    final paths = filesList?.cast<String>();
    final strings = scanner.scanHardcodedStrings(paths: paths);

    final relativized = strings.map((s) {
      final rel = s.file.startsWith(projectRoot)
          ? s.file.substring(projectRoot.length + 1)
          : s.file;
      return {
        'file': rel,
        'line': s.line,
        'column': s.column,
        'value': s.value,
        'context': s.context,
      };
    }).toList();

    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'total': strings.length,
            'strings': relativized,
          }),
        ),
      ],
    );
  }

  // ── l10n_status ──

  static final _l10nStatusTool = Tool(
    name: 'l10n_status',
    description:
        'Get the current localization status of the project. '
        'Reads all .arb files, compares languages, and reports '
        'total keys, per-language coverage, and missing translations.',
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

  Future<CallToolResult> _handleL10nStatus(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    final context = await ProjectContext.build(projectRoot);
    final scanner = L10nScanner(context);
    final status = scanner.getL10nStatus();

    return CallToolResult(
      content: [TextContent(text: _prettyJson.convert(status.toJson()))],
    );
  }

  // ── generate_l10n ──

  static final _generateL10nTool = Tool(
    name: 'generate_l10n',
    description:
        'Generate or update ARB localization files with translations. '
        'Provide a JSON object mapping language codes to key-value pairs. '
        'By default merges with existing ARB files. '
        'Example: {"en": {"hello": "Hello"}, "pt": {"hello": "Olá"}}',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
        'translations': ObjectSchema(
          description:
              'Map of language code → (key → translated string). '
              'Example: {"en": {"save": "Save"}, "pt": {"save": "Salvar"}}',
        ),
        'merge': Schema.bool(
          description:
              'If true (default), new keys are added to existing ARB files. '
              'If false, files are overwritten entirely.',
        ),
      },
      required: ['translations'],
    ),
  );

  Future<CallToolResult> _handleGenerateL10n(CallToolRequest request) async {
    final args = request.arguments ?? {};
    final projectRoot = args['path'] as String? ?? Directory.current.path;
    final rawTranslations = args['translations'] as Map<String, dynamic>?;
    final merge = args['merge'] as bool? ?? true;

    if (rawTranslations == null || rawTranslations.isEmpty) {
      return _errorResult(
        'Missing "translations" argument. '
        'Provide a map like: {"en": {"hello": "Hello"}, "pt": {"hello": "Olá"}}',
      );
    }

    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return _errorResult('No pubspec.yaml found at $projectRoot');
    }

    // Parse translations
    final translations = <String, Map<String, String>>{};
    for (final entry in rawTranslations.entries) {
      final lang = entry.key;
      final values = entry.value;
      if (values is Map<String, dynamic>) {
        translations[lang] = values.map((k, v) => MapEntry(k, v.toString()));
      }
    }

    final context = await ProjectContext.build(projectRoot);
    final scanner = L10nScanner(context);
    final updatedFiles = scanner.generateArb(translations, merge: merge);

    final relativeFiles = updatedFiles
        .map(
          (f) => f.startsWith(projectRoot)
              ? f.substring(projectRoot.length + 1)
              : f,
        )
        .toList();

    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'status': 'success',
            'files_updated': relativeFiles,
            'languages': translations.keys.toList(),
            'keys_per_language': {
              for (final e in translations.entries) e.key: e.value.length,
            },
          }),
        ),
      ],
    );
  }

  // ── generate_model_scaffold ──

  static final _generateModelScaffoldTool = Tool(
    name: 'generate_model_scaffold',
    description:
        'Generate a complete model class with boilerplate methods '
        '(copyWith, toMap, fromMap, ==, hashCode, toString). '
        'Respects the project\'s configured method names and serialization style '
        'from analyzer.yaml. Returns code that can be inserted directly.',
    inputSchema: ObjectSchema(
      properties: {
        'class_name': Schema.string(
          description: 'The name of the model class to generate.',
        ),
        'fields': Schema.list(
          items: ObjectSchema(
            properties: {
              'name': Schema.string(description: 'Field name.'),
              'type': Schema.string(
                description: 'Dart type (e.g. String, int, List<String>).',
              ),
            },
            required: ['name', 'type'],
          ),
          description: 'List of fields with name and type.',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
      required: ['class_name', 'fields'],
    ),
  );

  Future<CallToolResult> _handleGenerateModelScaffold(
    CallToolRequest request,
  ) async {
    final args = request.arguments ?? {};
    final className = args['class_name'] as String?;
    final fieldsList = args['fields'] as List<dynamic>?;
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    if (className == null || className.isEmpty) {
      return _errorResult('Missing "class_name" argument.');
    }
    if (fieldsList == null || fieldsList.isEmpty) {
      return _errorResult('Missing "fields" argument.');
    }

    final config = AnalyzerConfig.load(projectRoot);
    final generator = ModelGenerator(config.modelsConfig);

    final fields = fieldsList.map((f) {
      final map = f as Map<String, dynamic>;
      final type = map['type'] as String? ?? 'dynamic';
      return FieldInfo(
        name: map['name'] as String? ?? '',
        type: type,
        isNullable: type.endsWith('?'),
      );
    }).toList();

    final code = generator.generateFullClass(
      className: className,
      fields: fields,
    );

    final suggestedPath = _suggestModelPath(config, className);

    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'code': code,
            'methods_generated': _listGeneratedMethods(config.modelsConfig),
            'path_suggestion': suggestedPath,
          }),
        ),
      ],
    );
  }

  // ── generate_model_update ──

  static final _generateModelUpdateTool = Tool(
    name: 'generate_model_update',
    description:
        'Regenerate the sentinel-generated methods of an existing model class. '
        'Reads the class, extracts fields, and regenerates the code block '
        'between sentinel markers. Returns the full updated file content.',
    inputSchema: ObjectSchema(
      properties: {
        'file': Schema.string(
          description: 'Absolute path to the model file to update.',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
      required: ['file'],
    ),
  );

  Future<CallToolResult> _handleGenerateModelUpdate(
    CallToolRequest request,
  ) async {
    final args = request.arguments ?? {};
    final filePath = args['file'] as String?;
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    if (filePath == null || filePath.isEmpty) {
      return _errorResult('Missing "file" argument.');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      return _errorResult('File not found: $filePath');
    }

    final config = AnalyzerConfig.load(projectRoot);
    final generator = ModelGenerator(config.modelsConfig);

    final context = await ProjectContext.build(projectRoot);
    final unit = context.parsedUnits[filePath];
    if (unit == null) {
      return _errorResult('Could not parse file: $filePath');
    }

    // Find the first class declaration
    ClassDeclaration? classDecl;
    for (final decl in unit.declarations) {
      if (decl is ClassDeclaration) {
        classDecl = decl;
        break;
      }
    }

    if (classDecl == null) {
      return _errorResult('No class found in file: $filePath');
    }

    final fields = ModelGenerator.extractFields(classDecl);
    final className = classDecl.namePart.typeName.lexeme;

    final fileContent = file.readAsStringSync();
    final updated = generator.updateGeneratedSection(
      fileContent: fileContent,
      className: className,
      fields: fields,
    );

    if (updated != null) {
      return CallToolResult(
        content: [
          TextContent(
            text: _prettyJson.convert({
              'updated_code': updated,
              'class_name': className,
              'changed_methods': _listGeneratedMethods(config.modelsConfig),
            }),
          ),
        ],
      );
    }

    // No existing markers — generate and append before closing brace
    final generated = generator.generate(className: className, fields: fields);
    final classBody = classDecl.body;
    if (classBody is! BlockClassBody) {
      return _errorResult('Class body is not a block body: $filePath');
    }
    final classEnd = classBody.rightBracket.offset;
    final newContent =
        fileContent.substring(0, classEnd) +
        '\n$generated' +
        fileContent.substring(classEnd);

    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'updated_code': newContent,
            'class_name': className,
            'changed_methods': _listGeneratedMethods(config.modelsConfig),
          }),
        ),
      ],
    );
  }

  String _suggestModelPath(AnalyzerConfig config, String className) {
    final snake = className
        .replaceAllMapped(
          RegExp(r'[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .substring(1); // remove leading underscore
    final paths = config.modelsConfig.paths;
    if (paths.isNotEmpty) {
      final base = paths.first.replaceAll('/**', '').replaceAll('**', '');
      return '$base/$snake.dart';
    }
    return 'lib/src/models/$snake.dart';
  }

  List<String> _listGeneratedMethods(ModelsConfig config) {
    final methods = <String>[];
    if (config.copyWithName.isNotEmpty) methods.add(config.copyWithName);
    if (config.toMapName.isNotEmpty) methods.add(config.toMapName);
    if (config.fromMapName.isNotEmpty) methods.add(config.fromMapName);
    if (config.equality) methods.addAll(['==', 'hashCode']);
    if (config.toStringMethod) methods.add('toString');
    return methods;
  }

  // ── generate_test_scaffold ──

  static final _generateTestScaffoldTool = Tool(
    name: 'generate_test_scaffold',
    description:
        'Generate a test file scaffold for a Dart source file. '
        'Extracts public classes and methods from the AST and generates '
        'a test skeleton with group/test stubs for each.',
    inputSchema: ObjectSchema(
      properties: {
        'file': Schema.string(
          description:
              'Absolute path to the Dart source file to generate tests for.',
        ),
        'path': Schema.string(
          description:
              'Absolute path to the project root. '
              'Defaults to the current working directory.',
        ),
      },
      required: ['file'],
    ),
  );

  Future<CallToolResult> _handleGenerateTestScaffold(
    CallToolRequest request,
  ) async {
    final args = request.arguments ?? {};
    final filePath = args['file'] as String?;
    final projectRoot = args['path'] as String? ?? Directory.current.path;

    if (filePath == null || filePath.isEmpty) {
      return _errorResult('Missing "file" argument.');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      return _errorResult('File not found: $filePath');
    }

    final context = await ProjectContext.build(projectRoot);
    final unit = context.parsedUnits[filePath];
    if (unit == null) {
      return _errorResult('Could not parse file: $filePath');
    }

    final relativePath = context.relativePath(filePath);
    final buf = StringBuffer();
    buf.writeln("import 'package:test/test.dart';");

    // Derive import for the source file
    buf.writeln(
      "import 'package:${_derivePackageImport(projectRoot, relativePath)}';",
    );
    buf.writeln();
    buf.writeln('void main() {');

    for (final decl in unit.declarations) {
      if (decl is ClassDeclaration) {
        final className = decl.namePart.typeName.lexeme;
        if (className.startsWith('_')) continue;

        buf.writeln("  group('$className', () {");

        // Extract public methods
        if (decl.body is BlockClassBody) {
          final body = decl.body as BlockClassBody;
          for (final member in body.members) {
            if (member is MethodDeclaration) {
              final methodName = member.name.lexeme;
              if (methodName.startsWith('_')) continue;
              buf.writeln("    test('$methodName', () {");
              buf.writeln('      // TODO: implement test');
              buf.writeln('    });');
              buf.writeln();
            }
          }
        }

        buf.writeln('  });');
        buf.writeln();
      } else if (decl is FunctionDeclaration) {
        final funcName = decl.name.lexeme;
        if (funcName.startsWith('_')) continue;
        buf.writeln("  test('$funcName', () {");
        buf.writeln('    // TODO: implement test');
        buf.writeln('  });');
        buf.writeln();
      }
    }

    buf.writeln('}');

    // Suggest test file path
    final testPath = relativePath
        .replaceFirst('lib/', 'test/')
        .replaceFirst('.dart', '_test.dart');

    return CallToolResult(
      content: [
        TextContent(
          text: _prettyJson.convert({
            'test_code': buf.toString(),
            'suggested_path': testPath,
            'source_file': relativePath,
          }),
        ),
      ],
    );
  }

  String _derivePackageImport(String projectRoot, String relativePath) {
    final pubspecFile = File('$projectRoot/pubspec.yaml');
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      final match = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(content);
      if (match != null) {
        final packageName = match.group(1)!;
        final libPath = relativePath.replaceFirst('lib/', '');
        return '$packageName/$libPath';
      }
    }
    return relativePath;
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

  FutureOr<ReadResourceResult> _handleReadConfig(ReadResourceRequest request) {
    final configFile = File('${Directory.current.path}/analyzer.yaml');
    final content = configFile.existsSync()
        ? configFile.readAsStringSync()
        : '';
    return ReadResourceResult(
      contents: [TextResourceContents(uri: request.uri, text: content)],
    );
  }

  FutureOr<ReadResourceResult> _handleReadReport(ReadResourceRequest request) {
    final reportFile = File(
      '${Directory.current.path}/.dart_sentinel/report.json',
    );
    final content = reportFile.existsSync()
        ? reportFile.readAsStringSync()
        : '{}';
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: request.uri,
          text: content,
          mimeType: 'application/json',
        ),
      ],
    );
  }

  FutureOr<ReadResourceResult> _handleReadArchitecture(
    ReadResourceRequest request,
  ) {
    final projectRoot = Directory.current.path;
    final configFile = File('$projectRoot/analyzer.yaml');
    if (!configFile.existsSync()) {
      return ReadResourceResult(
        contents: [TextResourceContents(uri: request.uri, text: '{}')],
      );
    }

    final config = AnalyzerConfig.load(projectRoot);
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: request.uri,
          text: _prettyJson.convert(_architectureToJson(config)),
          mimeType: 'application/json',
        ),
      ],
    );
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
      LazyNullCheckRule(),
      ModelMissingMethodsRule(),
      UnusedCodeRule(),
      UntestedFilesRule(),
      TestCoverageRule(),
      TestQualityRule(),
      ClassMetricsRule(),
      PubspecRule(),
      AvoidGlobalStateRule(),
      NoMagicNumberRule(),
      NoEqualThenElseRule(),
      AvoidCommentedOutCodeRule(),
      NoEqualArgumentsRule(),
      AvoidSelfCompareRule(),
      AvoidReturningWidgetsRule(),
      FlutterAntiPatternsRule(),
      MisusedDependenciesRule(),
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
          .map(
            (i) => {
              'rule': i.rule,
              'severity': i.severity.toString(),
              'file': i.file,
              'line': i.line,
              'message': i.message,
            },
          )
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
      'layers':
          config.layerConfig?.layers.values
              .map(
                (l) => {
                  'name': l.name,
                  'paths': l.paths,
                  'can_depend_on': l.canDependOn,
                },
              )
              .toList() ??
          [],
      'banned_imports': config.bannedImports
          .map((b) => {'paths': b.paths, 'deny': b.deny, 'message': b.message})
          .toList(),
      'banned_symbols': config.bannedSymbols
          .map(
            (s) => {
              'paths': s.paths,
              'deny': s.deny,
              'suggest': s.suggest,
              'message': s.message,
            },
          )
          .toList(),
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
    AnalyzerConfig config,
    String fromFile,
    String importUri,
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
    AnalyzerConfig config,
    String fromFile,
    String importUri,
  ) {
    if (config.layerConfig == null) return const [];
    final layers = config.layerConfig!.layers;
    final sourceLayer = _findLayer(layers, fromFile);
    if (sourceLayer == null) return const [];

    final results = <Map<String, String>>[];
    for (final layer in layers.values) {
      if (layer.name == sourceLayer.name) continue;
      final matches = layer.paths.any((p) => GlobMatcher(p).matches(importUri));
      if (!matches) continue;
      if (sourceLayer.canDependOn.contains(layer.name)) continue;
      results.add({
        'rule': 'layer-dependency',
        'message':
            'Layer "${sourceLayer.name}" cannot depend on '
            '"${layer.name}" (import: $importUri)',
      });
    }
    return results;
  }

  LayerDefinition? _findLayer(
    Map<String, LayerDefinition> layers,
    String filePath,
  ) {
    for (final layer in layers.values) {
      if (layer.paths.any((p) => GlobMatcher(p).matches(filePath))) {
        return layer;
      }
    }
    return null;
  }

  CallToolResult _errorResult(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}
