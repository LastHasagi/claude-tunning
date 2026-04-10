# Feature Card: MCP Auto-Configurator (Marketplace CLI)

## Metadata
- Feature Name: `mcp-auto-configurator-marketplace-cli`
- Status: `review`
- Owner: `Dev`
- Reviewer: `Dev`
- Created At: `2026-04-10`
- Last Updated: `2026-04-10`

## Context
Hoje o fluxo de MCP no projeto cobre merge de presets padrão, mas não oferece um comando único para listar, instalar e remover servidores de forma objetiva para Claude Code e Claude Desktop.

## Goals
- Permitir `list/install/remove` de servidores MCP por CLI.
- Automatizar a edição de `mcpServers` em `~/.claude/settings.json` e/ou `%APPDATA%/Claude/claude_desktop_config.json`.
- Manter compatibilidade com o fluxo atual de setup.
- Adicionar opção para configurar o subagent `feature-card-handoff` para Claude Code, Cursor e targets locais.

## Non-Goals
- Instalar dependências externas fora do escopo dos presets configurados.
- Validar credenciais em runtime contra APIs remotas.

## Requirements
### Functional
- [x] Expor modo `McpMarketplace` no `setup.ps1`.
- [x] Suportar ações `List`, `Install`, `Remove`.
- [x] Suportar múltiplos alvos (`ClaudeCode`, `Desktop`, `Both`).
- [x] Suportar múltiplos servidores em `-McpServer` (incluindo entrada separada por vírgula).
- [x] Expor modo `SubagentSetup` no `setup.ps1`.
- [x] Suportar `SubagentTarget` com `ClaudeCode`, `Cursor`, `Both`, `Project`, `All`.
- [x] Provisionar `feature-card-handoff` em pastas globais e locais.

### Non-Functional
- [x] Compatível com PowerShell 5.1.
- [x] Manter escrita JSON robusta com backup em caso de parse inválido.
- [x] Não hardcode de segredos reais (apenas placeholders seguros).

## DOR (Definition of Ready)
- [x] Escopo fechado para gerenciamento de `mcpServers`.
- [x] Arquivos alvo e convenções existentes identificados.
- [x] Estratégia de compatibilidade com código legado definida.
- [x] Riscos principais mapeados (JSON inválido e nomes desconhecidos).
- [x] Estratégia de teste definida.

## Implementation Notes
- `lib/mcp.ps1`:
  - Catálogo de presets (`google-search`, `github`, `filesystem`, `context7`).
  - Funções de modelo JSON reutilizáveis para leitura/escrita segura.
  - Novo orquestrador `Invoke-McpMarketplacePhase`.
- `lib/subagent.ps1`:
  - Conteúdo versionado do skill e agent `feature-card-handoff`.
  - Escrita idempotente de arquivos em UTF-8.
  - Novo orquestrador `Invoke-SubagentSetupPhase`.
- `setup.ps1`:
  - Novo modo `McpMarketplace`.
  - Novo modo `SubagentSetup`.
  - Novos parâmetros: `McpAction`, `McpServer`, `McpTarget`.
- `setup.ps1`:
  - Novo parâmetro `SubagentTarget`.
- `lib/ui.ps1`:
  - Nova opção no menu principal.
  - Novo menu de ação do marketplace MCP.
  - Novo menu de target para setup de subagente.
- `README.md`:
  - Documentação de comandos, presets MCP e setup do subagente.

## Acceptance Criteria
- [x] Dado `-Mode McpMarketplace -McpAction List`, quando executado, então lista os servidores configurados no(s) arquivo(s) alvo.
- [x] Dado `-Mode McpMarketplace -McpAction Install -McpServer github,filesystem`, quando executado, então adiciona/atualiza estes servidores em `mcpServers`.
- [x] Dado `-Mode McpMarketplace -McpAction Remove -McpServer github`, quando executado, então remove a chave `github` sem quebrar o restante do JSON.
- [x] Dado `-Mode SubagentSetup -SubagentTarget Both`, quando executado, então cria/atualiza `feature-card-handoff` em `~/.claude` e `~/.cursor`.
- [x] Dado `-Mode SubagentSetup -SubagentTarget Project`, quando executado, então cria/atualiza `.claude` e `.cursor` no diretório atual.

## DOD (Definition of Done)
- [x] Código implementado e integrado ao fluxo atual.
- [x] Documentação do modo atualizada no `README.md`.
- [x] Card de feature criado em `docs/feature/`.
- [x] Sem exposição de segredos reais.
- [x] Setup de subagente disponível por CLI/menu com targets globais e locais.
- [ ] Testes automatizados adicionados (não aplicável no projeto atual).

## Test Plan
- Unit:
  - N/A (projeto sem suíte de testes automatizada).
- Integration:
  - Executar comandos `List`, `Install`, `Remove` em `ClaudeCode` e `Desktop`.
- E2E/Manual:
  - Confirmar alteração em `mcpServers` nos arquivos alvo e reversão por `Remove`.

## Risks and Mitigations
- Risk: Nome de servidor inválido informado pelo usuário.
  - Mitigation: Avisar `Unknown server(s)` e seguir com os válidos.
- Risk: Arquivo de config com JSON inválido.
  - Mitigation: Criar backup `.bak.<timestamp>` e recriar estrutura mínima.

## Open Questions
- Quais presets adicionais devem entrar no catálogo inicial além dos quatro atuais?
- O target padrão deve continuar `ClaudeCode` ou mudar para `Both`?
- Queremos suportar templates adicionais de subagentes além de `feature-card-handoff` no mesmo fluxo?

## Review Checklist (Dev Revision)
- [x] Requisitos completos e sem ambiguidade.
- [x] DOR e DOD objetivos e verificáveis.
- [x] Casos de erro principais tratados.
- [x] Sem regressão no fluxo `Full`/`McpOnly`.
- [x] Guia de uso atualizado no README.
