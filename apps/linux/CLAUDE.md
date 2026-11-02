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
- Zig com GTK4/Wayland. `build.zig` descobre GTK4/Pango/Cairo por `pkg-config` e liga
  a libcadex.a (feito por `make linux-core`); WebKitGTK 6.0 é detectado e ligado quando o
  webkitgtk-6.0.pc existe, com um fallback Pango quando não existe.
- Requisitos: gtk4-devel/libgtk-4-dev, webkitgtk6.0-devel/libwebkitgtk-6.0-dev (opcional),
  gstreamer1, pkg-config e Zig 0.16.
- `app/main.zig`: App, Space, Tab (terminal, documento ou mídia) e Pane; uma janela, um
  `GtkNotebook` por space, uma divisão por aba, a paleta, as configurações, os temas, a
  barra de status e as páginas Files/Search/Git/History/Agents/SSH.
- `features/terminal/terminal.zig`: a porta de entrada do núcleo (sessão, frame, teclas,
  seleção, busca, link, cores, cursor, diretório).
- `features/documents`: markdown.toPango é o fallback da prévia e git.parse* leem as listas
  do núcleo.
- Workspace e documentos: lista plana com watcher, editor com realce do núcleo, Markdown
  editável, prévia WebKit (ou Pango), imagem/vídeo/áudio em aba, diff e histórico.
- Agentes: lê `~/.claude/projects/*/*.jsonl`, lista as sessões mais recentes e abre o JSONL
  como texto; é só leitura, sem falar com modelo.
- SSH: lê `~/.ssh/config`, ignora padrões com `*`, `?` e `!`, e um clique abre uma aba de
  terminal rodando `ssh <host>`.
- Keep Awake usa `systemd-inhibit --what=idle:sleep` num processo filho e o encerra ao
  desligar/ao sair; sem systemd-inhibit, avisa e não falha.
- Notificações por `GNotification` no sino do terminal quando a janela não está ativa; a
  paleta tem "Test Notification".
- Temas embutidos aplicam cores ANSI ao terminal, cores de token ao editor, CSS à janela e
  o mesmo esquema ao WebKit; settings.json fica em $XDG_CONFIG_HOME/cadex/settings.json.
- Atalhos: Ctrl+Shift+K paleta, T nova aba, W fechar aba, PgDn/PgUp próxima/anterior,
  D dividir à direita, Alt+D dividir abaixo, F buscar (terminal) ou conteúdo (documento),
  C/V copiar/colar, A selecionar tudo, B barra lateral, E explorer, P busca, G git,
  H histórico, S salvar, M prévia Markdown, Alt+C mensagem de commit, Alt+P acordado,
  N novo space, Alt+PgDn/PgUp trocar de space, `,` configurações, Q sair.
- Pacotes em `packaging/`: `packaging/build.sh` monta AppImage (quando há appimagetool), `.deb` com
  ar/tar e `.rpm` com rpmbuild; `packaging/install.sh` instala o AppImage sem root; `packaging/release.sh` só
  roda com CADEX_LINUX=1.
- `CADEX_BACKGROUND=1` mostra a janela sem tomar foco; sem `WAYLAND_DISPLAY`, o app sai com
  a mensagem clara.

## Como validar
- `make linux-core && cd apps/linux && zig build && zig build test`.
- Headless Sway: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway`,
  rodar o `cadex` com o `WAYLAND_DISPLAY` do Sway e capturar com `grim`; digitar com
  `wtype`; testar clipboard com `wl-copy`/`wl-paste`.
- Abrir um `.md` (prévia WebKit), uma imagem (GtkPicture), a página Agents (com um
  `~/.claude/projects/.../*.jsonl`) e a página SSH (com `~/.ssh/config`); clicar num host
  deve abrir `ssh` numa aba.
- `make linux-package`; conferir `dist/AppDir/cadex.png`, o `.deb` (`ar t`) e o `.rpm`
  (`rpm -qip`); rodar o AppImage com `APPIMAGE_EXTRACT_AND_RUN=1`.
- Medir RSS com o binário ReleaseFast; hoje ~208 MB com um terminal e ~237 MB com um
  documento WebKit aberto.

## Backlog (depois desta fase)
- Element picker do preview, preview de URL/servidor local e PDF por pdf.js.
- Agents completo: estado (trabalhando/escutando), subagentes, uso de 5h/semana, notificação
  por evento e clique que abre o terminal da sessão; página Accounts.
- SSH com probe de disponibilidade (ConnectTimeout=2) e múltiplas contas.
- Atualização do AppImage (latest.json assinado, SHA-256, `.old` e rollback); no `.deb`/`.rpm`
  só notificar.
- Tray StatusNotifierItem/DBusMenu e verificação em GNOME/KDE.
- Power por D-Bus logind + idle-inhibit do Wayland (hoje um filho de systemd-inhibit).
- Vídeo/áudio e notificações com um daemon real; AppImage/CI num runner limpo; aarch64.
- Tudo o que ficou das fases 1–4 (árvore do explorer, renomear/mover/apagar, números de
  linha/folds, branch/init, lados do diff, divisões recursivas, spaces, temas, atalhos,
  itens da barra, paridade de comandos, GL atlas, IME, mouse/wheel/links, `vim`/`htop`).
