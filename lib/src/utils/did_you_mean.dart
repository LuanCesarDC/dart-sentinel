/// Returns the closest candidate to [word] within a small edit distance,
/// or null when nothing is similar enough to suggest.
String? closestMatch(String word, Iterable<String> candidates) {
  const maxDistance = 3;
  String? best;
  var bestDistance = maxDistance + 1;
  for (final candidate in candidates) {
    final distance = _editDistance(word.toLowerCase(), candidate);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return best;
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + substitution,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
