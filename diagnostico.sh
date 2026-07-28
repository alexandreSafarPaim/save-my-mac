#!/bin/bash
# Coleta tudo que precisamos sobre o travamento do SaveMyMac, num arquivo só.
#
# Uso:
#   1. Abra o SaveMyMac e espere ele travar.
#   2. Rode:  ./diagnostico.sh
#   3. Mande o conteúdo de /tmp/savemymac-diagnostico.txt
#
# Pede a senha uma vez, para o spindump. O `sample` já falhou em ler as threads
# deste processo; o spindump usa um mecanismo diferente (stackshot do kernel) e
# costuma funcionar onde o sample desiste.

OUT=/tmp/savemymac-diagnostico.txt
: > "$OUT"

say() { echo "$@" | tee -a "$OUT"; }
sec() { echo "" >> "$OUT"; echo "===== $* =====" >> "$OUT"; }

say "SaveMyMac — diagnóstico  $(date '+%Y-%m-%d %H:%M:%S')"

PID=$(pgrep -x SaveMyMac | head -1)
if [ -z "$PID" ]; then
  say "!! O SaveMyMac não está rodando. Abra o app, espere travar e rode de novo."
else
  say "pid: $PID"
fi

# ---------------------------------------------------------------- 1. binário
# Já perdemos tempo depurando uma cópia antiga. Isto tira a dúvida primeiro.
sec "QUAL BINÁRIO ESTÁ RODANDO"
for APP in /Applications/SaveMyMac.app "$HOME/Applications/SaveMyMac.app"; do
  BIN="$APP/Contents/MacOS/SaveMyMac"
  [ -f "$BIN" ] && {
    echo "$BIN" >> "$OUT"
    stat -f '   modificado: %Sm   tamanho: %z bytes' -t '%Y-%m-%d %H:%M:%S' "$BIN" >> "$OUT"
    lipo -archs "$BIN" 2>/dev/null | sed 's/^/   arquiteturas: /' >> "$OUT"
  }
done
[ -n "$PID" ] && ps -o comm= -p "$PID" | sed 's/^/em execução: /' >> "$OUT"

# O binário instalado é mais velho que o código-fonte? Então a compilação não
# chegou lá, e tudo abaixo descreve uma versão que não existe mais.
SRC=$(cd "$(dirname "$0")/SaveMyMac" 2>/dev/null && \
      find Sources -name '*.swift' -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
BIN=/Applications/SaveMyMac.app/Contents/MacOS/SaveMyMac
if [ -n "$SRC" ] && [ -f "$BIN" ]; then
  BINT=$(stat -f '%m' "$BIN")
  if [ "$SRC" -gt "$BINT" ]; then
    say ""
    say "########################################################################"
    say "#  ATENÇÃO: o app instalado é MAIS ANTIGO que o código-fonte.          #"
    say "#  A última compilação não chegou ao /Applications.                    #"
    say "#  Rode  ./build.sh --install --run  e DEIXE TERMINAR antes de repetir #"
    say "#  este diagnóstico. O que vem abaixo descreve uma versão obsoleta.    #"
    say "########################################################################"
    say ""
  fi
fi

# ------------------------------------------------------------------ 2. rastro
# A parte mais importante: a última linha diz onde o app parou.
sec "RASTRO DE EXECUÇÃO (~/Library/Logs/SaveMyMac-trace.log)"
TRACE="$HOME/Library/Logs/SaveMyMac-trace.log"
if [ -f "$TRACE" ]; then
  echo "--- primeiras 40 linhas ---" >> "$OUT"
  head -40 "$TRACE" >> "$OUT"
  echo "--- últimas 60 linhas (AQUI ESTÁ A RESPOSTA) ---" >> "$OUT"
  tail -60 "$TRACE" >> "$OUT"
  echo "--- total: $(wc -l < "$TRACE") linhas ---" >> "$OUT"
else
  echo "!! Não existe. O app rodando é uma versão SEM instrumentação —" >> "$OUT"
  echo "   ou seja, a compilação não chegou ao app que você abriu." >> "$OUT"
fi

# ------------------------------------------------------------- 3. recursos
# Threads e descritores crescendo sem parar apontam para acúmulo de tarefas.
if [ -n "$PID" ]; then
  sec "RECURSOS DO PROCESSO"
  echo "threads: $(ps -M "$PID" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')" >> "$OUT"
  echo "descritores abertos: $(lsof -p "$PID" 2>/dev/null | wc -l | tr -d ' ')" >> "$OUT"
  ps -o pid,%cpu,%mem,rss,state,wq,etime -p "$PID" >> "$OUT" 2>&1
  echo "" >> "$OUT"
  echo "-- subprocessos deixados para trás (ps/zumbis) --" >> "$OUT"
  ps -axo pid,ppid,state,comm | awk -v p="$PID" '$2==p' >> "$OUT"
fi

# ------------------------------------------------------------- 4. spindump
sec "SPINDUMP (pilhas reais)"
if [ -n "$PID" ]; then
  echo "Pedindo a senha para o spindump…"
  sudo spindump "$PID" 5 -file /tmp/savemymac-spindump.txt >/dev/null 2>&1
  if [ -f /tmp/savemymac-spindump.txt ]; then
    # Só as pilhas, sem o catálogo gigante de binários no fim.
    sed -n '/^Process:/,/^Binary Images:/p' /tmp/savemymac-spindump.txt \
      | head -250 >> "$OUT"
  else
    echo "!! spindump não produziu arquivo." >> "$OUT"
  fi
fi

# ------------------------------------------------------------ 5. saúde do hidd
# Se o hidd estiver sofrendo, o congelamento é do sistema todo, não do app.
sec "hidd (daemon de teclado/mouse)"
ps -axo pid,%cpu,%mem,etime,comm | grep -E '[h]idd' >> "$OUT" 2>&1

say ""
say "Pronto: $OUT"
say "Abra com:  open -e $OUT"
