#!/bin/bash
# Diagnóstico: o que está dentro do DMG que você tem, e o que deveria estar.
cd "$(dirname "$0")" 2>/dev/null || true
PROJ="/Volumes/SsdMac/pessoal/save_my_mac/SaveMyMac"
cd "$PROJ" || { echo "projeto não encontrado"; exit 1; }

echo "=== volumes SaveMyMac montados agora ==="
ls -d /Volumes/SaveMyMac* 2>/dev/null || echo "  nenhum"

echo
echo "=== md5 do fundo em Resources (o correto) ==="
md5 -q Resources/dmg-background.png

echo
echo "=== md5 do fundo dentro do DMG gerado ==="
if [ -f build/SaveMyMac.dmg ]; then
  OUT=$(hdiutil attach -readonly -noverify -noautoopen build/SaveMyMac.dmg 2>/dev/null)
  MP=$(echo "$OUT" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)
  if [ -n "$MP" ] && [ -f "$MP/.background/background.png" ]; then
    md5 -q "$MP/.background/background.png"
  else
    echo "  não encontrei .background/background.png dentro do DMG"
  fi
  [ -n "$MP" ] && hdiutil detach "$MP" -force >/dev/null 2>&1
else
  echo "  build/SaveMyMac.dmg não existe"
fi
