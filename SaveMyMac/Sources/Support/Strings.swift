import Foundation

/// Tabelas de tradução.
///
/// **Não existe tabela `en`.** A chave já é o texto em inglês, então inglês é o
/// caminho sem busca — e qualquer frase sem tradução cai nele. Uma tradução
/// faltando degrada para uma frase correta em outra língua, não para uma chave
/// crua na tela.
///
/// ── Como adicionar um idioma ──────────────────────────────────────────────
///
/// 1. Um `case` novo em `Language`, com o nome escrito no próprio idioma
/// 2. Um dicionário novo aqui
/// 3. Um `case` em `L(_:)` e, se a regra de plural for diferente das que já
///    existem, um `case` em `Lp`
///
/// Não é preciso traduzir tudo de uma vez. O que faltar aparece em inglês.
///
/// ── Convenções ───────────────────────────────────────────────────────────
///
/// - `%@` texto, `%d` inteiro. A ordem pode mudar entre idiomas, e é por isso
///   que existem marcadores em vez de concatenação.
/// - Reticências de menu são o caractere `…`, não três pontos.
/// - Unidades (GB, MB, °C, %) são formatadas pelo `Fmt`, que respeita o
///   `Locale` do sistema. Não entram nas tabelas.
enum Strings {

    // MARK: - Português

    static let pt: [String: String] = [
        // Idioma
        "Same as macOS": "Igual ao macOS",

        // Navegação
        "Dashboard": "Painel",
        "Cleanup": "Limpeza",
        "Apps": "Aplicativos",
        "Large files": "Grandes arquivos",
        "Duplicates": "Duplicados",
        // "Offload" não entra: é a mesma palavra em português, e entrada que
        // traduz para si mesma só ocupa espaço — a busca já cai na chave.
        "Navigation": "Navegação",

        // Faixa do topo
        "Dark": "Escuro",
        "Light": "Claro",
        "Switch between light and dark theme (⇧⌘T)": "Alternar entre tema claro e escuro (⇧⌘T)",
        "SaveMyMac settings (⌘,)": "Ajustes do SaveMyMac (⌘,)",

        // Barra lateral
        "Startup disk": "Disco de inicialização",
        "%@ free": "%@ livres",
        "of %@": "de %@",
        "Reclaimable": "Recuperável",
        "Offloaded": "Descarregado",
        "Level %d": "Nível %d",
        "No active week yet": "Nenhuma semana ativa ainda",
        "%d-week streak": "Streak de %d semana",
        "%d-week streak (plural)": "Streak de %d semanas",

        // Painel da barra de menus
        "Health": "Saúde",
        "Memory": "Memória",
        "Processor": "Processador",
        "Temperature": "Temperatura",
        "Thermal state": "Estado térmico",
        "Trash": "Lixeira",
        "Low disk space": "Pouco espaço no disco",
        "%@ free — below the %d %% threshold": "%@ livres — abaixo do limiar de %d %%",
        "Open SaveMyMac": "Abrir o SaveMyMac",
        "Analyze my Mac": "Analisar o Mac",
        "Empty the Trash (%@)": "Esvaziar a Lixeira (%@)",
        "Settings…": "Ajustes…",
        "Quit SaveMyMac": "Encerrar o SaveMyMac",

        // Ajustes — seções
        "Startup": "Inicialização",
        "Menu bar": "Barra de menus",
        "Low space alert": "Alerta de pouco espaço",
        "Appearance": "Aparência",
        "Language": "Idioma",

        // Ajustes — inicialização
        "Open SaveMyMac when the Mac starts": "Abrir o SaveMyMac ao ligar o Mac",
        "Checking…": "Verificando…",
        "Hide the Dock icon": "Esconder o ícone do Dock",
        "With the icon hidden the app lives only in the menu bar. Worth it if you leave it open all the time. Applies immediately, no restart.":
            "Com o ícone escondido o app vive só na barra de menus. Vale a pena se você deixa ele aberto o tempo todo. Aplica na hora, sem reiniciar.",
        "The app uses the modern API (system Login Items) when it can. Since this build is ad-hoc signed, registration may be refused — it then falls back to a user LaunchAgent, which works the same. The text above says which mechanism is active.":
            "O app usa a API moderna (Itens de Início do sistema) quando consegue. Como este build é assinado ad-hoc, o registro pode ser recusado — nesse caso ele cai para um LaunchAgent do usuário, que funciona igual. O texto acima diz qual mecanismo está ativo.",

        // Ajustes — barra de menus
        "Show in the menu bar": "Mostrar na barra de menus",
        "With this on, the app shows the chosen metric next to the clock and the panel opens with one click, without bringing up the window.":
            "Com isto ligado o app mostra a métrica escolhida ao lado do relógio e o painel abre com um clique, sem precisar trazer a janela.",
        "What to show next to the icon": "O que mostrar ao lado do ícone",
        "The icon turns into a warning triangle when free space drops below the threshold, whatever metric you picked.":
            "O ícone troca para um triângulo de alerta quando o espaço livre cai abaixo do limiar, independente da métrica escolhida.",
        "Turned off by the emergency switch.": "Desligada pelo interruptor de emergência.",

        // Ajustes — métricas
        "Free space": "Espaço livre",
        "Memory pressure": "Pressão de memória",
        "CPU usage": "Uso de CPU",
        "Icon only": "Só o ícone",

        // Ajustes — alertas
        "Notify me when space runs low": "Notificar quando faltar espaço",
        "Warn below": "Avisar abaixo de",
        "%d %% free": "%d %% livres",
        "Now: %@ %% free on %@ (%@).": "Agora: %@ %% livres em %@ (%@).",
        "The warning fires when crossing the threshold and only rearms after space rises 3 points above it, at most one every 6 hours. Without that, a disk hovering around the threshold would notify endlessly.":
            "O aviso dispara ao cruzar o limiar e só rearma depois de o espaço subir 3 pontos acima dele, com no máximo um por 6 horas. Sem isso, um disco oscilando em torno do limiar notificaria sem parar.",
        "Notification permission was denied. Allow it in System Settings › Notifications. The menu bar warning keeps working.":
            "A permissão de notificação foi negada. Libere em Ajustes do Sistema › Notificações. O aviso na barra de menus continua funcionando.",

        // Ajustes — idioma
        "The interface language. \"Same as macOS\" follows your system setting; anything else overrides it. Applies immediately.":
            "O idioma da interface. \"Igual ao macOS\" segue a configuração do sistema; qualquer outra opção sobrepõe. Aplica na hora.",
        // Idioma (continuação)
        "Following macOS: %@": "Seguindo o macOS: %@",
        "Numbers, sizes and dates always follow your system region, not this setting.":
            "Números, tamanhos e datas seguem sempre a região do sistema, não esta configuração.",

        // Barra de menus — interruptor de emergência
        "The `enableMenuBar` key is false, or the app is in safe mode. To turn it back on, in Terminal:":
            "A chave `enableMenuBar` está em falso, ou o app está em modo seguro. Para religar, no Terminal:",
        "then reopen the app.": "e reabra o app.",

        // Pressão de memória e estado térmico
        "Moderate": "Moderada",
        "High": "Alta",
        "Warming up": "Aquecendo",
        "Hot": "Quente",
        "Critical": "Crítico",
        "Unknown": "Desconhecido",

        // Abrir no login
        "system Login Items": "Itens de Início do sistema",
        "user LaunchAgent": "LaunchAgent do usuário",
        "disabled": "desativado",
        "Active through the system Login Items.": "Ativo pelos Itens de Início do sistema.",
        "Registered, but waiting for your approval in System Settings › General › Login Items.":
            "Registrado, mas aguardando sua aprovação em Ajustes do Sistema › Geral › Itens de Início.",
        "Active through a LaunchAgent — the fallback path, used because the app is ad-hoc signed.":
            "Ativo por LaunchAgent — o caminho alternativo, usado porque o app é assinado ad-hoc.",
        "Disabled.": "Desativado.",

    ]

    // MARK: - Español

    static let es: [String: String] = [
        "Same as macOS": "Igual que macOS",

        "Dashboard": "Panel",
        "Cleanup": "Limpieza",
        "Apps": "Aplicaciones",
        "Large files": "Archivos grandes",
        "Duplicates": "Duplicados",
        "Offload": "Descarga",
        "Navigation": "Navegación",

        "Dark": "Oscuro",
        "Light": "Claro",
        "Switch between light and dark theme (⇧⌘T)": "Cambiar entre tema claro y oscuro (⇧⌘T)",
        "SaveMyMac settings (⌘,)": "Ajustes de SaveMyMac (⌘,)",

        "Startup disk": "Disco de arranque",
        "%@ free": "%@ libres",
        "of %@": "de %@",
        "Reclaimable": "Recuperable",
        "Offloaded": "Descargado",
        "Level %d": "Nivel %d",
        "No active week yet": "Aún no hay semana activa",
        "%d-week streak": "Racha de %d semana",
        "%d-week streak (plural)": "Racha de %d semanas",

        "Health": "Salud",
        "Memory": "Memoria",
        "Processor": "Procesador",
        "Temperature": "Temperatura",
        "Thermal state": "Estado térmico",
        "Trash": "Papelera",
        "Low disk space": "Poco espacio en disco",
        "%@ free — below the %d %% threshold": "%@ libres — por debajo del umbral de %d %%",
        "Open SaveMyMac": "Abrir SaveMyMac",
        "Analyze my Mac": "Analizar el Mac",
        "Empty the Trash (%@)": "Vaciar la Papelera (%@)",
        "Settings…": "Ajustes…",
        "Quit SaveMyMac": "Salir de SaveMyMac",

        "Startup": "Inicio",
        "Menu bar": "Barra de menús",
        "Low space alert": "Alerta de poco espacio",
        "Appearance": "Apariencia",
        "Language": "Idioma",

        "Open SaveMyMac when the Mac starts": "Abrir SaveMyMac al encender el Mac",
        "Checking…": "Comprobando…",
        "Hide the Dock icon": "Ocultar el icono del Dock",
        "With the icon hidden the app lives only in the menu bar. Worth it if you leave it open all the time. Applies immediately, no restart.":
            "Con el icono oculto la app vive solo en la barra de menús. Merece la pena si la dejas abierta todo el tiempo. Se aplica al instante, sin reiniciar.",
        "The app uses the modern API (system Login Items) when it can. Since this build is ad-hoc signed, registration may be refused — it then falls back to a user LaunchAgent, which works the same. The text above says which mechanism is active.":
            "La app usa la API moderna (Ítems de inicio del sistema) cuando puede. Como esta compilación está firmada ad-hoc, el registro puede ser rechazado — en ese caso recurre a un LaunchAgent del usuario, que funciona igual. El texto de arriba indica qué mecanismo está activo.",

        "Show in the menu bar": "Mostrar en la barra de menús",
        "With this on, the app shows the chosen metric next to the clock and the panel opens with one click, without bringing up the window.":
            "Con esto activado la app muestra la métrica elegida junto al reloj y el panel se abre con un clic, sin traer la ventana.",
        "What to show next to the icon": "Qué mostrar junto al icono",
        "The icon turns into a warning triangle when free space drops below the threshold, whatever metric you picked.":
            "El icono cambia a un triángulo de advertencia cuando el espacio libre baja del umbral, sea cual sea la métrica elegida.",
        "Turned off by the emergency switch.": "Desactivada por el interruptor de emergencia.",

        "Free space": "Espacio libre",
        "Memory pressure": "Presión de memoria",
        "CPU usage": "Uso de CPU",
        "Icon only": "Solo el icono",

        "Notify me when space runs low": "Avisarme cuando quede poco espacio",
        "Warn below": "Avisar por debajo de",
        "%d %% free": "%d %% libres",
        "Now: %@ %% free on %@ (%@).": "Ahora: %@ %% libres en %@ (%@).",
        "The warning fires when crossing the threshold and only rearms after space rises 3 points above it, at most one every 6 hours. Without that, a disk hovering around the threshold would notify endlessly.":
            "El aviso salta al cruzar el umbral y solo se rearma cuando el espacio sube 3 puntos por encima, con un máximo de uno cada 6 horas. Sin eso, un disco oscilando alrededor del umbral avisaría sin parar.",
        "Notification permission was denied. Allow it in System Settings › Notifications. The menu bar warning keeps working.":
            "Se denegó el permiso de notificaciones. Actívalo en Ajustes del Sistema › Notificaciones. El aviso de la barra de menús sigue funcionando.",

        "The interface language. \"Same as macOS\" follows your system setting; anything else overrides it. Applies immediately.":
            "El idioma de la interfaz. «Igual que macOS» sigue la configuración del sistema; cualquier otra opción la sobrescribe. Se aplica al instante.",
        "Following macOS: %@": "Siguiendo a macOS: %@",
        "Numbers, sizes and dates always follow your system region, not this setting.":
            "Números, tamaños y fechas siguen siempre la región del sistema, no este ajuste.",

        "The `enableMenuBar` key is false, or the app is in safe mode. To turn it back on, in Terminal:":
            "La clave `enableMenuBar` está en falso, o la app está en modo seguro. Para reactivarla, en Terminal:",
        "then reopen the app.": "y vuelve a abrir la app.",

        "Moderate": "Moderada",
        "High": "Alta",
        "Warming up": "Calentando",
        "Hot": "Caliente",
        "Critical": "Crítico",
        "Unknown": "Desconocido",

        "system Login Items": "Ítems de inicio del sistema",
        "user LaunchAgent": "LaunchAgent del usuario",
        "disabled": "desactivado",
        "Active through the system Login Items.": "Activo mediante los Ítems de inicio del sistema.",
        "Registered, but waiting for your approval in System Settings › General › Login Items.":
            "Registrado, pero esperando tu aprobación en Ajustes del Sistema › General › Ítems de inicio.",
        "Active through a LaunchAgent — the fallback path, used because the app is ad-hoc signed.":
            "Activo mediante un LaunchAgent — la vía alternativa, usada porque la app está firmada ad-hoc.",
        "Disabled.": "Desactivado.",

    ]

    // MARK: - Français

    static let fr: [String: String] = [
        "Same as macOS": "Comme macOS",

        "Dashboard": "Tableau de bord",
        "Cleanup": "Nettoyage",
        "Apps": "Applications",
        "Large files": "Gros fichiers",
        "Duplicates": "Doublons",
        "Offload": "Déchargement",

        "Dark": "Sombre",
        "Light": "Clair",
        "Switch between light and dark theme (⇧⌘T)": "Basculer entre thème clair et sombre (⇧⌘T)",
        "SaveMyMac settings (⌘,)": "Réglages de SaveMyMac (⌘,)",

        "Startup disk": "Disque de démarrage",
        "%@ free": "%@ libres",
        "of %@": "sur %@",
        "Reclaimable": "Récupérable",
        "Offloaded": "Déchargé",
        "Level %d": "Niveau %d",
        "No active week yet": "Aucune semaine active",
        "%d-week streak": "Série de %d semaine",
        "%d-week streak (plural)": "Série de %d semaines",

        "Health": "Santé",
        "Memory": "Mémoire",
        "Processor": "Processeur",
        "Temperature": "Température",
        "Thermal state": "État thermique",
        "Trash": "Corbeille",
        "Low disk space": "Espace disque faible",
        "%@ free — below the %d %% threshold": "%@ libres — sous le seuil de %d %%",
        "Open SaveMyMac": "Ouvrir SaveMyMac",
        "Analyze my Mac": "Analyser le Mac",
        "Empty the Trash (%@)": "Vider la Corbeille (%@)",
        "Settings…": "Réglages…",
        "Quit SaveMyMac": "Quitter SaveMyMac",

        "Startup": "Démarrage",
        "Menu bar": "Barre des menus",
        "Low space alert": "Alerte d'espace faible",
        "Appearance": "Apparence",
        "Language": "Langue",

        "Open SaveMyMac when the Mac starts": "Ouvrir SaveMyMac au démarrage du Mac",
        "Checking…": "Vérification…",
        "Hide the Dock icon": "Masquer l'icône du Dock",
        "With the icon hidden the app lives only in the menu bar. Worth it if you leave it open all the time. Applies immediately, no restart.":
            "Avec l'icône masquée, l'app ne vit que dans la barre des menus. Utile si vous la laissez ouverte en permanence. S'applique immédiatement, sans redémarrage.",
        "The app uses the modern API (system Login Items) when it can. Since this build is ad-hoc signed, registration may be refused — it then falls back to a user LaunchAgent, which works the same. The text above says which mechanism is active.":
            "L'app utilise l'API moderne (Ouverture au démarrage du système) quand elle peut. Cette version étant signée ad-hoc, l'enregistrement peut être refusé — elle bascule alors sur un LaunchAgent utilisateur, qui fonctionne pareil. Le texte ci-dessus indique le mécanisme actif.",

        "Show in the menu bar": "Afficher dans la barre des menus",
        "With this on, the app shows the chosen metric next to the clock and the panel opens with one click, without bringing up the window.":
            "Activé, l'app affiche la mesure choisie à côté de l'horloge et le panneau s'ouvre d'un clic, sans rappeler la fenêtre.",
        "What to show next to the icon": "Quoi afficher à côté de l'icône",
        "The icon turns into a warning triangle when free space drops below the threshold, whatever metric you picked.":
            "L'icône devient un triangle d'avertissement lorsque l'espace libre passe sous le seuil, quelle que soit la mesure choisie.",
        "Turned off by the emergency switch.": "Désactivée par l'interrupteur d'urgence.",

        "Free space": "Espace libre",
        "Memory pressure": "Pression mémoire",
        "CPU usage": "Utilisation du processeur",
        "Icon only": "Icône seule",

        "Notify me when space runs low": "Me prévenir quand l'espace manque",
        "Warn below": "Prévenir en dessous de",
        "%d %% free": "%d %% libres",
        "Now: %@ %% free on %@ (%@).": "Actuellement : %@ %% libres sur %@ (%@).",
        "The warning fires when crossing the threshold and only rearms after space rises 3 points above it, at most one every 6 hours. Without that, a disk hovering around the threshold would notify endlessly.":
            "L'alerte se déclenche au franchissement du seuil et ne se réarme qu'après une remontée de 3 points au-dessus, au maximum une toutes les 6 heures. Sans cela, un disque oscillant autour du seuil alerterait sans fin.",
        "Notification permission was denied. Allow it in System Settings › Notifications. The menu bar warning keeps working.":
            "L'autorisation de notification a été refusée. Activez-la dans Réglages Système › Notifications. L'avertissement de la barre des menus continue de fonctionner.",

        "The interface language. \"Same as macOS\" follows your system setting; anything else overrides it. Applies immediately.":
            "La langue de l'interface. « Comme macOS » suit le réglage du système ; tout autre choix le remplace. S'applique immédiatement.",
        "Following macOS: %@": "Suit macOS : %@",
        "Numbers, sizes and dates always follow your system region, not this setting.":
            "Les nombres, tailles et dates suivent toujours la région du système, pas ce réglage.",

        "The `enableMenuBar` key is false, or the app is in safe mode. To turn it back on, in Terminal:":
            "La clé `enableMenuBar` est à faux, ou l'app est en mode sans échec. Pour la réactiver, dans le Terminal :",
        "then reopen the app.": "puis rouvrez l'app.",

        "Moderate": "Modérée",
        "High": "Élevée",
        "Warming up": "En chauffe",
        "Hot": "Chaud",
        "Critical": "Critique",
        "Unknown": "Inconnu",

        "system Login Items": "Ouverture au démarrage du système",
        "user LaunchAgent": "LaunchAgent utilisateur",
        "disabled": "désactivé",
        "Active through the system Login Items.": "Actif via l'ouverture au démarrage du système.",
        "Registered, but waiting for your approval in System Settings › General › Login Items.":
            "Enregistré, mais en attente de votre approbation dans Réglages Système › Général › Ouverture au démarrage.",
        "Active through a LaunchAgent — the fallback path, used because the app is ad-hoc signed.":
            "Actif via un LaunchAgent — la voie de secours, utilisée car l'app est signée ad-hoc.",
        "Disabled.": "Désactivé.",

    ]
}
