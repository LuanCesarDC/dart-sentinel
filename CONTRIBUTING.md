# Contributing to Dart Sentinel

Thanks for your interest in contributing! Here's how you can help.

## Getting Started

1. Fork the repo and clone it locally
2. Install dependencies:
   ```bash
   dart pub get
   ```
3. Run the tool to make sure everything works:
   ```bash
   dart run dart_sentinel
   dart test
   ```

## Making Changes

1. Create a branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```
2. Make your changes
3. Add tests if applicable
4. Make sure everything passes:
   ```bash
   dart analyze --fatal-infos
   dart format .
   dart test
   dart run dart_sentinel
   ```
5. Commit with a clear message:
   ```
   feat: add new xyz rule
   fix: false positive in dead-files for part files
   docs: update README with new config option
   ```

## Opening a Pull Request

1. Push your branch and open a PR against `main`
2. Describe **what** changed and **why**
3. Reference any related issues (e.g., `Closes #12`)
4. Wait for CI to pass and for a review

## Adding a New Rule

If you want to add a new lint/architecture rule:

1. Create the rule in `lib/src/rules/`
2. Register it in `lib/src/core/runner.dart`
3. Add config support in `lib/src/config/analyzer_config.dart` if needed
4. Add tests in `test/`
5. Document it in `README.md`

For IDE plugin rules (real-time diagnostics):

1. Create the plugin rule in `lib/src/plugin/rules/`
2. Register it in the plugin entry point
3. Optionally add a quick fix in `lib/src/plugin/fixes/`

## Reporting Bugs

Open an issue with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Dart version (`dart --version`)
- Minimal `analyzer.yaml` config if relevant

## Code Style

- Follow standard Dart conventions (`dart format`)
- Keep functions focused and small
- No unnecessary abstractions — simple is better
