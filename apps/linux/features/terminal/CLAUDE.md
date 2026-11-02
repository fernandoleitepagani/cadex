# terminal (app Linux)

## O que eu quero
- O terminal do núcleo numa janela GTK4/Wayland: um shell por painel, texto nítido,
  teclado/IME, mouse, links, busca e colagem.

## O que eu não quero
- Lógica de terminal aqui: teclas, seleção, links, busca e colagem são do núcleo.
- Desenho neste módulo: o `../../app/main.zig` desenha com Cairo/Pango; o atlas GL é
  otimização.
- Atalho do app roubando Ctrl+letra do shell.

## Como eu quero
- `terminal.zig`: a porta de entrada (`Terminal`, `Events`), `open`/`close`, frame,
  `key`, `write`, `paste`, `search*`, `select*`, `mouse`, `wheel`, `scroll`, `linkAt`,
  `setColors` e `setCursor`.
- O `../../app/main.zig` recebe os eventos do shim (`../../shared/system/gtk_shim.c`),
  chama o núcleo e desenha o `cadex_terminal_frame`.
- Atalhos do app: Ctrl+Shift+Q/W, C/V, A, F; o resto vai ao shell com CADEX_MOD_*.

## Como validar
- `make linux-core && cd apps/linux && zig build`.
- Headless Sway: digitar com `wtype`, buscar com Ctrl+Shift+F, colar com `wl-copy` e
  `wl-paste`, copiar com Ctrl+Shift+A/C.
- `vim`, `htop`, redimensionar e rolar.
