#!/bin/bash
#
# build.sh - compila o Save My Mac e monta o bundle .app
#
# Uso:
#   ./build.sh              -> compila para a arquitetura da sua máquina
#   ./build.sh --universal  -> compila binário universal (arm64 + x86_64)
#   ./build.sh --run        -> compila e abre o app
#   ./build.sh --install    -> instala em /Applications (Launchpad, Spotlight)
#   ./build.sh --dmg        -> gera um .dmg de instalação para distribuir
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SaveMyMac"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MIN_MACOS="13.0"

UNIVERSAL=0
RUN=0
INSTALL=0
MAKE_DMG=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --run) RUN=1 ;;
    --install) INSTALL=1 ;;
    --dmg) MAKE_DMG=1 ;;
    *) echo "Argumento desconhecido: $arg"; exit 1 ;;
  esac
done

# ---------- pré-requisitos ----------
if ! command -v swiftc >/dev/null 2>&1; then
  echo "ERRO: swiftc não encontrado."
  echo "Instale as Command Line Tools:  xcode-select --install"
  exit 1
fi

echo "==> Swift: $(swiftc --version | head -n1)"

# ---------- coleta de fontes ----------
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done \
  < <(find Sources -name '*.swift' -print0 | sort -z)

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "ERRO: nenhum arquivo .swift encontrado em Sources/"
  exit 1
fi
echo "==> ${#SOURCES[@]} arquivos Swift"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

COMMON_FLAGS=(
  -parse-as-library
  -swift-version 5
  -O
  -framework SwiftUI
  -framework AppKit
  -framework IOKit
  -framework Foundation
  -framework UserNotifications
  -framework ServiceManagement
)

compile_arch () {
  local arch="$1"
  local out="$2"
  echo "==> Compilando para $arch ..."
  swiftc "${COMMON_FLAGS[@]}" \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    -o "$out" \
    "${SOURCES[@]}"
}

if [ "$UNIVERSAL" -eq 1 ]; then
  compile_arch arm64  "$BUILD_DIR/${APP_NAME}-arm64"
  compile_arch x86_64 "$BUILD_DIR/${APP_NAME}-x86_64"
  lipo -create -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"
  rm -f "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"
else
  # `uname -m` devolve a arquitetura do PROCESSO, não da máquina. Com o Terminal
  # rodando sob Rosetta ele responde "x86_64" num Apple Silicon, e o app inteiro
  # sai compilado para Intel — depois roda traduzido, lento, com a interface
  # engasgando. `hw.optional.arm64` responde pelo hardware, mesmo sob Rosetta.
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
    HOST_ARCH="arm64"
  else
    HOST_ARCH="x86_64"
  fi

  if [ "$HOST_ARCH" != "$(uname -m)" ]; then
    echo "==> Atenção: este shell roda como $(uname -m), mas a máquina é $HOST_ARCH."
    echo "    Compilando nativo para $HOST_ARCH (sem Rosetta)."
  fi

  compile_arch "$HOST_ARCH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

# Confirma o que realmente saiu, para nunca mais passar despercebido.
echo "==> Binário: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || file -b "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ---------- fontes embutidas ----------
# ATSApplicationFontsPath=Fonts faz o macOS registrar tudo que estiver aqui,
# sem precisar instalar nada no sistema do usuário.
if [ -d "Resources/Fonts" ]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/Fonts"
  cp Resources/Fonts/*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/" 2>/dev/null || true
  echo "==> Fontes embutidas: $(ls -1 "$APP_BUNDLE/Contents/Resources/Fonts" | wc -l | tr -d ' ')"
fi

# ---------- ícone ----------
# A arte vem de tools/make-icon.py, que grava Resources/AppIcon.iconset.
# O iconutil (só existe no macOS) empacota tudo num .icns.
ICON_SRC="Resources/AppIcon.iconset"
ICON_OUT="Resources/AppIcon.icns"

if [ -d "$ICON_SRC" ]; then
  if command -v iconutil >/dev/null 2>&1; then
    # Regenera se o .icns não existe ou está mais velho que a arte.
    if [ ! -f "$ICON_OUT" ] || [ -n "$(find "$ICON_SRC" -newer "$ICON_OUT" -print -quit 2>/dev/null)" ]; then
      echo "==> Compilando o ícone com iconutil"
      iconutil -c icns "$ICON_SRC" -o "$ICON_OUT"
    fi
  else
    echo "   (aviso: iconutil não encontrado — o app ficará sem ícone)"
  fi
fi

if [ -f "$ICON_OUT" ]; then
  cp "$ICON_OUT" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  echo "==> Ícone embutido"
fi

# ---------- assinatura ad-hoc ----------
echo "==> Assinando (ad-hoc) ..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || \
  echo "   (aviso: codesign falhou, o app ainda deve abrir)"

# ---------- instalar em /Applications ----------
install_app () {
  local dest="/Applications/$APP_NAME.app"

  # Substituir um bundle em execução deixa um processo zumbi apontando para
  # arquivos que já não existem. Fecha antes.
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Fechando a instância em execução"
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || killall "$APP_NAME" 2>/dev/null || true
    sleep 1.5
  fi

  if [ -d "$dest" ]; then
    echo "==> Removendo a versão anterior"
    rm -rf "$dest" 2>/dev/null || {
      echo "   Sem permissão para escrever em /Applications."
      echo "   Rode:  sudo rm -rf \"$dest\"  e tente de novo,"
      echo "   ou arraste $APP_BUNDLE para Aplicativos manualmente."
      return 1
    }
  fi

  echo "==> Copiando para /Applications"
  cp -R "$APP_BUNDLE" "$dest" || {
    echo "   Falha ao copiar. Arraste $APP_BUNDLE para Aplicativos manualmente."
    return 1
  }

  # Sem isto o macOS pede confirmação a cada abertura. O app foi compilado aqui,
  # não baixado, então a quarentena não faz sentido.
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

  # Registra no Launch Services para aparecer no Spotlight e no Launchpad já.
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$lsregister" ] && "$lsregister" -f "$dest" >/dev/null 2>&1 || true

  echo ""
  echo "✅ Instalado em $dest"
  echo ""
  echo "Falta um passo, e ele não pode ser automatizado:"
  echo "  conceda Acesso Total ao Disco ao SaveMyMac."
  echo "  Abrindo o painel para você…"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
  return 0
}

# ---------- gerar o .dmg ----------
make_dmg () {
  local vol="$APP_NAME"
  local staging="$BUILD_DIR/dmg-staging"
  local rw="$BUILD_DIR/$APP_NAME-rw.dmg"
  local final="$BUILD_DIR/$APP_NAME.dmg"

  # Desmonta qualquer volume anterior com este nome.
  #
  # Isto não é higiene: é correção de bug. Com "/Volumes/SaveMyMac" ainda
  # montado de um teste anterior, o novo DMG monta como "SaveMyMac 1" e o
  # AppleScript abaixo (`tell disk "SaveMyMac"`) aplica o layout no volume
  # ANTIGO — que é o que o Finder mostra. O resultado é ver o DMG velho e jurar
  # que o novo não mudou.
  for mounted in /Volumes/"$vol"*; do
    [ -d "$mounted" ] || continue
    echo "==> Desmontando volume anterior: $mounted"
    hdiutil detach "$mounted" -force >/dev/null 2>&1 || true
  done

  echo "==> Montando a estrutura do DMG"
  rm -rf "$staging" "$rw" "$final"
  mkdir -p "$staging"
  cp -R "$APP_BUNDLE" "$staging/"
  ln -s /Applications "$staging/Applications"

  if [ -f "Resources/dmg-background.png" ]; then
    mkdir -p "$staging/.background"
    cp Resources/dmg-background.png "$staging/.background/background.png"
    [ -f "Resources/dmg-background@2x.png" ] && \
      cp "Resources/dmg-background@2x.png" "$staging/.background/background@2x.png"
  fi

  # Espaço extra para o Finder gravar o .DS_Store com o layout.
  local size_kb
  size_kb=$(du -sk "$staging" | cut -f1)
  local dmg_mb=$(( size_kb / 1024 + 60 ))

  hdiutil create -srcfolder "$staging" -volname "$vol" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${dmg_mb}m" "$rw" >/dev/null

  echo "==> Aplicando o layout da janela"
  local attach_output device mount_point volume_name
  attach_output=$(hdiutil attach -readwrite -noverify -noautoopen "$rw")
  device=$(echo "$attach_output" | awk '/^\/dev\// { print $1; exit }')
  # Usa o ponto de montagem real devolvido pelo hdiutil em vez de assumir o
  # nome — se ainda houver colisão, é aqui que ela aparece.
  mount_point=$(echo "$attach_output" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)
  volume_name=$(basename "${mount_point:-/Volumes/$vol}")
  echo "    volume montado: $volume_name"
  sleep 2

  # O layout via Finder depende da permissão de Automação. Se falhar, o DMG
  # continua perfeitamente funcional — só abre sem o fundo posicionado.
  osascript >/dev/null 2>&1 <<EOF || echo "   (aviso: layout não aplicado; o DMG funciona sem ele)"
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    try
      set background picture of opts to file ".background:background.png"
    end try
    set position of item "$APP_NAME.app" of container window to {165, 150}
    set position of item "Applications" of container window to {495, 150}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

  sync
  hdiutil detach "$device" >/dev/null 2>&1 || true
  sleep 1

  echo "==> Comprimindo"
  hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$final" >/dev/null
  rm -f "$rw"
  rm -rf "$staging"

  # Verificação: monta o DMG final e confere que o fundo dentro dele é o mesmo
  # arquivo de Resources. Barato, e responde de imediato a "regerei e não mudou".
  if [ -f "Resources/dmg-background.png" ]; then
    local check_output check_mount inside_md5 source_md5
    check_output=$(hdiutil attach -readonly -noverify -noautoopen "$final" 2>/dev/null || true)
    check_mount=$(echo "$check_output" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)
    if [ -n "$check_mount" ] && [ -f "$check_mount/.background/background.png" ]; then
      inside_md5=$(md5 -q "$check_mount/.background/background.png")
      source_md5=$(md5 -q "Resources/dmg-background.png")
      if [ "$inside_md5" = "$source_md5" ]; then
        echo "==> Fundo conferido: o DMG contém exatamente Resources/dmg-background.png"
      else
        echo "   AVISO: o fundo dentro do DMG difere de Resources/dmg-background.png"
        echo "          dentro: $inside_md5"
        echo "          fonte:  $source_md5"
      fi
    fi
    if [ -n "$check_mount" ]; then
      hdiutil detach "$check_mount" -force >/dev/null 2>&1 || true
    fi
  fi

  echo ""
  echo "✅ Instalador: $(pwd)/$final  ($(du -h "$final" | cut -f1))"
  echo ""
  echo "Atenção ao distribuir: o app é assinado ad-hoc, não notarizado."
  echo "Em OUTRO Mac, o macOS vai bloquear na primeira abertura — a pessoa"
  echo "precisa clicar com o botão direito no app e escolher Abrir."
  echo "Notarizar exige conta paga no Apple Developer Program."
}

if [ "$INSTALL" -eq 1 ]; then
  install_app || true
fi

if [ "$MAKE_DMG" -eq 1 ]; then
  make_dmg
fi

echo ""
echo "✅ Pronto: $(pwd)/$APP_BUNDLE"
echo ""
if [ "$INSTALL" -eq 0 ]; then
  echo "Para abrir:            open \"$APP_BUNDLE\""
  echo "Para instalar:         ./build.sh --install"
  echo "Para gerar o .dmg:     ./build.sh --dmg"
fi
echo ""
echo "IMPORTANTE: para varrer todas as pastas, conceda ao app"
echo "Acesso Total ao Disco em:"
echo "  Ajustes do Sistema > Privacidade e Segurança > Acesso Total ao Disco"
echo ""

if [ "$RUN" -eq 1 ]; then
  if [ "$INSTALL" -eq 1 ] && [ -d "/Applications/$APP_NAME.app" ]; then
    open "/Applications/$APP_NAME.app"
  else
    open "$APP_BUNDLE"
  fi
fi
