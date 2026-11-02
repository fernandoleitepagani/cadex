# 18 — Linux: núcleo, app GTK4 e release

Data: 2026-11-01 · Status: fases 0–6, backlog, casca libadwaita e barra superior integrada executados no fork (2026-11-02); restam itens ambientais no fim

> A fase 2 entregou o terminal com Cairo/Pango por célula (o fallback previsto no ADR
> 0021). A fase 3 entregou abas, uma divisão por aba, paleta, temas, configurações,
> barra de status, spaces em memória e a casca da barra lateral. A fase 4 entregou
> explorer, busca, editor, Markdown e git. A fase 5 entregou a prévia WebKit, mídia,
> Agents, SSH, Keep Awake, notificações e os pacotes. O backlog final acrescentou divisões
> recursivas, spaces persistidos, line numbers, headings/backlinks, URL/PDF, tray, SSH
> probe, side-by-side diff, branch/init, renomear/lixeira e a paridade de comandos.

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
| 5 | previews e integrações | WebKitGTK (opcional), GtkPicture/GtkVideo, Agents (JSONL), SSH, Keep Awake via systemd-inhibit, GNotification | prévia Markdown e imagem, agentes, SSH e inibição testados; picker, PDF, updates, SNI e Accounts no backlog |
| 6 | release | AppImage, .deb/.rpm, install.sh, release.sh, CI, README | artefatos montados e inspecionados; instalação limpa e CI ainda não rodados |

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

## Backlog restante

O backlog das fases 1–6 foi executado em 2026-11-02: divisões recursivas, spaces
persistidos, dez temas, RAM/portas/load na barra, busca com cancelamento, branch/init,
renomear/lixeira, line numbers, headings/backlinks, preview de URL, PDF pelo WebKit,
side-by-side diff, SSH probe, estado das sessões, tray SNI, element picker e a checagem de
paridade de comandos (26 ids explicitamente adiados no script). O que resta depende do
ambiente ou é uma decisão de escopo:

- **Renderização/IME:** atlas GL no terminal (Cairo/Pango é o renderer atual), IME CJK
  (o host não tem engine) e mouse/roda/links no Sway headless (o seat não tem ponteiro).
- **Explorer/editor:** árvore expansível, copiar/colar arquivos, ocultos e colapsar; folds,
  zoom de mídia, renomear/fechar/colorir aba e space, busca no histórico, abrir link do
  editor Markdown, acentos/importação/alto contraste de tema e reabrir a pasta do workspace.
- **Integrações/release:** atualização do AppImage (latest.json assinado, SHA-256, `.old` e
  rollback), página Accounts, power por D-Bus logind + idle-inhibit, aarch64 e a
  instalação/CI num runner limpo.
- **Fora do escopo desta máquina:** macOS `make check`, GNOME/KDE e o tray visual nesses
  ambientes. A casca libadwaita foi verificada no Sway headless; o comportamento CSD/SSD
  varia por compositor.

O backlog não bloqueia o uso diário do preview no Fedora/Wayland.
