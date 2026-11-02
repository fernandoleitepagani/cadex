#!/bin/sh
# Builds the Linux preview artifacts: AppImage (when the tool exists), .deb and .rpm.
# The binary links the system GTK4/WebKitGTK/GStreamer; none of them is bundled.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app=$(dirname "$here")
repo=$(CDPATH= cd -- "$app/../.." && pwd)
version=${CADEX_VERSION:-0.1.0}
out=${CADEX_OUT:-$app/dist}

echo "== core =="
make -C "$repo" linux-core

echo "== app =="
(cd "$app" && zig build -Doptimize=ReleaseFast)

stage="$out/AppDir"
rm -rf "$stage"
mkdir -p "$stage/usr/bin" "$stage/usr/share/applications" \
         "$stage/usr/share/icons/hicolor/scalable/apps" "$stage/usr/share/metainfo"
install -m 755 "$app/zig-out/bin/cadex" "$stage/usr/bin/cadex"
install -m 644 "$here/cadex.desktop" "$stage/usr/share/applications/cadex.desktop"
install -m 644 "$here/cadex.svg" "$stage/usr/share/icons/hicolor/scalable/apps/cadex.svg"
mkdir -p "$stage/usr/share/icons/hicolor/256x256/apps"
install -m 644 "$here/cadex.png" "$stage/usr/share/icons/hicolor/256x256/apps/cadex.png"
install -m 644 "$here/cadex.png" "$stage/cadex.png"
install -m 644 "$here/io.github.c4duz.cadex.metainfo.xml" "$stage/usr/share/metainfo/io.github.c4duz.cadex.metainfo.xml"
install -m 644 "$here/cadex.desktop" "$stage/cadex.desktop"
install -m 644 "$here/cadex.svg" "$stage/cadex.svg"
install -m 644 "$here/cadex.png" "$stage/cadex.png"
cat > "$stage/AppRun" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/usr/bin/cadex" "$@"
EOF
chmod 755 "$stage/AppRun"

echo "== AppImage =="
tool=${CADEX_APPIMAGETOOL:-}
if [ -z "$tool" ]; then tool=$(command -v appimagetool 2>/dev/null || true); fi
if [ -z "$tool" ] && [ "${CADEX_DOWNLOAD_APPIMAGETOOL:-0}" = 1 ]; then
    cache="$out/.cache"
    mkdir -p "$cache"
    tool="$cache/appimagetool"
    if [ ! -x "$tool" ]; then
        curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod 755 "$tool"
    fi
fi
if [ -n "$tool" ]; then
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$stage" "$out/Cadex-linux-x86_64.AppImage" \
        || echo "warning: appimagetool failed; the AppImage was not produced"
else
    echo "appimagetool not found: AppImage skipped (set CADEX_APPIMAGETOOL or CADEX_DOWNLOAD_APPIMAGETOOL=1)"
fi

echo "== .deb =="
debwork="$out/.deb"
rm -rf "$debwork"
mkdir -p "$debwork/DEBIAN" "$debwork/usr/bin" "$debwork/usr/share/applications" \
         "$debwork/usr/share/icons/hicolor/scalable/apps" "$debwork/usr/share/metainfo"
install -m 755 "$app/zig-out/bin/cadex" "$debwork/usr/bin/cadex"
install -m 644 "$here/cadex.desktop" "$debwork/usr/share/applications/cadex.desktop"
install -m 644 "$here/cadex.svg" "$debwork/usr/share/icons/hicolor/scalable/apps/cadex.svg"
mkdir -p "$debwork/usr/share/icons/hicolor/256x256/apps"
install -m 644 "$here/cadex.png" "$debwork/usr/share/icons/hicolor/256x256/apps/cadex.png"
install -m 644 "$here/io.github.c4duz.cadex.metainfo.xml" "$debwork/usr/share/metainfo/io.github.c4duz.cadex.metainfo.xml"
installed_size=$(du -sk "$debwork/usr" | cut -f1)
cat > "$debwork/DEBIAN/control" <<EOF
Package: cadex
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $installed_size
Depends: libgtk-4-1 (>= 4.14), libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, fonts-dejavu-core
Recommends: libwebkitgtk-6.0-4
Maintainer: Carlos Teixeira <c4duz@users.noreply.github.com>
Homepage: https://github.com/c4duZ/cadex
Description: Terminal-centric development workspace
 Terminal tabs and splits, an editor with tree-sitter highlights, Markdown notes,
 git status and history, workspace search, SSH hosts and Claude session history.
 The Linux app is a Wayland-only preview built with GTK4.
EOF
( cd "$debwork" && printf '2.0\n' > debian-binary \
    && tar -czf control.tar.gz -C DEBIAN . \
    && tar -czf data.tar.gz usr \
    && rm -f "$out/Cadex-linux-x86_64.deb" \
    && ar rcs "$out/Cadex-linux-x86_64.deb" debian-binary control.tar.gz data.tar.gz )
rm -rf "$debwork"

echo "== .rpm =="
rpmtop="$out/.rpm"
rm -rf "$rpmtop"
mkdir -p "$rpmtop/BUILD" "$rpmtop/RPMS" "$rpmtop/SOURCES" "$rpmtop/SPECS" "$rpmtop/SRPMS"
cat > "$rpmtop/SPECS/cadex.spec" <<EOF
Name: cadex
Version: $version
Release: 1%{?dist}
Summary: Terminal-centric development workspace
License: MIT
URL: https://github.com/c4duZ/cadex
BuildArch: x86_64
Requires: gtk4 >= 4.14
Recommends: webkitgtk6.0
Requires: gstreamer1
Requires: gstreamer1-plugins-base

%description
Terminal tabs and splits, an editor with tree-sitter highlights, Markdown notes,
git status and history, workspace search, SSH hosts and Claude session history.
The Linux app is a Wayland-only preview built with GTK4.

%prep
%build
%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps %{buildroot}/usr/share/icons/hicolor/256x256/apps %{buildroot}/usr/share/metainfo
install -m 755 %{stage}/usr/bin/cadex %{buildroot}/usr/bin/cadex
install -m 644 %{stage}/usr/share/applications/cadex.desktop %{buildroot}/usr/share/applications/cadex.desktop
install -m 644 %{stage}/usr/share/icons/hicolor/scalable/apps/cadex.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/cadex.svg
install -m 644 %{stage}/usr/share/icons/hicolor/256x256/apps/cadex.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/cadex.png
install -m 644 %{stage}/usr/share/metainfo/io.github.c4duz.cadex.metainfo.xml %{buildroot}/usr/share/metainfo/io.github.c4duz.cadex.metainfo.xml

%files
/usr/bin/cadex
/usr/share/applications/cadex.desktop
/usr/share/icons/hicolor/scalable/apps/cadex.svg
/usr/share/icons/hicolor/256x256/apps/cadex.png
/usr/share/metainfo/io.github.c4duz.cadex.metainfo.xml
EOF
if command -v rpmbuild >/dev/null 2>&1; then
    QA_RPATHS=${QA_RPATHS:-0x0001} rpmbuild -bb --define "_topdir $rpmtop" --define "stage $stage" "$rpmtop/SPECS/cadex.spec" >/dev/null
    cp "$rpmtop"/RPMS/x86_64/cadex-"$version"-1*.rpm "$out/Cadex-linux-x86_64.rpm"
else
    echo "rpmbuild not found: .rpm skipped"
fi
rm -rf "$rpmtop"

echo "== checksums =="
( cd "$out" && rm -f SHA256SUMS && sha256sum Cadex-linux-x86_64.* 2>/dev/null > SHA256SUMS || true )
ls -lh "$out"
[ -f "$out/SHA256SUMS" ] && cat "$out/SHA256SUMS"
