import 'package:path/path.dart' as p;

/// [path] relative to [from], always with `/` separators.
///
/// Rules and `exclude`/layer globs are written with `/`. On Windows the native
/// separator is `\`, so it is converted there; on POSIX a backslash is a
/// legitimate file-name character and is left alone.
String posixRelative(String path, {required String from, p.Context? context}) {
  final ctx = context ?? p.context;
  final relative = ctx.relative(path, from: from);
  return ctx.style == p.Style.windows
      ? relative.replaceAll(r'\', '/')
      : relative;
}
