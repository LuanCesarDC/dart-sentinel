// ⚠ BAD — lazy null coalescing hides null instead of handling it
String displayName(String? name) {
  return name ?? ""; // lazy: what should be shown when there's no name?
}

int itemCount(int? count) {
  return count ?? 0; // lazy: is 0 a valid count or a missing value?
}

bool isEnabled(bool? flag) {
  return flag ??
      false; // lazy: should default be false or should caller decide?
}

List<String> getTags(List<String>? tags) {
  return tags ?? []; // lazy: empty list hides that there were no tags
}

Map<String, int> getScores(Map<String, int>? scores) {
  return scores ?? {}; // lazy: empty map hides missing data
}

// ✅ GOOD — handle the null case explicitly
String displayNameFixed(String? name) {
  if (name == null) return 'Anonymous';
  return name;
}

int itemCountFixed(int? count) {
  if (count == null) throw ArgumentError('count is required');
  return count;
}

List<String> getTagsFixed(List<String>? tags) {
  if (tags == null) return const ['untagged'];
  return tags;
}
