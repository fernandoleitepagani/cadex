# documents (app Linux)

## O que eu quero
- A parte sem GTK dos documentos: transformar o HTML do núcleo em markup do Pango e ler
  as listas de status, log e detalhes do git que o núcleo devolve.
- Um lugar testável para `markdown.zig` e `git.zig`, usado pelo `../../app/main.zig`.

## O que eu não quero
- Widgets aqui: a interface (GtkTextView, listas, janelas) fica no `../../app/main.zig`.
- Reimplementar o git ou o Markdown: o núcleo faz o trabalho e entrega HTML/linhas
  separadas por tab.
- Renderizador WebKit: a prévia real chega na fase 5; aqui a prévia é Pango.

## Como eu quero
- `documents.zig` reexporta os dois módulos.
- `markdown.zig`: `toPango` converte o corpo HTML (títulos, ênfase, listas, código,
  links e blocos) em markup válido, com fechamento das tags e entidades.
- `git.zig`: `parseStatus`, `parseLog` e `parseDetails` copiam os campos para o alocador
  do app; `freeLog`/`freeCommit`/`deinit` devolvem a memória.
- Testes de unidade rodam com `zig build test` no diretório `apps/linux`.

## Como validar
- `make linux-core && cd apps/linux && zig build test`.
- Abrir um `.md` e conferir a prévia; abrir a página Git e conferir o diff, o commit e o
  histórico.
