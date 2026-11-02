# apps/linux — app Linux

## O que eu quero
- Um app Linux nativo sobre o mesmo núcleo, só Wayland, com as features do Mac.
- A fase 3 do plano 18 (`../../docs/plans/18-linux.md`) entrega a casca: abas, uma divisão
  por aba, paleta, temas, configurações, barra de status, spaces em memória e a casca da
  barra lateral.

## O que eu não quero
- X11, XWayland ou teste em X11.
- WebView para a interface (a exceção é preview, na fase 5).
- Lógica de terminal aqui: PTY, teclas, seleção, busca e colagem vêm do núcleo.
- Headers do GTK no Zig: o GLib 2.88 quebra o `translate-c`; o C fica em
  `shared/system/gtk_shim.c` e o Zig vê uma API pequena.
- Refatorar o app Windows para compartilhar a casca.

## Como eu quero
- Zig com GTK4/Wayland. `build.zig` descobre GTK4/Pango/Cairo por `pkg-config` e liga
  a libcadex.a (feito por `make linux-core`); `shared/system/system.zig` importa o shim.
- Requisitos: `gtk4-devel` no Fedora ou `libgtk-4-dev` no Ubuntu, `pkg-config` e Zig 0.16.
- `app/main.zig`: App, Space, Tab e Pane; uma janela, um `GtkNotebook` por space, uma
  divisão horizontal/vertical por aba, a paleta (janela modal com lista de comandos), a
  janela de configurações, os temas, a barra de status e a casca da barra lateral.
- `features/terminal/terminal.zig`: a porta de entrada do núcleo (sessão, frame, teclas,
  seleção, busca, link, cores, cursor, diretório).
- Temas embutidos (Cadex Dark/Light, Solarized Dark/Light) aplicam cores ANSI ao terminal e
  CSS à janela; settings.json fica em $XDG_CONFIG_HOME/cadex/settings.json (ou
  ~/.config/cadex/settings.json) com tema, tamanho da fonte, cursor e barra lateral.
- Atalhos: Ctrl+Shift+K paleta, T nova aba, W fechar aba, PgDn/PgUp próxima/anterior,
  D dividir à direita, Alt+D dividir abaixo, F buscar, C/V copiar/colar, A selecionar
  tudo, B barra lateral, N novo space, Alt+PgDn/PgUp trocar de space, `,` configurações,
  Q sair. O resto vai ao shell com CADEX_MOD_*.
- `CADEX_BACKGROUND=1` mostra a janela sem tomar foco; sem `WAYLAND_DISPLAY`, o app sai
  com a mensagem clara.
- O que fica para o backlog (depois das fases 4 e 5): divisões recursivas, spaces
  persistidos/restaurados, catálogo completo de temas, edição de atalhos, branch na barra
  de status e paridade de comandos do script.

## Como validar
- `make linux-core && cd apps/linux && zig build`.
- Headless Sway: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway`,
  rodar o `cadex` com o `WAYLAND_DISPLAY` do Sway e capturar com `grim`; digitar com
  `wtype`; testar clipboard com `wl-copy`/`wl-paste`.
- Abas (Ctrl+Shift+T), divisão (Ctrl+Shift+D), paleta (Ctrl+Shift+K), configurações
  (Ctrl+Shift+,), spaces (Ctrl+Shift+N) e barra lateral (Ctrl+Shift+B).
