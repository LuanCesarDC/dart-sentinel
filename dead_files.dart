import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final projectRoot = Directory.current.path;

  final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    print('pubspec.yaml não encontrado');
    exit(1);
  }

  final packageName = _extractPackageName(pubspec.readAsStringSync());

  if (packageName == null) {
    print('Não foi possível determinar o nome do package');
    exit(1);
  }

  final libDir = Directory(p.join(projectRoot, 'lib'));

  final allFiles = await _collectDartFiles(libDir);

  final entrypoints = await _findEntrypoints(libDir);

  if (entrypoints.isEmpty) {
    print('Nenhum entrypoint encontrado');
    exit(1);
  }

  print('Entrypoints detectados:');
  for (final e in entrypoints) {
    print(' - ${p.relative(e, from: projectRoot)}');
  }

  final graph = <String, Set<String>>{};

  for (final file in allFiles) {
    graph[file] = await _extractImports(
      file,
      projectRoot,
      packageName,
    );
  }

  final reachable = <String>{};

  for (final entry in entrypoints) {
    reachable.addAll(_dfs(entry, graph));
  }

  final deadFiles = allFiles.where((f) => !reachable.contains(f)).toList();

  print('\nArquivos mortos encontrados:\n');

  for (final file in deadFiles) {
    print(p.relative(file, from: projectRoot));
  }

  print('\nTotal: ${deadFiles.length}');
}

String? _extractPackageName(String pubspec) {
  final regex = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true);
  final match = regex.firstMatch(pubspec);
  return match?.group(1);
}

Future<List<String>> _collectDartFiles(Directory dir) async {
  final files = <String>[];

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(p.normalize(entity.path));
    }
  }

  return files;
}

Future<List<String>> _findEntrypoints(Directory libDir) async {
  final mains = <String>[];

  await for (final entity in libDir.list()) {
    if (entity is File) {
      final name = p.basename(entity.path);

      if (name.startsWith('main') && name.endsWith('.dart')) {
        mains.add(p.normalize(entity.path));
      }
    }
  }

  return mains;
}

Future<Set<String>> _extractImports(
  String filePath,
  String projectRoot,
  String packageName,
) async {
  final imports = <String>{};

  try {
    final result = parseFile(
      path: filePath,
      featureSet: FeatureSet.latestLanguageVersion(),
    );

    final unit = result.unit;

    for (final directive in unit.directives) {
      if (directive is UriBasedDirective) {
        final uri = directive.uri.stringValue;

        if (uri == null) continue;

        final resolved = _resolveImport(
          uri,
          filePath,
          projectRoot,
          packageName,
        );

        if (resolved != null && File(resolved).existsSync()) {
          imports.add(p.normalize(resolved));
        }
      }
    }
  } catch (_) {}

  return imports;
}

String? _resolveImport(
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

    return p.join(projectRoot, 'lib', relative);
  }

  return p.normalize(
    p.join(p.dirname(currentFile), uri),
  );
}

Set<String> _dfs(String start, Map<String, Set<String>> graph) {
  final visited = <String>{};
  final stack = <String>[start];

  while (stack.isNotEmpty) {
    final current = stack.removeLast();

    if (visited.contains(current)) continue;

    visited.add(current);

    final deps = graph[current];

    if (deps == null) continue;

    for (final dep in deps) {
      if (!visited.contains(dep)) {
        stack.add(dep);
      }
    }
  }

  return visited;
}