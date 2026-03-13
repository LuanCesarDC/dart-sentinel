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
  return _TarjanScc(graph).run();
}

class _TarjanScc {
  final Map<String, Set<String>> _graph;
  final _index = <String, int>{};
  final _lowlink = <String, int>{};
  final _onStack = <String>{};
  final _stack = <String>[];
  var _currentIndex = 0;
  final _sccs = <List<String>>[];

  _TarjanScc(this._graph);

  List<List<String>> run() {
    for (final v in _graph.keys) {
      if (!_index.containsKey(v)) _strongConnect(v);
    }
    return _sccs;
  }

  void _strongConnect(String v) {
    _index[v] = _currentIndex;
    _lowlink[v] = _currentIndex;
    _currentIndex++;
    _stack.add(v);
    _onStack.add(v);
    _visitNeighbors(v);
    _emitSccIfRoot(v);
  }

  void _visitNeighbors(String v) {
    for (final w in _graph[v] ?? {}) {
      if (!_index.containsKey(w)) {
        _strongConnect(w);
        _lowlink[v] = _min(_lowlink[v]!, _lowlink[w]!);
      } else if (_onStack.contains(w)) {
        _lowlink[v] = _min(_lowlink[v]!, _index[w]!);
      }
    }
  }

  void _emitSccIfRoot(String v) {
    if (_lowlink[v] != _index[v]) return;

    final scc = <String>[];
    String w;
    do {
      w = _stack.removeLast();
      _onStack.remove(w);
      scc.add(w);
    } while (w != v);

    if (scc.length > 1) {
      _sccs.add(scc.reversed.toList());
    } else if (_graph[scc.first]?.contains(scc.first) ?? false) {
      _sccs.add(scc);
    }
  }
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
