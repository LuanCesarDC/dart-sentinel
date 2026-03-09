/// Utility functions for working with directed graphs.
library;

/// Find all nodes reachable from [start] using DFS.
Set<String> reachableFrom(String start, Map<String, Set<String>> graph) {
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

/// Find all nodes reachable from any of the [starts].
Set<String> reachableFromAll(
    Iterable<String> starts, Map<String, Set<String>> graph) {
  final visited = <String>{};
  for (final start in starts) {
    visited.addAll(reachableFrom(start, graph));
  }
  return visited;
}

/// Detect all cycles in a directed graph using Tarjan's algorithm.
/// Returns a list of strongly connected components with more than one node
/// (i.e., actual cycles).
List<List<String>> findCycles(Map<String, Set<String>> graph) {
  final index = <String, int>{};
  final lowlink = <String, int>{};
  final onStack = <String>{};
  final stack = <String>[];
  var currentIndex = 0;
  final sccs = <List<String>>[];

  void strongConnect(String v) {
    index[v] = currentIndex;
    lowlink[v] = currentIndex;
    currentIndex++;
    stack.add(v);
    onStack.add(v);

    final neighbors = graph[v] ?? {};
    for (final w in neighbors) {
      if (!index.containsKey(w)) {
        strongConnect(w);
        lowlink[v] = _min(lowlink[v]!, lowlink[w]!);
      } else if (onStack.contains(w)) {
        lowlink[v] = _min(lowlink[v]!, index[w]!);
      }
    }

    if (lowlink[v] == index[v]) {
      final scc = <String>[];
      String w;
      do {
        w = stack.removeLast();
        onStack.remove(w);
        scc.add(w);
      } while (w != v);

      // Only report SCCs with more than one node (actual cycles)
      // or self-loops
      if (scc.length > 1) {
        sccs.add(scc.reversed.toList());
      } else if (scc.length == 1 &&
          (graph[scc.first]?.contains(scc.first) ?? false)) {
        sccs.add(scc);
      }
    }
  }

  for (final v in graph.keys) {
    if (!index.containsKey(v)) {
      strongConnect(v);
    }
  }

  return sccs;
}

int _min(int a, int b) => a < b ? a : b;

/// Build a reverse graph (invert all edges).
Map<String, Set<String>> reverseGraph(Map<String, Set<String>> graph) {
  final reversed = <String, Set<String>>{};

  for (final entry in graph.entries) {
    reversed.putIfAbsent(entry.key, () => <String>{});
    for (final dep in entry.value) {
      reversed.putIfAbsent(dep, () => <String>{}).add(entry.key);
    }
  }

  return reversed;
}
