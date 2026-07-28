#!/bin/bash
# Diagnóstico do travamento. Rode COM o app travado.
#
# O `sample` sem sudo voltou vazio ("failed to get thread state") depois que o
# app passou a ser nativo — provavelmente falta de privilégio, não deadlock.
# O spindump lê processos que o sample não consegue.

PID=$(pgrep -x SaveMyMac | head -1)
if [ -z "$PID" ]; then echo "SaveMyMac não está rodando"; exit 1; fi
echo "pid $PID"

echo
echo "=== 1) sample com privilégio ==="
sudo sample "$PID" 5 -file /tmp/sm-sudo.txt >/dev/null 2>&1
sed -n '/Call graph/,/^$/p' /tmp/sm-sudo.txt | head -45

echo
echo "=== 2) spindump (lê o que o sample não lê) ==="
sudo spindump "$PID" 4 -file /tmp/sm-spin.txt >/dev/null 2>&1
grep -A 30 "Thread.*DispatchQueue_1\|com.apple.main-thread" /tmp/sm-spin.txt | head -40

echo
echo "=== 3) o app registrou algo no log? ==="
log show --predicate 'process == "SaveMyMac"' --last 5m --style compact 2>/dev/null | tail -30

echo
echo "Arquivos completos: /tmp/sm-sudo.txt e /tmp/sm-spin.txt"
