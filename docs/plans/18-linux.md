# 18 — Linux: núcleo, app GTK4 e release

Data: 2026-11-01 · Status: fases 0–4 feitas no fork (2026-11-02); fase 5 é a próxima

> A fase 2 entregou o terminal com Cairo/Pango por célula (o fallback previsto no ADR
> 0021). A fase 3 entregou abas, uma divisão por aba, paleta, temas, configurações,
> barra de status, spaces em memória e a casca da barra lateral. A fase 4 entregou
> explorer, busca, editor, Markdown e git. O que ficou de fora está no backlog no fim
> deste plano.

## O que eu quero
- O Cadex nativo no Linux sobre o mesmo núcleo, só Wayland, sem Electron/Tauri.
- Núcleo primeiro: `cd core && zig build test` verde no Linux antes de qualquer janela.
- `apps/linux/` em GTK4, uma feature por pasta, com os mesmos ids de comando do Mac e do
  Windows (`docs/adr/0005-every-action-is-a-command.md`).
- Instalação em um passo (AppImage ou .deb/.rpm) e o mesmo settings.json das outras
  plataformas.
- Uma feature por PR, com `CLAUDE.md` e testes, como no port do Windows.

## O que eu não quero
- X11, XWayland ou teste em X11.
- Começar a interface antes do núcleo passar no Linux.
- WebView para a interface; WebKitGTK só no preview (como o WebView2 no Windows).
- Poppler no binário (GPL-2.0): PDF por pdf.js.
- Dependência nova sem ADR e sem linha no `NOTICE`.
- Prometer paridade sem testar IME em Wayland.
- Refatorar o app Windows para "compartilhar" a casca: o custo é maior que duplicar.

## Como eu quero
Fases, uma por PR; o índice de PRs e os critérios de cada uma ficam na issue do repositório.

| # | fase | entrega | critério |
|---|---|---|---|
| 0 | docs | ADR 0021, este plano, manifestos | `make manifests` verde; dono aprova |
| 1 | núcleo | build, fs, pty, inotify, shell, CI | `zig build test` verde em Ubuntu 24.04 e Fedora 44 |
| 2 | janela e terminal | app GTK4, Cairo/Pango (fallback do atlas GL), teclado/IME/clipboard | janela, shell, digitação, busca, clipboard e cópia testados no Sway headless |
| 3 | casca | abas, uma divisão por aba, paleta, temas, configurações, atalhos, barra, spaces em memória, casca da barra lateral | janela e atalhos testados no Sway headless; paridade completa e divisões recursivas no backlog |
| 4 | documentos | explorer em lista plana com watcher, busca de nome e conteúdo, editor com realce (Markdown editável, prévia Pango provisória), git (status, stage, commit, push/pull/fetch, diff) e histórico com detalhes | abrir, editar, salvar, buscar, diff, commit e histórico testados no Sway headless |
| 5 | previews e integrações | WebKitGTK, GStreamer, power, SSH, agents, updates, SNI, picker | preview, mídia, inibição, agentes |
| 6 | release | AppImage, .deb/.rpm, install.sh, CI, README | instalação limpa em um comando |

- `apps/linux/` segue `apps/windows/`: um build próprio que traduz `core/include/cadex.h` e
  liga a libcadex.a; pastas de feature com o mesmo nome do núcleo; shared/ só com o que
  2+ features usam.
- O build do app descobre as bibliotecas do sistema por `pkg-config`: GTK4 (>= 4.14),
  WebKitGTK 6.0 (>= 2.44), GStreamer, GdkPixbuf, HarfBuzz, FreeType e fontconfig.
- `make linux-core`, `make linux-app`, `make linux-run` e `make linux-package`.
- CI em `ubuntu:24.04` e `fedora:44`; smoke headless com Sway e `grim`.
- A bandeja usa StatusNotifierItem; no Mango ela não aparece. O README diz isso.
- O `NOTICE` ganha cada biblioteca na tarefa que a adiciona, não antes.

## Como validar
- `cd core && zig build test` nas duas imagens.
- `make check` continua verde no macOS.
- App no Fedora 44 + Mango: `vim`, `htop`, IME (Fcitx5/IBus), clipboard de imagem,
  notificações, `systemd-inhibit --list`, SSH, agents, element picker e self-update.
- `python3 tools/check_command_parity.py` passa com o terceiro app.
- Tamanho e memória medidos no README; release marcada **preview**.

## Backlog (depois da fase 5)

Itens que ficaram pendentes nas fases 1–4, para não bloquear o resto do port:

- **Fase 1:** `make check` no macOS (dispensado no fork), workflow de CI aprovado no
  GitHub, aarch64 e o limite de `max_user_watches` do inotify.
- **Fase 2:** atlas GL (`GtkGLArea`) para performance/memória, IME CJK com Fcitx5/IBus,
  seleção por mouse/roda/links exercitados, `vim`/`htop` no host de teste e a duplicação
  cosmética do título no Sway.
- **Fase 3:** divisões recursivas (hoje uma por aba), spaces persistidos e restaurados,
  catálogo completo de temas do Mac/Windows, edição de atalhos, branch/agentes/uso na
  barra de status e a extensão do `tools/check_command_parity.py` para o app Linux.
- **Fase 4:** árvore do explorer (hoje lista plana), renomear/mover/apagar arquivos,
  números de linha e folds na interface, prévia WebKit e o índice de notas
  (headings/backlinks/links) do Markdown, troca e inicialização de branch, os dois lados
  do diff, push/pull/fetch exercitados contra um remoto, cancelamento visível da busca e
  Ctrl+clique nos links do Markdown.

O backlog não entra em nenhuma das fases 4 e 5; ele é a última etapa, depois do release.
