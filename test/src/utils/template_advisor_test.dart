import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

void main() {
  test('picks the template with the most matching folders', () {
    expect(
      recommendTemplate(['ui', 'data', 'domain', 'routing']),
      'flutter_official',
    );
  });

  test('falls back to starter on a single weak signal', () {
    expect(recommendTemplate(['services']), fallbackTemplate);
  });
}
