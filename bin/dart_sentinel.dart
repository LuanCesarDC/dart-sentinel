/// Main entry point — delegates to analyze.dart so both
/// `dart run dart_sentinel` and `dart run dart_sentinel:analyze` work.
import 'analyze.dart' as analyze;

Future<void> main(List<String> args) => analyze.main(args);
