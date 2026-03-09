# Dart Linter

Ferramenta interna de análise estática e métricas para projetos Dart/Flutter. Alternativa gratuita ao Dart Code Metrics (DCM).

## Instalação

Adicione ao `pubspec.yaml` do seu projeto:

```yaml
dev_dependencies:
  dart_linter:
    git:
      url: https://github.com/your-org/dart_linter.git
```

Ou via path local (para desenvolvimento):

```yaml
dev_dependencies:
  dart_linter:
    path: ../dart_linter
```

Depois:

```bash
dart pub get
```

## Uso

```bash
# Rodar todas as regras
dart run dart_linter

# Apenas regras de arquitetura
dart run dart_linter -o arch

# Apenas dead code
dart run dart_linter -o dead

# Apenas métricas
dart run dart_linter -o metrics

# Apenas lint rules
dart run dart_linter -o lint

# Output em JSON (para CI)
dart run dart_linter -f json

# Output em Markdown (para PR comments)
dart run dart_linter -f markdown

# Especificar projeto
dart run dart_linter -p /path/to/project
```

## Configuração

Crie um arquivo `analyzer.yaml` na raiz do seu projeto:

```yaml
# Arquivos a excluir (globs)
exclude:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "**/*.gr.dart"

# Entrypoints (auto-detectados se não especificados)
entrypoints:
  - lib/main.dart
  - lib/main_partner_mobile.dart

# Diretórios extras para scan
extra_scan_dirs:
  - integration_test
  - bin

# Severidade por regra
rules:
  dead-files: warning
  banned-imports: error
  complexity: warning
  dispose-check: error

# Regras de arquitetura
architecture:
  banned_imports:
    - paths: ["lib/features/**/viewmodel/**"]
      deny: ["package:cloud_firestore/**"]
      message: "ViewModels não devem acessar Firestore — use Services."

  layers:
    ui:
      paths: ["lib/features/**", "lib/apps/**"]
      can_depend_on: ["service", "core", "domain"]
    service:
      paths: ["lib/services/**"]
      can_depend_on: ["repository", "core", "domain"]
    repository:
      paths: ["lib/repositories/**"]
      can_depend_on: ["data", "core", "domain"]

  feature_isolation:
    enabled: true
    paths: ["lib/features/*/"]
    allow_shared:
      - "lib/core/**"
      - "lib/domain/**"
      - "lib/services/**"

# Thresholds de métricas
metrics:
  cyclomatic_complexity:
    warning: 10
    error: 20
  lines_per_file:
    warning: 300
    error: 600
  lines_per_method:
    warning: 50
    error: 100
  max_parameters:
    warning: 4
    error: 7
  max_nesting:
    warning: 4
    error: 6
  build_method_loc:
    warning: 30
    error: 60
  build_method_branches:
    warning: 3
    error: 6
```

## Regras

### Dead Code
| Regra | Descrição |
|-------|-----------|
| `dead-files` | Detecta arquivos não alcançáveis a partir de nenhum entrypoint |
| `dead-exports` | Detecta exports que ninguém importa |

### Architecture
| Regra | Descrição |
|-------|-----------|
| `banned-imports` | Impede imports proibidos em paths específicos |
| `layer-dependency` | Valida que imports respeitam as camadas definidas |
| `feature-isolation` | Impede acoplamento horizontal entre features |
| `import-cycles` | Detecta ciclos no grafo de imports |

### Metrics
| Regra | Descrição |
|-------|-----------|
| `complexity` | LOC, complexidade ciclomática, parâmetros, nesting |
| `build-complexity` | LOC e branches do método `build()` em Widgets |

### Lint
| Regra | Descrição |
|-------|-----------|
| `dispose-check` | Verifica que recursos são disposed corretamente |
| `async-safety` | Detecta `setState`/`context` após `await` sem `mounted` check |

## CI Integration

### GitHub Actions

```yaml
- name: Run Dart Linter
  run: dart run dart_linter -f json > lint_report.json

- name: Check for errors
  run: dart run dart_linter  # exit code 1 se houver errors
```

### Pre-commit hook

Adicione ao `.githooks/pre-commit`:

```bash
#!/bin/sh
dart run dart_linter -o arch
```

## Uso programático

```dart
import 'package:dart_linter/dart_linter.dart';

void main() async {
  final context = await ProjectContext.build('/path/to/project');

  final rules = [
    DeadFilesRule(),
    BannedImportsRule(),
    ComplexityRule(),
  ];

  final runner = RuleRunner(rules: rules, config: context.config);
  final issues = runner.runAll(context);

  print(ConsoleOutput.format(issues));
}
```

## Estrutura do package

```
dart_linter/
  bin/
    analyze.dart              # CLI entry point
  lib/
    dart_linter.dart          # Package exports
    src/
      config/
        analyzer_config.dart  # Configuração YAML
      core/
        issue.dart            # Issue model + Severity
        project_context.dart  # Contexto compartilhado (grafo, AST cache)
        rule.dart             # Base class para regras
        runner.dart           # Rule runner
      rules/
        async_safety_rule.dart
        banned_imports_rule.dart
        build_complexity_rule.dart
        complexity_rule.dart
        dead_exports_rule.dart
        dead_files_rule.dart
        dispose_check_rule.dart
        feature_isolation_rule.dart
        import_cycle_rule.dart
        layer_dependency_rule.dart
      output/
        output.dart           # Console, JSON, Markdown formatters
      utils/
        glob_matcher.dart     # Glob pattern matching
        graph_utils.dart      # Graph algorithms (DFS, Tarjan)
  example/
    analyzer.yaml             # Exemplo de configuração
```
