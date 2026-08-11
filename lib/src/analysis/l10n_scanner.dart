import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../core/project_context.dart';

/// A hardcoded string found in a Dart source file.
class HardcodedString {
  /// Absolute file path.
  final String file;

  /// 1-based line number.
  final int line;

  /// Column number.
  final int column;

  /// The literal string value.
  final String value;

  /// The widget or context where the string was found (e.g. "Text", "AppBar.title").
  final String context;

  HardcodedString({
    required this.file,
    required this.line,
    required this.column,
    required this.value,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
    'file': file,
    'line': line,
    'column': column,
    'value': value,
    'context': context,
  };
}

/// Current state of a translation key across languages.
class L10nStatus {
  /// Base language code (e.g. "en").
  final String baseLanguage;

  /// All languages found.
  final List<String> languages;

  /// Keys defined in base language.
  final int totalKeys;

  /// Per-language: how many keys are translated.
  final Map<String, int> translatedCount;

  /// Per-language: list of missing keys.
  final Map<String, List<String>> missingKeys;

  /// All translation entries: language → key → value.
  final Map<String, Map<String, String>> translations;

  L10nStatus({
    required this.baseLanguage,
    required this.languages,
    required this.totalKeys,
    required this.translatedCount,
    required this.missingKeys,
    required this.translations,
  });

  Map<String, dynamic> toJson() => {
    'baseLanguage': baseLanguage,
    'languages': languages,
    'totalKeys': totalKeys,
    'translatedCount': translatedCount,
    'missingKeys': missingKeys,
    'coverage': {
      for (final lang in languages)
        lang: totalKeys > 0
            ? '${((translatedCount[lang] ?? 0) / totalKeys * 100).toStringAsFixed(1)}%'
            : '0%',
    },
  };
}

/// Scans a Dart/Flutter project for hardcoded UI strings and l10n status.
class L10nScanner {
  final ProjectContext _context;

  L10nScanner(this._context);

  /// Scan all Dart files for hardcoded strings in UI contexts.
  List<HardcodedString> scanHardcodedStrings({List<String>? paths}) {
    final results = <HardcodedString>[];
    final filesToScan = paths ?? _context.allFiles;

    for (final file in filesToScan) {
      final unit = _context.parsedUnits[file];
      if (unit == null) continue;

      final visitor = _HardcodedStringVisitor(file, unit);
      unit.accept(visitor);
      results.addAll(visitor.strings);
    }

    // Sort by file, then line
    results.sort((a, b) {
      final f = a.file.compareTo(b.file);
      return f != 0 ? f : a.line.compareTo(b.line);
    });

    return results;
  }

  /// Read the current l10n state from ARB files.
  L10nStatus getL10nStatus() {
    final arbDir = _findArbDirectory();
    if (arbDir == null) {
      return L10nStatus(
        baseLanguage: 'en',
        languages: [],
        totalKeys: 0,
        translatedCount: {},
        missingKeys: {},
        translations: {},
      );
    }

    final arbFiles = Directory(arbDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();

    if (arbFiles.isEmpty) {
      return L10nStatus(
        baseLanguage: 'en',
        languages: [],
        totalKeys: 0,
        translatedCount: {},
        missingKeys: {},
        translations: {},
      );
    }

    // Parse all ARB files
    final allTranslations = <String, Map<String, String>>{};
    for (final file in arbFiles) {
      final lang = _langFromArbPath(file.path);
      final content =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final strings = <String, String>{};
      for (final entry in content.entries) {
        // Skip ARB metadata keys (start with @@ or @)
        if (entry.key.startsWith('@@') || entry.key.startsWith('@')) continue;
        if (entry.value is String) {
          strings[entry.key] = entry.value as String;
        }
      }
      allTranslations[lang] = strings;
    }

    // Detect base language from l10n.yaml or default to 'en'
    final baseLanguage = _detectBaseLanguage() ?? 'en';
    final baseKeys = allTranslations[baseLanguage]?.keys.toSet() ?? <String>{};
    final languages = allTranslations.keys.toList()..sort();

    final translatedCount = <String, int>{};
    final missingKeys = <String, List<String>>{};

    for (final lang in languages) {
      final langKeys = allTranslations[lang]?.keys.toSet() ?? <String>{};
      translatedCount[lang] = langKeys.intersection(baseKeys).length;
      final missing = baseKeys.difference(langKeys).toList()..sort();
      if (missing.isNotEmpty) {
        missingKeys[lang] = missing;
      }
    }

    return L10nStatus(
      baseLanguage: baseLanguage,
      languages: languages,
      totalKeys: baseKeys.length,
      translatedCount: translatedCount,
      missingKeys: missingKeys,
      translations: allTranslations,
    );
  }

  /// Generate or update ARB files with new translations.
  ///
  /// [translations] is a map of language → key → value.
  /// If [merge] is true (default), new keys are added to existing files.
  /// If false, files are overwritten entirely.
  List<String> generateArb(
    Map<String, Map<String, String>> translations, {
    bool merge = true,
  }) {
    final arbDir =
        _findArbDirectory() ?? p.join(_context.projectRoot, 'lib', 'l10n');

    // Ensure directory exists
    Directory(arbDir).createSync(recursive: true);

    final updatedFiles = <String>[];

    for (final entry in translations.entries) {
      final lang = entry.key;
      final newStrings = entry.value;
      final filePath = p.join(arbDir, 'app_$lang.arb');
      final file = File(filePath);

      Map<String, dynamic> existing = {};
      if (merge && file.existsSync()) {
        existing = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      }

      // Set locale
      existing['@@locale'] = lang;

      // Add/update translations
      for (final kv in newStrings.entries) {
        existing[kv.key] = kv.value;
      }

      // Write sorted
      final sorted = Map.fromEntries(
        existing.entries.toList()..sort((a, b) {
          // @@locale first, then @metadata after their key, then alphabetical
          if (a.key == '@@locale') return -1;
          if (b.key == '@@locale') return 1;
          return a.key.compareTo(b.key);
        }),
      );

      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(sorted) + '\n',
      );
      updatedFiles.add(filePath);
    }

    return updatedFiles;
  }

  // ── Private ──

  String? _findArbDirectory() {
    // Check l10n.yaml first
    final l10nYaml = File(p.join(_context.projectRoot, 'l10n.yaml'));
    if (l10nYaml.existsSync()) {
      final content = l10nYaml.readAsStringSync();
      final match = RegExp(r'arb-dir:\s*(.+)').firstMatch(content);
      if (match != null) {
        final dir = p.join(_context.projectRoot, match.group(1)!.trim());
        if (Directory(dir).existsSync()) return dir;
      }
    }

    // Common locations
    for (final candidate in ['lib/l10n', 'lib/src/l10n', 'l10n']) {
      final dir = p.join(_context.projectRoot, candidate);
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  String? _detectBaseLanguage() {
    final l10nYaml = File(p.join(_context.projectRoot, 'l10n.yaml'));
    if (l10nYaml.existsSync()) {
      final content = l10nYaml.readAsStringSync();
      final match = RegExp(
        r'template-arb-file:\s*app_(\w+)\.arb',
      ).firstMatch(content);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _langFromArbPath(String path) {
    final name = p.basenameWithoutExtension(path);
    // app_en.arb → en, intl_pt_BR.arb → pt_BR
    final match = RegExp(r'(?:app|intl)_(.+)').firstMatch(name);
    return match?.group(1) ?? name;
  }
}

/// Named parameters in widgets that typically contain user-visible text.
const _uiNamedParams = {
  'label',
  'hintText',
  'labelText',
  'helperText',
  'errorText',
  'counterText',
  'prefixText',
  'suffixText',
  'semanticLabel',
  'tooltip',
  'message', // Tooltip(message:)
  'title',
  'subtitle',
  'content', // for string content
};

/// Constructors where the first positional argument is UI text.
const _uiConstructors = {'Text', 'SelectableText', 'TextSpan', 'Tab'};

class _HardcodedStringVisitor extends RecursiveAstVisitor<void> {
  final String file;
  final CompilationUnit unit;
  final List<HardcodedString> strings = [];

  _HardcodedStringVisitor(this.file, this.unit);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;

    // Check first positional argument for Text('...'), TextSpan('...'), etc.
    if (_uiConstructors.contains(name)) {
      final args = node.argumentList.arguments;
      if (args.isNotEmpty) {
        final first = args.first;
        if (first is! NamedExpression) {
          _checkExpression(first, name);
        }
      }
    }

    // Check named parameters for label:, hintText:, title:, etc.
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedExpression) {
        final paramName = arg.name.label.name;
        if (_uiNamedParams.contains(paramName)) {
          _checkExpression(arg.expression, '$name.$paramName');
        }
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;

    // showDialog, showSnackBar, showBottomSheet, etc.
    if (name == 'showDialog' || name == 'showModalBottomSheet') {
      // Don't scan these — the content is usually a widget tree
    }

    // showSnackBar(SnackBar(content: Text('...'))) — handled by widget visit

    super.visitMethodInvocation(node);
  }

  void _checkExpression(Expression expr, String widgetContext) {
    if (expr is StringLiteral) {
      final value = expr.stringValue;
      if (value != null && _isTranslatableString(value)) {
        final loc = unit.lineInfo.getLocation(expr.offset);
        strings.add(
          HardcodedString(
            file: file,
            line: loc.lineNumber,
            column: loc.columnNumber,
            value: value,
            context: widgetContext,
          ),
        );
      }
    }

    // Also check string interpolation
    if (expr is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in expr.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else {
          buffer.write(r'${...}');
        }
      }
      final value = buffer.toString();
      if (_isTranslatableString(value)) {
        final loc = unit.lineInfo.getLocation(expr.offset);
        strings.add(
          HardcodedString(
            file: file,
            line: loc.lineNumber,
            column: loc.columnNumber,
            value: value,
            context: widgetContext,
          ),
        );
      }
    }
  }

  /// Filter out strings that are clearly not translatable.
  bool _isTranslatableString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length < 2) return false;

    // Skip URLs, paths, keys
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }
    if (trimmed.startsWith('/') || trimmed.startsWith('assets/')) return false;
    if (trimmed.contains(RegExp(r'^[a-z_]+\.[a-z_]+$'))) {
      return false; // keys like "user.name"
    }

    // Skip strings that are only symbols/punctuation
    if (trimmed.replaceAll(RegExp(r'[\s\W\d]'), '').isEmpty) return false;

    // Skip single words that look like identifiers
    if (RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(trimmed)) return false;

    return true;
  }
}
