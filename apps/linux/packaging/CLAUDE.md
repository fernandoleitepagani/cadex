# apps/linux/packaging — pacotes Linux

## O que eu quero
- Gerar os três artefatos da fase 5: AppImage, `.deb` e `.rpm`, com as bibliotecas do
  sistema (GTK4/libadwaita/WebKitGTK/GStreamer), sem empacotar o WebKit.
- Um `install.sh` sem root que baixa o AppImage e instala em `~/.local/bin`, e um
  `release.sh` que só roda com `CADEX_LINUX=1`.

## O que eu não quero
- Flatpak/Snap nesta fase.
- Baixar ou embutir GTK/WebKit dentro do AppImage.
- Publicar automaticamente: o release continua sendo um passo manual do dono.
- Poppler no binário (PDF por pdf.js fica no backlog).

## Como eu quero
- `build.sh`: faz `make linux-core`, compila o app em ReleaseFast, monta um AppDir, tenta
  o `appimagetool` (se existir), monta o `.deb` com `ar`/`tar` (sem `dpkg-deb`) e o `.rpm`
  com `rpmbuild`; calcula `SHA256SUMS`.
- `install.sh`: baixa o AppImage do release, instala em `~/.local/bin/cadex` e o
  `.desktop`/ícone em `~/.local/share`, sem root.
- `release.sh`: exige `CADEX_LINUX=1`, chama o `build.sh` e lista os artefatos para subir.
- `cadex.desktop`, `cadex.svg` e `io.github.c4duz.cadex.metainfo.xml` são os metadados
  usados pelos três pacotes.

## Como validar
- `make linux-package` no repositório.
- `ar t apps/linux/dist/Cadex-linux-x86_64.deb` mostra debian-binary, control.tar.gz e
  data.tar.gz; `rpm -qip` no `.rpm` mostra nome/versão.
- `CADEX_LINUX=1 apps/linux/packaging/release.sh` termina com os checksums.
