# apps/linux — app Linux

## O que eu quero
- Um app Linux nativo sobre o mesmo núcleo, só Wayland, com as features do Mac.
- A fase 3 entregou a casca (abas, uma divisão por aba, paleta, temas, configurações, barra
  de status e spaces em memória); a fase 4 entregou os documentos (explorer, busca, editor,
  Markdown, git e histórico).
- A fase 5 entrega os previews e as integrações: Markdown no WebKitGTK, imagem/vídeo/áudio,
  páginas Agents e SSH, Keep Awake, notificações e os pacotes AppImage/.deb/.rpm.

## O que eu não quero
- X11, XWayland ou teste em X11.
- WebView para a interface; WebKitGTK só no preview, e opcional na compilação.
- Lógica de terminal, documento, git ou Markdown aqui: tudo vem do núcleo.
- Headers do GTK/WebKit no Zig: o GLib 2.88 quebra o `translate-c`; o C fica em
  `shared/system/gtk_shim.c` e o Zig vê uma API pequena.
- Refatorar o app Windows para compartilhar a casca.

## Como eu quero
- Zig com GTK4/libadwaita/Wayland. `build.zig` descobre GTK4/Pango/Cairo e libadwaita por
  `pkg-config` e liga a libcadex.a (feito por `make linux-core`); WebKitGTK 6.0 é detectado
  e ligado quando o webkitgtk-6.0.pc existe, com um fallback Pango quando não existe.
- Requisitos: gtk4-devel/libgtk-4-dev, libadwaita-devel/libadwaita-1-dev,
  webkitgtk6.0-devel/libwebkitgtk-6.0-dev (opcional), gstreamer1, pkg-config e Zig 0.16.
- `app/main.zig`: App, Space, Tab (terminal, documento, mídia, Web/PDF) e uma árvore de
  panes (`Node`/`Split`) com divisões recursivas. A casca é libadwaita:
  `AdwApplicationWindow` + `AdwToolbarView` com uma barra superior integrada
  (`AdwHeaderBar`), abas `AdwTabBar` no centro (uma barra só, trocando de `AdwTabView`
  com o space), controles de navegação à esquerda e ações à direita; a barra inferior
  mostra pasta, branch, abas e estatísticas. `AdwOverlaySplitView` separa a barra
  lateral (240 px) do painel de conteúdo, `AdwViewStack`/`AdwViewSwitcher` cuidam dos
  spaces, e há `AdwPreferencesWindow`, `AdwActionRow`/`AdwStatusPage` e toasts. A barra
  lateral é navegação (Terminal, Files, Search, Git, History, Agents, SSH) e as páginas
  abrem na área principal, não dentro da barra.
- spaces.json guarda os spaces e quantos terminais cada um tinha; ao abrir, o app recria
  as abas de terminal (documentos não são restaurados).
- Doze temas embutidos (Caffeine, Caffeine Light, Cadex, Solarized, Nord, Dracula,
  Gruvbox, Tokyo Night, One Dark, Catppuccin). O Caffeine é o padrão: a interface mantém a estrutura do macOS Cadex
  (chrome `#222226`, barra lateral `#2e2e32`, painel `#1d1d20`, destaque `#ffe0c2`) e
  o terminal usa a paleta noturna padrão do GNOME Console (fundo `#1d1d20`, texto
  branco); os demais temas derivam a interface das cores do terminal. A paleta do tema vale para a
  interface, o terminal, o editor e a prévia WebKit; o claro/escuro é forçado pelo
  `AdwStyleManager`.
- `features/terminal/terminal.zig`: a porta de entrada do núcleo (sessão, frame, teclas,
  seleção, busca, link, cores, cursor, diretório).
- `features/documents`: markdown.toPango é o fallback da prévia e git.parse* leem as listas
  do núcleo.
- Workspace e documentos: lista plana com watcher, editor com realce do núcleo, Markdown
  editável, prévia WebKit (ou Pango), imagem/vídeo/áudio em aba, diff e histórico.
- Agentes: lê `~/.claude/projects/*/*.jsonl`, mostra estado (working/waiting/done) e
  tokens aproximados, lista as mais recentes e abre o JSONL como texto; é só leitura.
- SSH: lê `~/.ssh/config`, ignora padrões com `*`, `?` e `!`, testa cada host com
  `ssh -o ConnectTimeout=2` em paralelo, e um clique abre uma aba rodando `ssh <host>`.
- Keep Awake usa `systemd-inhibit --what=idle:sleep` num processo filho e o encerra ao
  desligar/ao sair; sem systemd-inhibit, avisa e não falha.
- Notificações por `GNotification` no sino do terminal quando a janela não está ativa; a
  paleta tem "Test Notification". O tray é um StatusNotifierItem com DBusMenu vazio
  registrado no watcher; no GNOME/KDE não foi testado.
- A barra inferior (estilo macOS) mostra a pasta do terminal em foco, a branch, RAM,
  portas e load e o número de abas; o título da janela segue a página/aba atual.
  Confirmações são toasts. settings.json fica em $XDG_CONFIG_HOME/cadex/settings.json.
- Atalhos: Ctrl+Shift+K paleta, T nova aba, W fechar aba, PgDn/PgUp próxima/anterior,
  D dividir à direita, Alt+D dividir abaixo, F buscar (terminal) ou conteúdo (documento),
  C/V copiar/colar, A selecionar tudo, B barra lateral, E explorer, P busca, G git,
  H histórico, S salvar, M prévia Markdown, Alt+C mensagem de commit, Alt+P acordado,
  N novo space, Alt+PgDn/PgUp trocar de space, `,` configurações, Q sair.
- Explorador: lista plana, watcher, criar/renomear e mover para a lixeira; o editor tem
  números de linha; o Markdown tem prévia WebKit, headings/backlinks e link preview por URL
  (http/https) ou PDF local (WebKit). O diff tem patch e lado a lado; o Git troca branch e
  inicializa repositório.
- Pacotes em `packaging/`: `packaging/build.sh` monta AppImage, `.deb` com ar/tar e `.rpm`
  com rpmbuild; `packaging/install.sh` instala o AppImage sem root; `packaging/release.sh`
  só roda com CADEX_LINUX=1.
- `CADEX_BACKGROUND=1` mostra a janela sem tomar foco; sem `WAYLAND_DISPLAY`, o app sai com
  a mensagem clara.

## Como validar
- `make linux-core && cd apps/linux && zig build && zig build test`.
- Headless Sway: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway`,
  rodar o `cadex` com o `WAYLAND_DISPLAY` do Sway e capturar com `grim`; digitar com
  `wtype`; testar clipboard com `wl-copy`/`wl-paste`.
- Abrir um `.md` (prévia WebKit e headings/backlinks), uma imagem, vídeo/áudio, um PDF e
  uma URL local; a página Agents com `~/.claude/projects/.../*.jsonl`; a página SSH com
  `~/.ssh/config` (hosts testados e `ssh` numa aba); divisões recursivas; spaces após
  reiniciar; branch/init; renomear/lixeira; side-by-side diff.
- `make linux-package`; conferir `dist/AppDir/cadex.png`, o `.deb` (`ar t`) e o `.rpm`
  (`rpm -qip`); rodar o AppImage com `APPIMAGE_EXTRACT_AND_RUN=1`.
- Medir RSS com o binário ReleaseFast; hoje ~244 MB com um terminal e ~277 MB com um
  documento WebKit aberto (a casca libadwaita soma ~28 MB).

## Backlog restante
- Atlas GL no terminal (hoje Cairo/Pango), IME CJK (sem engine no host) e seleção/roda/links
  por mouse no Sway headless (o seat não tem ponteiro).
- Árvore do explorador, copiar/colar arquivos, mostrar ocultos e colapsar; folds, zoom de
  mídia, renomear/fechar/colorir aba e space, busca no histórico, abrir link do editor
  Markdown, acentos/importação/alto contraste de tema e reabrir a pasta do workspace.
- Atualização do AppImage (latest.json assinado, SHA-256, `.old` e rollback), página
  Accounts, power por D-Bus logind + idle-inhibit (hoje systemd-inhibit), aarch64 e a
  instalação/CI num runner limpo.
- macOS `make check`, GNOME/KDE e o tray visual nesses ambientes: fora do escopo desta
  máquina, por decisão.
