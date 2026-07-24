# Dart Sentinel — Loop de Enforcement via Hooks (Claude Code)

## Contexto e motivação

Dart Sentinel já implementa um motor de regras maduro (19 regras, MCP server com
10 tools, plugin de analysis server, extensão VS Code). Apesar disso, um teste real
feito pelo autor — codar uma aplicação simples com um modelo mais fraco, com e sem
o Sentinel — não produziu nenhuma prova perceptível de benefício, e o próprio autor
parou de usar a ferramenta por fricção.

Causas identificadas na conversa que originou este spec:
- A integração via **MCP depende do modelo decidir chamar as tools**. Em testes
  com GitHub Copilot como "skill", o modelo simplesmente não usava.
- O relatório em `.dart_sentinel/report.json` fica desatualizado e exige rodar o
  CLI manualmente — não há loop automático fechando sozinho.
- Não é plug-and-play: requer configuração manual de `analyzer.yaml` e do client
  MCP antes de qualquer valor aparecer.
- Não havia nenhum indicador visível de que a ferramenta estava, de fato, mudando
  o comportamento do modelo.

O objetivo deste spec é resolver especificamente a fricção de uso e a falta de
prova de valor, usando os hooks do Claude Code para tornar o enforcement
**determinístico** (não depende do modelo lembrar ou decidir usar a ferramenta),
e produzir um indicador de "ratchet" (violações introduzidas vs. corrigidas) como
evidência visível a cada sessão.

## Escopo

Este é o primeiro de dois subprojetos identificados no brainstorm:

1. **Loop de enforcement via hooks** (este spec) — ataca a causa raiz do abandono:
   fricção de integração e falta de prova de valor. Prioridade alta porque pode
   ser validado rapidamente usando o `analyzer.yaml` que o próprio projeto já tem.
2. **Skill de setup interativo** (fora de escopo aqui, spec futuro) — entrevista
   guiada sobre arquitetura/gerenciamento de estado/estrutura de pastas que gera
   o `analyzer.yaml` automaticamente. Resolve a fricção de configuração inicial,
   mas depende menos de mudança técnica e mais de design de conversa — fica para
   uma segunda rodada, depois que o loop de enforcement provar valor.

MCP deixa de ser o mecanismo principal de enforcement. Continua existindo para
tools de consulta ativa que a IA invoca sob demanda (`impact_analysis`,
`generate_model_scaffold`, `dependency_map`) — não para checagem de conformidade,
que passa a ser 100% via hook.

## Arquitetura e componentes

```
.claude/settings.json (hooks)
        │
        ├── PostToolUse (Edit|Write, *.dart) ──> dart_sentinel analyze-file <path> --fast
        │                                          (regras de arquivo único, mesmo motor do plugin)
        │                                          → stdout JSON → hook bloqueia/injeta se error
        │
        └── Stop ─────────────────────────────> dart_sentinel analyze --check-baseline
                                                   (scan completo: arquitetura + métricas cross-file)
                                                   → compara com .dart_sentinel/baseline.json
                                                   → bloqueia só se piorou; senão libera + resumo de ratchet
```

Dois componentes novos, ambos wrappers finos sobre o motor de regras existente
(`RuleRunner`, `Ratchet`, `ProjectContext`) — não há novo motor de análise:

- **`bin/hook_edit.dart`** — chama a mesma lógica de `analyze_file` usada pelo
  plugin de IDE, mas formata a saída no protocolo de hook do Claude Code
  (`decision`/`reason` em JSON) em vez de diagnostics do analysis server.
- **`bin/hook_stop.dart`** — chama `RuleRunner` completo (todas as categorias) +
  `Ratchet` (já existe em `lib/src/analysis/ratchet.dart`), formata como
  bloqueio/liberação de Stop hook, incluindo o resumo de "prova de valor".

Novo subcomando de instalação:

- **`dart_sentinel setup-hooks`** — escreve/mescla as entradas de hook em
  `.claude/settings.json` automaticamente (nunca overwrite; faz merge se já
  existirem hooks de outra origem). Se não houver `analyzer.yaml`, avisa e para
  sem bloquear quem já tem um configurado manualmente.

## Fluxo de dados

### PostToolUse (a cada `Edit`/`Write` em `.dart`)

1. Hook recebe o path do arquivo editado.
2. Se o arquivo está fora do escopo scaneado (fora de `lib/`/`bin/`, ou casa com
   `exclude` do `analyzer.yaml`), sai sem rodar nada.
3. Roda só as regras de arquivo único — as mesmas ~12 do plugin (`dispose-check`,
   `async-safety`, `empty-catch`, `generic-naming`, `sentinel_complexity`,
   `build_complexity`, etc.). Rápido: parseia só o arquivo tocado, sem
   reconstruir o grafo de imports do projeto.
4. Se houver violação de severidade `error`: `decision: block`, com a lista
   formatada compacta (`arquivo:linha — regra — mensagem`). O Claude Code trata
   isso como um erro de compilação e precisa corrigir antes de prosseguir.
5. Se só houver `warning`/`info`: não bloqueia (evita fricção excessiva por
   edição), mas fica registrado para aparecer no resumo do Stop hook.

### Stop (quando o Claude termina de responder)

1. Roda o scan completo (todas as categorias), reconstruindo o grafo de imports
   — necessário porque `layer-dependency`, `import-cycles` e `dead-files`
   dependem do projeto inteiro, não de um arquivo isolado.
2. Compara a contagem de violações por regra contra
   `.dart_sentinel/baseline.json`.
3. Se piorou: `decision: block`, mostrando **apenas o diff** (violações novas
   desde o baseline) — não o relatório inteiro. Evita o problema de saída
   ruidosa relatado no teste original.
4. Se não piorou: libera e imprime um resumo curto, por exemplo:
   ```
   ✓ Sentinel: 3 violações pegas e corrigidas nesta sessão (dispose-check ×2, layer-dependency ×1)
   ✓ Baseline: 0 regressões
   ```
   Esse resumo é o indicador de "prova de valor" visível a cada sessão, sem
   precisar de benchmark separado.
5. O baseline **só é atualizado com aceite explícito do usuário** (comando
   separado, não automático a cada Stop) — do contrário a IA poderia "lavar"
   uma regressão simplesmente encerrando a resposta num estado pior.

### Edge cases

- CLI não instalado ou hook falha ao rodar → falha aberta (não bloqueia o
  fluxo do usuário), com um aviso único por sessão de que o Sentinel está
  inativo.
- Performance do scan completo em projetos grandes no Stop hook → reutilizar o
  cache de AST do `ProjectContext`, persistido entre invocações do hook dentro
  da mesma sessão (hoje o cache só vive dentro de um processo).
- Primeiro `Stop` sem baseline existente → cria baseline automaticamente sem
  bloquear (evita travar todo projeto legado no primeiro uso).

## Testes

- **Unit**: `hook_edit.dart` e `hook_stop.dart` testados com fixtures de
  projeto (mesmo padrão dos testes de regra existentes), verificando o formato
  JSON de saída do protocolo de hook e a lógica de block/allow.
- **Integração**: usar o `example/` já existente no repo, configurar os hooks,
  simular uma sequência edit → violação → correção, e verificar que o
  baseline e o resumo de ratchet batem com o esperado.
- **Dogfood**: ativar os hooks neste próprio repositório (Sentinel analisando a
  si mesmo, como o `REBUILD_PLAN.md` já propunha) como validação viva antes de
  publicar a feature.

## Fora de escopo (explicitamente adiado)

- Skill de setup interativo para gerar `analyzer.yaml` (subprojeto 2).
- Suporte a hooks em outros agentes além do Claude Code (Cursor, Copilot etc.)
  — pode vir depois, mas não é o alvo desta rodada.
- Benchmark formal reproduzível (POC A/B/C/D de `POC_EXPERIMENTS.md`) como
  prova externa — o resumo de ratchet por sessão é a prova adotada nesta
  rodada; um benchmark mais rigoroso fica como possível trabalho futuro.
