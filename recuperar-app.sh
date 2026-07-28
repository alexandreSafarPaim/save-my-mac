#!/bin/bash
# Recupera o SaveMyMac de um estado travado.
#
# 1) mata o processo
# 2) desliga a barra de menus e o alerta de notificação nas preferências
# 3) mostra onde ficou o log de travamento, se houver

BUNDLE="br.com.pentagrama.savemymac"

echo "==> Encerrando o SaveMyMac"
killall -9 SaveMyMac 2>/dev/null && echo "   processo morto" || echo "   não estava rodando"

echo
echo "==> Desligando barra de menus, alerta e ícone oculto do Dock"
defaults write "$BUNDLE" showMenuBarExtra -bool false
defaults write "$BUNDLE" lowSpaceAlerts   -bool false
defaults write "$BUNDLE" hideDockIcon     -bool false
echo "   feito — o app volta a ser só a janela"

echo
echo "==> Removendo o LaunchAgent, se tiver sido criado"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE.launcher.plist"
if [ -f "$AGENT" ]; then
  launchctl bootout "gui/$(id -u)/$BUNDLE.launcher" 2>/dev/null
  rm -f "$AGENT"
  echo "   removido"
else
  echo "   não existia"
fi

echo
echo "==> Diagnóstico: onde o app travou"
echo "   Rode isto COM o app travado, numa outra janela do Terminal:"
echo "     sample SaveMyMac 5 -file /tmp/savemymac-sample.txt"
echo "   e me mande as primeiras 60 linhas:"
echo "     head -60 /tmp/savemymac-sample.txt"
echo
echo "   Travamentos registrados nas últimas horas:"
ls -lt ~/Library/Logs/DiagnosticReports/SaveMyMac* 2>/dev/null | head -5 || echo "   nenhum"
