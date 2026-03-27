---
applyTo: "**/*.dart"
---

# Dart Sentinel — Architecture Enforcement

This project uses Dart Sentinel for deterministic architecture enforcement.
Rules are defined in `analyzer.yaml` — check it before writing code.

## Before writing code

1. Call `get_architecture` from dart-sentinel MCP to understand layers and boundaries.
2. Call `check_import` before adding any package or cross-layer import.

## After writing code

3. Call `analyze_file` on every new or modified `.dart` file.
4. Fix ALL reported violations before returning the result.

## Rules to follow

- Respect layer boundaries (defined in `analyzer.yaml` under `architecture.layers`)
- Do not import across features — use shared/core layers only
- Use design system components (banned symbols are enforced)
- Model classes in model paths: include `toMap`, `fromMap`, `copyWith`, `==`, `hashCode`, `toString`
- Always dispose resources (StreamSubscription, TextEditingController, AnimationController)
- No empty catch blocks — handle, rethrow, or document
- No `setState`/`context` after `await` without `mounted` check
- Keep cyclomatic complexity under 10 per method
- Keep methods under 50 lines
- Keep files under 300 lines

Treat Sentinel violations as compile errors — never ignore them.
