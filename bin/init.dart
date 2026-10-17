// `dart_sentinel init` — detects the lib/ structure, recommends a template,
// writes it as analyzer.yaml (templates ship inside the package) and sets up
// the Claude Code hooks.
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:path/path.dart' as p;

import 'setup_hooks.dart' as setup_hooks;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to the project root.')
    ..addOption('template', abbr: 't', help: 'Template name (default: detect).')
    ..addFlag('force', negatable: false, help: 'Overwrite analyzer.yaml.')
    ..addFlag('no-hooks', negatable: false, help: 'Skip setup-hooks.');
  final results = parser.parse(args);
  final projectRoot = results['project'] as String? ?? Directory.current.path;

  if (!File(p.join(projectRoot, 'pubspec.yaml')).existsSync()) {
    stderr.writeln(
      'pubspec.yaml not found at $projectRoot — run from the '
      'project root or pass --project.',
    );
    exit(1);
  }

  final target = File(p.join(projectRoot, 'analyzer.yaml'));
  if (target.existsSync() && !(results['force'] as bool)) {
    stderr.writeln(
      'analyzer.yaml already exists — pass --force to replace it.',
    );
    exit(1);
  }

  final folders = _libFolders(projectRoot);
  final requested = results['template'] as String?;
  final template = requested ?? recommendTemplate(folders);
  print('lib/ folders: ${folders.isEmpty ? '(none)' : folders.join(', ')}');
  print(
    requested == null
        ? 'Recommended template: $template'
        : 'Using template: $template',
  );

  final source = await _templateFile(template);
  if (source == null) {
    stderr.writeln('Template "$template" not found in the package.');
    exit(1);
  }
  target.writeAsStringSync(source.readAsStringSync());
  print('Wrote ${target.path}');

  await _reportFit(projectRoot);

  if (results['no-hooks'] as bool) {
    print('Next: run `dart_sentinel setup-hooks` to enforce it automatically.');
    return;
  }
  await setup_hooks.main(['--project', projectRoot]);
}

/// Top-level folders under lib/ (descending into lib/src when it is the
/// only wrapper).
List<String> _libFolders(String projectRoot) {
  var libDir = Directory(p.join(projectRoot, 'lib'));
  final src = Directory(p.join(libDir.path, 'src'));
  final hasWrapper = src.existsSync();
  if (hasWrapper) libDir = src;
  if (!libDir.existsSync()) return const [];
  return libDir
      .listSync()
      .whereType<Directory>()
      .map((d) => p.basename(d.path))
      .toList()
    ..sort();
}

Future<File?> _templateFile(String name) async {
  final entry = await Isolate.resolvePackageUri(
    Uri.parse('package:dart_sentinel/dart_sentinel.dart'),
  );
  if (entry == null) return null;
  final packageRoot = p.dirname(p.dirname(entry.toFilePath()));
  final file = File(p.join(packageRoot, 'example', 'templates', '$name.yaml'));
  return file.existsSync() ? file : null;
}

Future<void> _reportFit(String projectRoot) async {
  final context = await ProjectContext.build(projectRoot);
  final warnings = layerCoverageWarnings(
    context.config,
    context.allFiles.map(context.relativePath),
  );
  if (warnings.isEmpty) return;
  print('The template does not fully match this project:');
  for (final warning in warnings) {
    print('  ⚠ $warning');
  }
  print('Edit the layer paths in analyzer.yaml to fit your folders.');
}
