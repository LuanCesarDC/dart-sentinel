import 'package:dart_sentinel/dart_sentinel.dart';
import 'package:test/test.dart';

void main() {
  test('suggests the closest candidate', () {
    expect(
      closestMatch('dead-file', ['dead-files', 'complexity']),
      'dead-files',
    );
  });

  test('returns null when nothing is close', () {
    expect(closestMatch('zzzzzzzz', ['dead-files', 'complexity']), isNull);
  });
}
