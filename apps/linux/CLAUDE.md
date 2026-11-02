# apps/linux — app Linux

## O que eu quero
- Um app Linux nativo sobre o mesmo núcleo, só Wayland, com as features do Mac.
- A fase 2 do plano 18 (`../../docs/plans/18-linux.md`) entrega uma janela e um terminal
  completos; as abas e a casca chegam na fase 3.

## O que eu não quero
- X11, XWayland ou teste em X11.
- WebView para a interface (a exceção é a feature preview, na fase 5).
- Lógica de terminal aqui: PTY, teclas, seleção, busca e colagem vêm do núcleo.
- Headers do GTK no Zig: o GLib 2.88 quebra o `translate-c` por causa de `_Pragma` nas
  declarações. O C fica em `shared/system/gtk_shim.c`; o resto do app é Zig.
- Refatorar o app Windows para compartilhar a casca: a duplicação é mais barata.

## Como eu quero
- Zig com GTK4 e Wayland. `build.zig` descobre GTK4/Pango/Cairo por `pkg-config` e liga
  a libcadex.a (feito por `make linux-core`). `shared/system/gtk_shim.c` compila GTK,
  Pango e Cairo e expõe `shared/system/gtk_shim.h` ao Zig; `shared/system/system.zig` é a
  importação.
- Requisitos: `gtk4-devel` no Fedora ou `libgtk-4-dev` no Ubuntu, `pkg-config` e Zig 0.16.
- `app/main.zig`: a janela, a barra de título, o terminal, o teclado/IME, o mouse, o
  clipboard, a busca, `CADEX_BACKGROUND=1` e o gate de Wayland. Sem `WAYLAND_DISPLAY`, o
  app sai com uma mensagem clara.
- `features/terminal/terminal.zig`: a porta de entrada do núcleo (sessão, frame, teclas,
  seleção, busca, link, cores, cursor). O desenho é do `app/main.zig`, com Cairo/Pango por
  célula; o atlas GL é a otimização seguinte (ADR 0021).
- Atalhos: Ctrl+Shift+Q/W sair, Ctrl+Shift+C/V copiar/colar, Ctrl+Shift+A selecionar tudo,
  Ctrl+Shift+F buscar, Enter/Shift+Enter próximo/anterior, Esc fechar a busca.
- A busca usa `cadex_terminal_search_*`; a colagem, `cadex_terminal_paste`; o mouse,
  `cadex_terminal_select_*`, ou `cadex_terminal_mouse` quando o programa pede o mouse.
- A janela abre na pasta em que o app foi iniciado (o shell herda o `cwd`).

## Como validar
- `make linux-core && cd apps/linux && zig build`.
- Headless Sway: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway`,
  depois rodar o `cadex` com o `WAYLAND_DISPLAY` do Sway e capturar com `grim`; digitar com
  `wtype` e testar o clipboard com `wl-copy` e `wl-paste`.
- No host: `WAYLAND_DISPLAY=wayland-0 zig-out/bin/cadex`.
- A memória com um terminal é medida a cada fase; a renderização atual é Cairo/Pango.
