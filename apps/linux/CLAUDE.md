# apps/linux — app Linux

## O que eu quero
- Um app Linux nativo sobre o mesmo núcleo, só Wayland, com as features do Mac.
- A fase 3 do plano 18 (`../../docs/plans/18-linux.md`) entregou a casca: abas, uma
  divisão por aba, paleta, temas, configurações, barra de status e spaces em memória.
- A fase 4 entrega os documentos: explorer com watcher, busca de nomes e conteúdo,
  editor com realce do núcleo, Markdown editável com prévia, git (status, stage, commit,
  push/pull/fetch, diff) e histórico com detalhes.

## O que eu não quero
- X11, XWayland ou teste em X11.
- WebView para a interface (a exceção é preview, na fase 5).
- Lógica de terminal ou de documento aqui: PTY, teclas, seleção, realce, folds, git e
  Markdown vêm do núcleo.
- Headers do GTK no Zig: o GLib 2.88 quebra o `translate-c`; o C fica em
  `shared/system/gtk_shim.c` e o Zig vê uma API pequena.
- Refatorar o app Windows para compartilhar a casca.

## Como eu quero
- Zig com GTK4/Wayland. `build.zig` descobre GTK4/Pango/Cairo por `pkg-config` e liga
  a libcadex.a (feito por `make linux-core`); `shared/system/system.zig` importa o shim.
- Requisitos: `gtk4-devel` no Fedora ou `libgtk-4-dev` no Ubuntu, `pkg-config` e Zig 0.16.
- `app/main.zig`: App, Space, Tab (terminal ou documento) e Pane; uma janela, um
  `GtkNotebook` por space, uma divisão por aba, a paleta, as configurações, os temas, a
  barra de status e as páginas Files/Search/Git/History da barra lateral.
- `features/terminal/terminal.zig`: a porta de entrada do núcleo (sessão, frame, teclas,
  seleção, busca, link, cores, cursor, diretório).
- `features/documents`: markdown.toPango converte o HTML do núcleo para a prévia Pango
  provisória; git.parseStatus/parseLog/parseDetails leem as listas do núcleo.
- Workspace: o primeiro argumento que for pasta (ou o cwd) é autorizado; o explorer lista
  uma pasta por vez (lista plana), navega, cria arquivo/pasta e atualiza pelo watcher do
  núcleo. O editor abre numa aba: código é somente leitura, Markdown é editável e salva
  com Ctrl+Shift+S. A prévia Markdown é o Pango provisório (WebKit chega na fase 5).
- Git: status com branch/ahead/behind, Stage/Unstage/Discard, Commit All, Push/Pull/Fetch,
  diff numa aba e histórico com detalhes do commit.
- Temas embutidos (Cadex Dark/Light, Solarized Dark/Light) aplicam cores ANSI ao terminal,
  cores de token ao editor e CSS à janela; settings.json fica em
  $XDG_CONFIG_HOME/cadex/settings.json (ou ~/.config/cadex/settings.json).
- Atalhos: Ctrl+Shift+K paleta, T nova aba, W fechar aba, PgDn/PgUp próxima/anterior,
  D dividir à direita, Alt+D dividir abaixo, F buscar (terminal) ou busca de conteúdo
  (documento), C/V copiar/colar, A selecionar tudo, B barra lateral, E explorer, P busca,
  G git, H histórico, S salvar, M prévia Markdown, Alt+C mensagem de commit, N novo space,
  Alt+PgDn/PgUp trocar de space, `,` configurações, Q sair. O resto vai ao shell com
  CADEX_MOD_*.
- `CADEX_BACKGROUND=1` mostra a janela sem tomar foco; sem `WAYLAND_DISPLAY`, o app sai
  com a mensagem clara.
- O que fica para o backlog (depois da fase 5): árvore do explorer, renomear/mover/apagar,
  números de linha e folds na interface, prévia WebKit e backlinks/headings do Markdown,
  troca/inicialização de branch, push/pull/fetch num repositório com remoto, divisões
  recursivas, spaces persistidos, catálogo completo de temas, edição de atalhos, itens de
  branch/agentes/uso na barra e paridade de comandos do script.

## Como validar
- `make linux-core && cd apps/linux && zig build && zig build test`.
- Headless Sway: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway`,
  rodar o `cadex` com o `WAYLAND_DISPLAY` do Sway e capturar com `grim`; digitar com
  `wtype`; testar clipboard com `wl-copy`/`wl-paste`.
- Abrir a pasta, navegar, criar arquivo/pasta, buscar nome e conteúdo, abrir/editar/salvar
  Markdown (a prévia acompanha), ver diff, commitar e abrir os detalhes no histórico.
- Medir RSS com o binário ReleaseFast; hoje ~190 MB com um terminal e ~195 MB com um
  documento aberto, no renderer Cairo/Pango.
