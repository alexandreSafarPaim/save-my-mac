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

        // ── Painel ──────────────────────────────────────────────────────────
        "System dashboard": "Painel do sistema",
        "Up for %@": "Ligado há %@",
        "Clean now": "Limpar agora",
        "See what takes up space": "Ver o que ocupa espaço",
        "How this number is calculated": "Como esse número é calculado",
        "The score belongs to the app, not to macOS. Each factor carries a weight:":
            "O score é do próprio app, não do macOS. Cada fator entra com um peso:",
        "No scan yet. A full scan takes under a minute and deletes nothing.":
            "Nenhuma análise feita ainda. Uma varredura completa leva menos de um minuto e não apaga nada.",
        "We found %@ of reclaimable junk in %d category": "Encontramos %@ de lixo recuperável em %d categoria",
        "We found %@ of reclaimable junk in %d categories": "Encontramos %@ de lixo recuperável em %d categorias",
        "Monthly goal · %@": "Meta do mês · %@",
        "Available": "Disponível",
        "In use": "Em uso",
        "Pressure": "Pressão",
        "unused": "não usado",
        "Collecting samples…": "Coletando amostras…",
        "On macOS, free RAM is wasted RAM: the system uses the leftover as disk cache. What matters is this curve, not the percentage.":
            "No macOS, RAM livre é RAM desperdiçada: o sistema usa a sobra como cache de disco. O que importa é esta curva, não o percentual.",
        "Cores": "Núcleos",
        "System / user": "Sistema / usuário",
        "%d / %d physical": "%d / %d físicos",
        "Read sensors with admin password": "Ler sensores com senha de admin",
        "Runs powermetrics once. macOS will ask for your password.":
            "Executa powermetrics uma vez. O macOS pedirá sua senha.",
        "What's using resources": "Quem está consumindo",
        "Reading the process list…": "Lendo a lista de processos…",
        "By memory": "Por memória",
        "Quitting asks the app to exit, and it may ask about unsaved work. Force quit only with confirmation.":
            "Encerrar pede ao app para sair, e ele pode perguntar sobre trabalho não salvo. Forçar só com confirmação.",
        "Grew %@ since the app started watching. Could be a leak.":
            "Cresceu %@ desde que o app começou a observar. Pode ser vazamento.",
        "Ask it to quit": "Pedir para encerrar",
        "Force quit…": "Forçar encerramento…",
        "History": "Histórico",
        "Nothing recorded yet. Every cleanup, removed cache or uninstalled app lands here with a date and its real size.":
            "Nada registrado ainda. Cada limpeza, cache removido ou app desinstalado entra aqui com data e tamanho real.",

        // ── Nota de saúde ───────────────────────────────────────────────────
        "Your Mac is asking for help.": "Seu Mac está pedindo socorro.",
        "There's a lot of room to improve.": "Dá pra melhorar bastante.",
        "Your Mac is fine — and could be better.": "Seu Mac está bem — e dá pra ficar melhor.",
        "Your Mac is in great shape.": "Seu Mac está em ótima forma.",
        "Swap usage": "Uso de swap",
        "No swap in use": "Nenhum swap em uso",
        "Accumulated junk": "Lixo acumulado",
        "Nothing identified yet — run a scan": "Nada identificado ainda — rode uma análise",
        "%@ reclaimable": "%@ recuperáveis",
        "None found": "Nenhum encontrado",
        "%@ in identical copies": "%@ em cópias idênticas",
        "Offload links": "Links de offload",
        "All healthy": "Todos saudáveis",

        // ── Limpeza ─────────────────────────────────────────────────────────
        "Disk cleanup": "Limpeza de disco",
        "Last scan: %@": "Última análise: %@",
        "Nothing scanned yet": "Nada analisado ainda",
        "It maps caches, logs, Xcode builds, package manager caches, iPhone backups and app leftovers.":
            "Mapeia caches, logs, builds do Xcode, caches de gerenciadores de pacotes, backups de iPhone e sobras de apps.",
        "The scan is read-only.": "A varredura é somente leitura.",
        "Without that permission several folders come back empty and the numbers are underestimated.":
            "Sem essa permissão várias pastas voltam vazias e os números ficam subestimados.",
        "Empty the Trash: %d items (%@)?": "Esvaziar a Lixeira: %d itens (%@)?",
        "Empty permanently": "Esvaziar definitivamente",
        "This is permanent: there is no moving to the Trash what is already in it. It is the only action in the app with no way back.":
            "Isto é permanente: não existe mover para a Lixeira o que já está nela. É a única ação do app sem volta.",
        "\n\nScope: the Mac's Trash only. The Trash on external disks is not touched.":
            "\n\nEscopo: apenas a Lixeira do Mac. A Lixeira dos discos externos não é tocada.",
        "Open in Finder": "Abrir no Finder",
        "Check only the safe ones": "Marcar só os seguros",
        "Check safe + caution": "Marcar seguros + atenção",
        "Check everything": "Marcar tudo",
        "Uncheck everything": "Desmarcar tudo",
        "+ %d items not listed (all included in the selection)": "+ %d itens não listados (todos incluídos na seleção)",
        "Show in Finder": "Mostrar no Finder",
        "Copy path": "Copiar caminho",
        "\n\nCaution: %d items are in categories marked \"Review\" — they may be your own files.":
            "\n\nAtenção: %d itens estão em categorias marcadas como \"Revisar\" — podem ser arquivos seus.",

        // ── Risco de limpeza ────────────────────────────────────────────────
        "Caution": "Atenção",
        "Temporary files the system recreates automatically.":
            "Arquivos temporários que o sistema recria automaticamente.",
        "Can be removed, but it will be downloaded or rebuilt the next time you use the app.":
            "Pode ser removido, mas será baixado ou reconstruído na próxima vez que você usar o app.",
        "May contain your own files. Check item by item before selecting.":
            "Pode conter arquivos seus. Confira item por item antes de marcar.",
        "Move to Trash": "Mover para a Lixeira",
        "Delete permanently": "Apagar definitivamente",
        "Safer: you can restore. The space only comes back when the Trash is emptied — which you can do right here, in the card at the top.":
            "Mais seguro: você pode restaurar. O espaço só volta ao esvaziar a Lixeira — o que dá para fazer aqui mesmo, no card do topo.",
        "Frees the space immediately, with no chance of recovery.":
            "Libera o espaço imediatamente, sem possibilidade de recuperação.",

        // ── Comemoração ─────────────────────────────────────────────────────
        "The space only comes back when you empty the Trash.":
            "O espaço só volta ao esvaziar a Lixeira.",
        "Achievement unlocked": "Conquista desbloqueada",
        "Achievements unlocked": "Conquistas desbloqueadas",
        " · health %d · ": " · saúde %d · ",

        // ── Conquistas ──────────────────────────────────────────────────────
        "First cleanup": "Primeira limpeza",
        "Run your first cleanup": "Faça sua primeira limpeza",
        "Free up 50 GB in total": "Libere 50 GB no total",
        "4-week streak": "Streak de 4 semanas",
        "Clean 4 weeks in a row": "Limpe em 4 semanas seguidas",
        "First offload": "Primeiro offload",
        "Move a folder to another disk with a link": "Mova uma pasta para outro disco com link",
        "Free up 100 GB in total": "Libere 100 GB no total",
        "Zero duplicates": "Zero duplicados",
        "End up with no duplicate files": "Fique sem nenhum arquivo duplicado",
        "Reach 95 health": "Chegue a 95 de saúde",
        "Level 10": "Nível 10",
        "Reach level 10": "Alcance o nível 10",
        "App spring cleaning": "Faxina de apps",
        "Uninstall 5 apps completely": "Desinstale 5 apps completamente",
        "Zero cache": "Cache zero",
        "Clear the cache of 10 apps": "Limpe o cache de 10 apps",
        "Clean quarter": "Trimestre limpo",
        "Clean 12 weeks in a row": "Limpe em 12 semanas seguidas",
        "Keep 100 GB off the Mac's disk": "Mantenha 100 GB fora do disco do Mac",
        "uninstall": "desinstalação",

        // ── Fechando o lote do Painel ───────────────────────────────────────
        "%@ · %@ of RAM · %@": "%@ · %@ de RAM · %@",
        "live · 2 s": "ao vivo · 2 s",
        "%@ free of %@ (%@)": "%@ livres de %@ (%@)",
        "%@ · %@ in use of %@": "%@ · %@ em uso de %@",
        "%@ in swap": "%@ em swap",
        "%d with problems": "%d com problema",
        "moved to the Trash": "movidos para a Lixeira",
        "freed": "liberados",

        "%@ ready to go": "%@ prontos para sair",
        "Empty": "Esvaziar",
        "Cancel": "Cancelar",
        "Grant Full Disk Access": "Conceder Acesso Total ao Disco",
        "\n\nThe oldest item was discarded %@.": "\n\nO item mais antigo foi descartado %@.",

        // ── Migrated in batch ──
        "No apps scanned yet": "Nenhum app analisado ainda",
        "Lists installed apps with their real size, last use, and all the cache and support data each one left scattered around the Library.": "Lista os apps instalados com tamanho real, último uso e todo o cache e dados de apoio que cada um deixou espalhado pela Library.",
        "Last use comes from Spotlight. System apps are excluded.": "O último uso vem do Spotlight. Apps do sistema ficam de fora.",
        "Move everything to the Trash": "Mover tudo para a Lixeira",
        "Installed apps": "Aplicativos instalados",
        "Scan apps": "Analisar apps",
        "Filter by name…": "Filtrar por nome…",
        "used by apps and their data": "ocupado por apps e seus dados",
        "in cache alone, removable with no loss": "só em cache, removível sem perda",
        "unused for over 90 days": "sem uso há mais de 90 dias",
        "Clear cache": "Limpar cache",
        "See all support data": "Ver todos os dados de apoio",
        "Copy identifier": "Copiar identificador",
        "App bundle": "Bundle do app",
        "Other data": "Outros dados",
        "This app left nothing identifiable in the Library.": "Este app não deixou nada identificável na Library.",
        "Cache is regenerable. The rest only makes sense to remove along with the app.": "Cache é regenerável. O resto só faz sentido remover junto com o app.",
        "Walks your home folder and lists anything over 500 MB, sorted by kind. The same scan finds the duplicates.": "Percorre sua pasta pessoal e lista o que passa de 500 MB, classificado por tipo. A mesma varredura encontra os duplicados.",
        "Files that exist only in iCloud and already-offloaded content are excluded.": "Arquivos que só existem no iCloud e conteúdo já descarregado ficam de fora.",
        "Files over 500 MB": "Arquivos acima de 500 MB",
        "Scan files": "Analisar arquivos",
        "Click a band to filter the list": "Clique numa faixa para filtrar a lista",
        "See duplicates": "Ver duplicados",
        "Offload to another disk…": "Descarregar para outro disco…",
        "No duplicates found": "Nenhum duplicado encontrado",
        "The comparison is by content: it first groups by exact size, then checks 256 KB samples from the start, middle and end of each file.": "A comparação é por conteúdo: primeiro agrupa por tamanho exato, depois confere amostras de 256 KB do início, meio e fim de cada arquivo.",
        "Your files have no identical copies over 2 MB. Nothing to do here.": "Seus arquivos estão sem cópias idênticas acima de 2 MB. Nada a fazer aqui.",
        "Name and date don't matter — only content does.": "Nome e data não importam — só o conteúdo.",
        "Duplicate files": "Arquivos duplicados",
        "Compared by content — name and date don't matter. The oldest copy in each group is preserved.": "Comparação por conteúdo — nome e data não importam. A cópia mais antiga de cada grupo é preservada.",
        "reclaimable": "recuperável",
        "Remove copies": "Remover cópias",
        "use unknown": "uso desconhecido",
        "used today": "usado hoje",
        "used yesterday": "usado ontem",
        "Finding applications…": "Localizando aplicativos…",
        "Querying Spotlight…": "Consultando o Spotlight…",
        "Indexing support data…": "Indexando dados de apoio…",
        "Done": "Concluído",
        "Support data": "Dados de apoio",
        "Group container": "Container de grupo",
        "Saved state": "Estado salvo",
        "HTTP storage": "Armazenamento HTTP",
        "WebKit data": "Dados WebKit",
        "Preferences": "Preferências",
        "Launch agent": "Agente de inicialização",
        "Videos": "Vídeos",
        "Virtual machines": "Máquinas virtuais",
        "Disk images": "Imagens de disco",
        "Audio": "Áudio",
        "Databases": "Bases de dados",
        "Walking the home folder…": "Percorrendo a pasta pessoal…",
        "Sorting the large files…": "Separando os arquivos grandes…",
        "Comparing content to find duplicates…": "Comparando conteúdo para achar duplicados…",
        "Volume missing": "Volume ausente",
        "Same disk": "Mesmo disco",
        "The content is on the external volume and the link is working.": "O conteúdo está no volume externo e o link está funcionando.",
        "The destination volume is not mounted. Apps using this path will fail — and some may recreate the folder over the link, creating two diverging sets of data.": "O volume de destino não está montado. Apps que usarem este caminho vão falhar — e alguns podem recriar a pasta por cima do link, criando dois conjuntos de dados divergentes.",
        "The target no longer exists. The link has to be recreated or removed.": "O alvo não existe mais. O link precisa ser refeito ou removido.",
        "The destination is on the Mac's own disk, so this link saves no space.": "O destino está no mesmo disco do Mac, então este link não economiza espaço.",
        "Verifying the copy": "Conferindo a cópia",
        "Moving the original to quarantine": "Movendo o original para a quarentena",
        "Publishing to the destination": "Publicando no destino",
        "Creating the link": "Criando o link",
        "Testing the link": "Testando o link",
        "Good candidate": "Bom candidato",
        "Better to delete": "Melhor apagar",
        "Use the app's own setting": "Use o ajuste do app",
        "Do not link": "Não linkar",
        "Large volume, rarely accessed, no native alternative. The classic offload case.": "Volume grande, acesso raro e sem alternativa nativa. É o caso clássico de offload.",
        "It's regenerable cache and cheap to rebuild. Moving it is work with no real gain.": "É cache regenerável e barato de refazer. Mover dá trabalho sem ganho real.",
        "The app itself lets you change the folder in its preferences, which is more robust than a link.": "O próprio app permite mudar a pasta nas preferências, o que é mais robusto que um link.",
        "A system service manages this folder and does not handle symlinks well.": "Um serviço do sistema gerencia esta pasta e não lida bem com links simbólicos.",
        "Nothing checked yet": "Nada verificado ainda",
        "No links and no candidates": "Nenhum link e nenhum candidato",
        "Here you move a heavy folder to an external disk and leave a symlink in its place. macOS keeps finding everything; the space comes back to the SSD.": "Aqui você move uma pasta pesada para um disco externo e deixa um link simbólico no lugar. O macOS continua achando tudo; o espaço volta para o SSD.",
        "The check is read-only.": "A verificação é somente leitura.",
        "Move and create the link": "Mover e criar o link",
        "Symlink offload": "Offload por link simbólico",
        "Offload heavy folders": "Descarregar pastas pesadas",
        "Check links": "Verificar links",
        "Do not disconnect the external disk right now.": "Não desconecte o disco externo agora.",
        "Offload destination": "Destino do offload",
        "No destination chosen. Create a dedicated folder on the external disk — for example, a mac-offload folder at the root.": "Nenhum destino escolhido. Crie uma pasta dedicada no disco externo — por exemplo, uma pasta mac-offload na raiz.",
        "Set destination": "Configurar destino",
        "off the Mac's disk": "fora do disco do Mac",
        "active links": "links ativos",
        "with problems": "com problema",
        "in quarantine": "em quarentena",
        "orphans at the destination": "órfãos no destino",
        "Offload candidates": "Candidatos a offload",
        "Not everything large should become a link. The verdict on each row says why.": "Nem tudo que é grande deve virar link. O veredito de cada linha diz o porquê.",
        "Move and link": "Mover e linkar",
        "Choose the destination folder first": "Escolha primeiro a pasta de destino",
        "NOT MOUNTED": "NÃO MONTADO",
        "Show the link in Finder": "Mostrar o link no Finder",
        "Show the target in Finder": "Mostrar o destino no Finder",
        "Copy command to recreate the link": "Copiar comando para refazer o link",
        "Release everything": "Liberar tudo",
        "The originals are kept until you confirm everything works. **The space only comes back when you release them.** While they are here, each migration can be undone with one click.": "Os originais ficam guardados até você conferir que tudo funciona. **O espaço só volta ao liberar.** Enquanto estiverem aqui, cada migração pode ser revertida com um clique.",
        "The journal records each step before it happens, so nothing was lost. Check the paths below before trying again.": "O journal registra cada etapa antes dela acontecer, então nada foi perdido. Confira os caminhos abaixo antes de tentar de novo.",
        "Orphan data at the destination": "Dados órfãos no destino",
        "Folders inside your offload area that **no link points to**. Usually leftovers from a removed link, taking up space on the external disk for nothing — but check before deleting.": "Pastas dentro da sua área de offload que **nenhum link aponta**. Costuma ser sobra de um link removido, ocupando espaço no externo sem servir para nada — mas confira antes de apagar.",
        "Worth knowing": "O que vale saber",
        "The destination disk has to support symlinks.": "O disco de destino precisa aceitar link simbólico.",
        "exFAT and FAT do not. The app checks this before touching any file and refuses the destination.": "exFAT e FAT não aceitam. O app checa isso antes de tocar em qualquer arquivo e recusa o destino.",
        "A disconnected volume is the real risk.": "Volume desconectado é o risco real.",
        "Some apps and installers recreate the folder over the link when the target is missing, and then two sets of data start diverging silently.": "Alguns apps e instaladores recriam a pasta por cima do link quando o destino não existe, e aí passam a existir dois conjuntos de dados divergindo em silêncio.",
        "Time Machine on the internal disk backs up the link, not the content.": "O Time Machine do disco interno guarda o link, não o conteúdo.",
        "Offloaded folders need their own backup.": "As pastas descarregadas precisam de backup próprio.",
        "The Cleanup tab ignores everything on the far side of a link.": "A aba Limpeza ignora tudo que está do outro lado de um link.",
        "Deleting on the external disk would not give space back to the Mac, so those paths are left out of the list on purpose.": "Apagar no disco externo não devolveria espaço ao Mac, então esses caminhos ficam fora da lista de propósito.",

        "50 GB freed": "50 GB liberados",
        "100 GB freed": "100 GB liberados",
        "100 GB offloaded": "100 GB descarregados",

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

        // ── Panel ───────────────────────────────────────────────────────────
        "System dashboard": "Panel del sistema",
        "Up for %@": "Encendido hace %@",
        "Clean now": "Limpiar ahora",
        "See what takes up space": "Ver qué ocupa espacio",
        "How this number is calculated": "Cómo se calcula este número",
        "The score belongs to the app, not to macOS. Each factor carries a weight:":
            "La puntuación es de la propia app, no de macOS. Cada factor entra con un peso:",
        "No scan yet. A full scan takes under a minute and deletes nothing.":
            "Aún no hay análisis. Un escaneo completo tarda menos de un minuto y no borra nada.",
        "We found %@ of reclaimable junk in %d category": "Encontramos %@ de basura recuperable en %d categoría",
        "We found %@ of reclaimable junk in %d categories": "Encontramos %@ de basura recuperable en %d categorías",
        "Monthly goal · %@": "Meta del mes · %@",
        "Available": "Disponible",
        "In use": "En uso",
        "Pressure": "Presión",
        "unused": "sin usar",
        "Collecting samples…": "Recogiendo muestras…",
        "On macOS, free RAM is wasted RAM: the system uses the leftover as disk cache. What matters is this curve, not the percentage.":
            "En macOS, la RAM libre es RAM desperdiciada: el sistema usa el resto como caché de disco. Lo que importa es esta curva, no el porcentaje.",
        "Cores": "Núcleos",
        "System / user": "Sistema / usuario",
        "%d / %d physical": "%d / %d físicos",
        "Read sensors with admin password": "Leer sensores con contraseña de administrador",
        "Runs powermetrics once. macOS will ask for your password.":
            "Ejecuta powermetrics una vez. macOS pedirá tu contraseña.",
        "What's using resources": "Quién está consumiendo",
        "Reading the process list…": "Leyendo la lista de procesos…",
        "By memory": "Por memoria",
        "Quitting asks the app to exit, and it may ask about unsaved work. Force quit only with confirmation.":
            "Salir pide a la app que se cierre, y puede preguntar por trabajo sin guardar. Forzar solo con confirmación.",
        "Grew %@ since the app started watching. Could be a leak.":
            "Creció %@ desde que la app empezó a observar. Podría ser una fuga.",
        "Ask it to quit": "Pedir que se cierre",
        "Force quit…": "Forzar la salida…",
        "History": "Historial",
        "Nothing recorded yet. Every cleanup, removed cache or uninstalled app lands here with a date and its real size.":
            "Aún no hay nada registrado. Cada limpieza, caché eliminada o app desinstalada aparece aquí con fecha y tamaño real.",
        "%@ · %@ of RAM · %@": "%@ · %@ de RAM · %@",
        "live · 2 s": "en vivo · 2 s",

        // ── Puntuación de salud ─────────────────────────────────────────────
        "Your Mac is asking for help.": "Tu Mac está pidiendo auxilio.",
        "There's a lot of room to improve.": "Hay bastante que mejorar.",
        "Your Mac is fine — and could be better.": "Tu Mac está bien — y puede estar mejor.",
        "Your Mac is in great shape.": "Tu Mac está en excelente forma.",
        "Swap usage": "Uso de swap",
        "No swap in use": "Sin swap en uso",
        "Accumulated junk": "Basura acumulada",
        "Nothing identified yet — run a scan": "Nada identificado aún — ejecuta un análisis",
        "%@ reclaimable": "%@ recuperables",
        "None found": "Ninguno encontrado",
        "%@ in identical copies": "%@ en copias idénticas",
        "Offload links": "Enlaces de descarga",
        "All healthy": "Todos sanos",
        "%@ free of %@ (%@)": "%@ libres de %@ (%@)",
        "%@ · %@ in use of %@": "%@ · %@ en uso de %@",
        "%@ in swap": "%@ en swap",
        "%d with problems": "%d con problemas",

        // ── Limpieza ────────────────────────────────────────────────────────
        "Disk cleanup": "Limpieza de disco",
        "Last scan: %@": "Último análisis: %@",
        "Nothing scanned yet": "Nada analizado aún",
        "It maps caches, logs, Xcode builds, package manager caches, iPhone backups and app leftovers.":
            "Mapea cachés, registros, compilaciones de Xcode, cachés de gestores de paquetes, copias de iPhone y restos de apps.",
        "The scan is read-only.": "El análisis es de solo lectura.",
        "Without that permission several folders come back empty and the numbers are underestimated.":
            "Sin ese permiso varias carpetas vuelven vacías y los números quedan subestimados.",
        "Empty the Trash: %d items (%@)?": "¿Vaciar la Papelera: %d ítems (%@)?",
        "Empty permanently": "Vaciar definitivamente",
        "This is permanent: there is no moving to the Trash what is already in it. It is the only action in the app with no way back.":
            "Esto es permanente: no se puede mover a la Papelera lo que ya está en ella. Es la única acción de la app sin vuelta atrás.",
        "\n\nScope: the Mac's Trash only. The Trash on external disks is not touched.":
            "\n\nAlcance: solo la Papelera del Mac. La Papelera de los discos externos no se toca.",
        "Open in Finder": "Abrir en el Finder",
        "Check only the safe ones": "Marcar solo los seguros",
        "Check safe + caution": "Marcar seguros + atención",
        "Check everything": "Marcar todo",
        "Uncheck everything": "Desmarcar todo",
        "+ %d items not listed (all included in the selection)": "+ %d ítems no listados (todos incluidos en la selección)",
        "Show in Finder": "Mostrar en el Finder",
        "Copy path": "Copiar ruta",
        "\n\nCaution: %d items are in categories marked \"Review\" — they may be your own files.":
            "\n\nAtención: %d ítems están en categorías marcadas como \"Revisar\" — pueden ser archivos tuyos.",

        // ── Riesgo de limpieza ──────────────────────────────────────────────
        "Caution": "Atención",
        "Temporary files the system recreates automatically.":
            "Archivos temporales que el sistema recrea automáticamente.",
        "Can be removed, but it will be downloaded or rebuilt the next time you use the app.":
            "Se puede eliminar, pero se descargará o reconstruirá la próxima vez que uses la app.",
        "May contain your own files. Check item by item before selecting.":
            "Puede contener archivos tuyos. Revisa ítem por ítem antes de marcar.",
        "Move to Trash": "Mover a la Papelera",
        "Delete permanently": "Eliminar definitivamente",
        "Safer: you can restore. The space only comes back when the Trash is emptied — which you can do right here, in the card at the top.":
            "Más seguro: puedes restaurar. El espacio solo vuelve al vaciar la Papelera — algo que puedes hacer aquí mismo, en la tarjeta de arriba.",
        "Frees the space immediately, with no chance of recovery.":
            "Libera el espacio de inmediato, sin posibilidad de recuperación.",

        // ── Celebración ─────────────────────────────────────────────────────
        "The space only comes back when you empty the Trash.":
            "El espacio solo vuelve al vaciar la Papelera.",
        "Achievement unlocked": "Logro desbloqueado",
        "Achievements unlocked": "Logros desbloqueados",
        " · health %d · ": " · salud %d · ",
        "moved to the Trash": "movidos a la Papelera",
        "freed": "liberados",

        // ── Logros ──────────────────────────────────────────────────────────
        "First cleanup": "Primera limpieza",
        "Run your first cleanup": "Haz tu primera limpieza",
        "Free up 50 GB in total": "Libera 50 GB en total",
        "4-week streak": "Racha de 4 semanas",
        "Clean 4 weeks in a row": "Limpia 4 semanas seguidas",
        "First offload": "Primera descarga",
        "Move a folder to another disk with a link": "Mueve una carpeta a otro disco con enlace",
        "Free up 100 GB in total": "Libera 100 GB en total",
        "Zero duplicates": "Cero duplicados",
        "End up with no duplicate files": "Quédate sin archivos duplicados",
        "Reach 95 health": "Llega a 95 de salud",
        "Level 10": "Nivel 10",
        "Reach level 10": "Alcanza el nivel 10",
        "App spring cleaning": "Limpieza de apps",
        "Uninstall 5 apps completely": "Desinstala 5 apps por completo",
        "Zero cache": "Caché cero",
        "Clear the cache of 10 apps": "Limpia la caché de 10 apps",
        "Clean quarter": "Trimestre limpio",
        "Clean 12 weeks in a row": "Limpia 12 semanas seguidas",
        "Keep 100 GB off the Mac's disk": "Mantén 100 GB fuera del disco del Mac",
        "uninstall": "desinstalación",

        "%@ ready to go": "%@ listos para salir",
        "Empty": "Vaciar",
        "Cancel": "Cancelar",
        "Grant Full Disk Access": "Conceder Acceso Total al Disco",
        "\n\nThe oldest item was discarded %@.": "\n\nEl ítem más antiguo se descartó %@.",

        // ── Migrated in batch ──
        "No apps scanned yet": "Ninguna app analizada aún",
        "Lists installed apps with their real size, last use, and all the cache and support data each one left scattered around the Library.": "Lista las apps instaladas con su tamaño real, último uso y toda la caché y datos de apoyo que cada una dejó repartida por la Library.",
        "Last use comes from Spotlight. System apps are excluded.": "El último uso viene de Spotlight. Las apps del sistema quedan fuera.",
        "Move everything to the Trash": "Mover todo a la Papelera",
        "Installed apps": "Aplicaciones instaladas",
        "Scan apps": "Analizar apps",
        "Filter by name…": "Filtrar por nombre…",
        "used by apps and their data": "ocupado por apps y sus datos",
        "in cache alone, removable with no loss": "solo en caché, eliminable sin pérdida",
        "unused for over 90 days": "sin usar desde hace más de 90 días",
        "Clear cache": "Limpiar caché",
        "See all support data": "Ver todos los datos de apoyo",
        "Copy identifier": "Copiar identificador",
        "App bundle": "Paquete de la app",
        "Other data": "Otros datos",
        "This app left nothing identifiable in the Library.": "Esta app no dejó nada identificable en la Library.",
        "Cache is regenerable. The rest only makes sense to remove along with the app.": "La caché es regenerable. El resto solo tiene sentido eliminarlo junto con la app.",
        "Walks your home folder and lists anything over 500 MB, sorted by kind. The same scan finds the duplicates.": "Recorre tu carpeta personal y lista lo que pasa de 500 MB, clasificado por tipo. El mismo análisis encuentra los duplicados.",
        "Files that exist only in iCloud and already-offloaded content are excluded.": "Los archivos que solo existen en iCloud y el contenido ya descargado quedan fuera.",
        "Files over 500 MB": "Archivos de más de 500 MB",
        "Scan files": "Analizar archivos",
        "Click a band to filter the list": "Haz clic en una franja para filtrar la lista",
        "See duplicates": "Ver duplicados",
        "Offload to another disk…": "Descargar a otro disco…",
        "No duplicates found": "No se encontraron duplicados",
        "The comparison is by content: it first groups by exact size, then checks 256 KB samples from the start, middle and end of each file.": "La comparación es por contenido: primero agrupa por tamaño exacto, luego comprueba muestras de 256 KB del inicio, medio y final de cada archivo.",
        "Your files have no identical copies over 2 MB. Nothing to do here.": "Tus archivos no tienen copias idénticas de más de 2 MB. Nada que hacer aquí.",
        "Name and date don't matter — only content does.": "El nombre y la fecha no importan — solo el contenido.",
        "Duplicate files": "Archivos duplicados",
        "Compared by content — name and date don't matter. The oldest copy in each group is preserved.": "Comparación por contenido — el nombre y la fecha no importan. La copia más antigua de cada grupo se conserva.",
        "reclaimable": "recuperable",
        "Remove copies": "Eliminar copias",
        "use unknown": "uso desconocido",
        "used today": "usado hoy",
        "used yesterday": "usado ayer",
        "Finding applications…": "Localizando aplicaciones…",
        "Querying Spotlight…": "Consultando Spotlight…",
        "Indexing support data…": "Indexando datos de apoyo…",
        "Done": "Listo",
        "Support data": "Datos de apoyo",
        "Group container": "Contenedor de grupo",
        "Saved state": "Estado guardado",
        "HTTP storage": "Almacenamiento HTTP",
        "WebKit data": "Datos de WebKit",
        "Preferences": "Preferencias",
        "Launch agent": "Agente de inicio",
        "Videos": "Vídeos",
        "Virtual machines": "Máquinas virtuales",
        "Disk images": "Imágenes de disco",
        "Databases": "Bases de datos",
        "Walking the home folder…": "Recorriendo la carpeta personal…",
        "Sorting the large files…": "Separando los archivos grandes…",
        "Comparing content to find duplicates…": "Comparando contenido para encontrar duplicados…",
        "Volume missing": "Volumen ausente",
        "Same disk": "Mismo disco",
        "The content is on the external volume and the link is working.": "El contenido está en el volumen externo y el enlace funciona.",
        "The destination volume is not mounted. Apps using this path will fail — and some may recreate the folder over the link, creating two diverging sets of data.": "El volumen de destino no está montado. Las apps que usen esta ruta fallarán — y algunas pueden recrear la carpeta encima del enlace, creando dos conjuntos de datos divergentes.",
        "The target no longer exists. The link has to be recreated or removed.": "El destino ya no existe. El enlace debe recrearse o eliminarse.",
        "The destination is on the Mac's own disk, so this link saves no space.": "El destino está en el mismo disco del Mac, así que este enlace no ahorra espacio.",
        "Verifying the copy": "Comprobando la copia",
        "Moving the original to quarantine": "Moviendo el original a cuarentena",
        "Publishing to the destination": "Publicando en el destino",
        "Creating the link": "Creando el enlace",
        "Testing the link": "Probando el enlace",
        "Good candidate": "Buen candidato",
        "Better to delete": "Mejor borrar",
        "Use the app's own setting": "Usa el ajuste de la app",
        "Do not link": "No enlazar",
        "Large volume, rarely accessed, no native alternative. The classic offload case.": "Volumen grande, acceso raro y sin alternativa nativa. Es el caso clásico de descarga.",
        "It's regenerable cache and cheap to rebuild. Moving it is work with no real gain.": "Es caché regenerable y barata de reconstruir. Moverla da trabajo sin ganancia real.",
        "The app itself lets you change the folder in its preferences, which is more robust than a link.": "La propia app permite cambiar la carpeta en sus preferencias, lo que es más robusto que un enlace.",
        "A system service manages this folder and does not handle symlinks well.": "Un servicio del sistema gestiona esta carpeta y no lleva bien los enlaces simbólicos.",
        "Nothing checked yet": "Nada verificado aún",
        "No links and no candidates": "Ningún enlace y ningún candidato",
        "Here you move a heavy folder to an external disk and leave a symlink in its place. macOS keeps finding everything; the space comes back to the SSD.": "Aquí mueves una carpeta pesada a un disco externo y dejas un enlace simbólico en su lugar. macOS sigue encontrando todo; el espacio vuelve al SSD.",
        "The check is read-only.": "La verificación es de solo lectura.",
        "Move and create the link": "Mover y crear el enlace",
        "Symlink offload": "Descarga por enlace simbólico",
        "Offload heavy folders": "Descargar carpetas pesadas",
        "Check links": "Verificar enlaces",
        "Do not disconnect the external disk right now.": "No desconectes el disco externo ahora.",
        "Offload destination": "Destino de la descarga",
        "No destination chosen. Create a dedicated folder on the external disk — for example, a mac-offload folder at the root.": "Ningún destino elegido. Crea una carpeta dedicada en el disco externo — por ejemplo, una carpeta mac-offload en la raíz.",
        "Set destination": "Configurar destino",
        "off the Mac's disk": "fuera del disco del Mac",
        "active links": "enlaces activos",
        "with problems": "con problemas",
        "in quarantine": "en cuarentena",
        "orphans at the destination": "huérfanos en el destino",
        "Offload candidates": "Candidatos a descarga",
        "Not everything large should become a link. The verdict on each row says why.": "No todo lo grande debe convertirse en enlace. El veredicto de cada fila dice por qué.",
        "Move and link": "Mover y enlazar",
        "Choose the destination folder first": "Elige primero la carpeta de destino",
        "NOT MOUNTED": "NO MONTADO",
        "Show the link in Finder": "Mostrar el enlace en el Finder",
        "Show the target in Finder": "Mostrar el destino en el Finder",
        "Copy command to recreate the link": "Copiar comando para recrear el enlace",
        "Release everything": "Liberar todo",
        "The originals are kept until you confirm everything works. **The space only comes back when you release them.** While they are here, each migration can be undone with one click.": "Los originales se guardan hasta que confirmes que todo funciona. **El espacio solo vuelve al liberar.** Mientras estén aquí, cada migración puede revertirse con un clic.",
        "The journal records each step before it happens, so nothing was lost. Check the paths below before trying again.": "El diario registra cada paso antes de que ocurra, así que nada se perdió. Revisa las rutas de abajo antes de intentarlo de nuevo.",
        "Orphan data at the destination": "Datos huérfanos en el destino",
        "Folders inside your offload area that **no link points to**. Usually leftovers from a removed link, taking up space on the external disk for nothing — but check before deleting.": "Carpetas dentro de tu área de descarga a las que **ningún enlace apunta**. Suelen ser restos de un enlace eliminado, ocupando espacio en el externo sin servir de nada — pero revisa antes de borrar.",
        "Worth knowing": "Lo que conviene saber",
        "The destination disk has to support symlinks.": "El disco de destino debe aceptar enlaces simbólicos.",
        "exFAT and FAT do not. The app checks this before touching any file and refuses the destination.": "exFAT y FAT no lo hacen. La app lo comprueba antes de tocar ningún archivo y rechaza el destino.",
        "A disconnected volume is the real risk.": "El volumen desconectado es el riesgo real.",
        "Some apps and installers recreate the folder over the link when the target is missing, and then two sets of data start diverging silently.": "Algunas apps e instaladores recrean la carpeta encima del enlace cuando falta el destino, y entonces dos conjuntos de datos empiezan a divergir en silencio.",
        "Time Machine on the internal disk backs up the link, not the content.": "Time Machine del disco interno guarda el enlace, no el contenido.",
        "Offloaded folders need their own backup.": "Las carpetas descargadas necesitan su propia copia de seguridad.",
        "The Cleanup tab ignores everything on the far side of a link.": "La pestaña Limpieza ignora todo lo que está al otro lado de un enlace.",
        "Deleting on the external disk would not give space back to the Mac, so those paths are left out of the list on purpose.": "Borrar en el disco externo no devolvería espacio al Mac, así que esas rutas quedan fuera de la lista a propósito.",

        "50 GB freed": "50 GB liberados",
        "100 GB freed": "100 GB liberados",
        "100 GB offloaded": "100 GB descargados",

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

        // ── Tableau de bord ─────────────────────────────────────────────────
        "System dashboard": "Tableau de bord système",
        "Up for %@": "Allumé depuis %@",
        "Clean now": "Nettoyer",
        "See what takes up space": "Voir ce qui prend de la place",
        "How this number is calculated": "Comment ce chiffre est calculé",
        "The score belongs to the app, not to macOS. Each factor carries a weight:":
            "Le score vient de l'app, pas de macOS. Chaque facteur a un poids :",
        "No scan yet. A full scan takes under a minute and deletes nothing.":
            "Aucune analyse pour l'instant. Un scan complet prend moins d'une minute et ne supprime rien.",
        "We found %@ of reclaimable junk in %d category": "Nous avons trouvé %@ à récupérer dans %d catégorie",
        "We found %@ of reclaimable junk in %d categories": "Nous avons trouvé %@ à récupérer dans %d catégories",
        "Monthly goal · %@": "Objectif du mois · %@",
        "Available": "Disponible",
        "In use": "Utilisée",
        "Pressure": "Pression",
        "unused": "non utilisé",
        "Collecting samples…": "Collecte d'échantillons…",
        "On macOS, free RAM is wasted RAM: the system uses the leftover as disk cache. What matters is this curve, not the percentage.":
            "Sur macOS, la RAM libre est de la RAM gaspillée : le système utilise le reste comme cache disque. Ce qui compte, c'est cette courbe, pas le pourcentage.",
        "Cores": "Cœurs",
        "System / user": "Système / utilisateur",
        "%d / %d physical": "%d / %d physiques",
        "Read sensors with admin password": "Lire les capteurs avec le mot de passe admin",
        "Runs powermetrics once. macOS will ask for your password.":
            "Exécute powermetrics une fois. macOS demandera votre mot de passe.",
        "What's using resources": "Qui consomme",
        "Reading the process list…": "Lecture de la liste des processus…",
        "By memory": "Par mémoire",
        "Quitting asks the app to exit, and it may ask about unsaved work. Force quit only with confirmation.":
            "Quitter demande à l'app de se fermer, et elle peut poser une question sur le travail non enregistré. Forcer uniquement après confirmation.",
        "Grew %@ since the app started watching. Could be a leak.":
            "A grossi de %@ depuis le début de l'observation. Possible fuite mémoire.",
        "Ask it to quit": "Demander à quitter",
        "Force quit…": "Forcer à quitter…",
        "History": "Historique",
        "Nothing recorded yet. Every cleanup, removed cache or uninstalled app lands here with a date and its real size.":
            "Rien d'enregistré pour l'instant. Chaque nettoyage, cache supprimé ou app désinstallée apparaît ici avec sa date et sa taille réelle.",
        "%@ · %@ of RAM · %@": "%@ · %@ de RAM · %@",
        "live · 2 s": "en direct · 2 s",

        // ── Score de santé ──────────────────────────────────────────────────
        "Your Mac is asking for help.": "Votre Mac appelle au secours.",
        "There's a lot of room to improve.": "Il y a de quoi améliorer.",
        "Your Mac is fine — and could be better.": "Votre Mac va bien — et peut aller mieux.",
        "Your Mac is in great shape.": "Votre Mac est en pleine forme.",
        "Swap usage": "Utilisation du swap",
        "No swap in use": "Aucun swap utilisé",
        "Accumulated junk": "Déchets accumulés",
        "Nothing identified yet — run a scan": "Rien d'identifié — lancez une analyse",
        "%@ reclaimable": "%@ récupérables",
        "None found": "Aucun trouvé",
        "%@ in identical copies": "%@ en copies identiques",
        "Offload links": "Liens de déchargement",
        "All healthy": "Tous sains",
        "%@ free of %@ (%@)": "%@ libres sur %@ (%@)",
        "%@ · %@ in use of %@": "%@ · %@ utilisés sur %@",
        "%@ in swap": "%@ en swap",
        "%d with problems": "%d en défaut",

        // ── Nettoyage ───────────────────────────────────────────────────────
        "Disk cleanup": "Nettoyage du disque",
        "Last scan: %@": "Dernière analyse : %@",
        "Nothing scanned yet": "Rien d'analysé",
        "It maps caches, logs, Xcode builds, package manager caches, iPhone backups and app leftovers.":
            "Il cartographie les caches, journaux, compilations Xcode, caches de gestionnaires de paquets, sauvegardes iPhone et restes d'apps.",
        "The scan is read-only.": "L'analyse est en lecture seule.",
        "Without that permission several folders come back empty and the numbers are underestimated.":
            "Sans cette autorisation, plusieurs dossiers reviennent vides et les chiffres sont sous-estimés.",
        "Empty the Trash: %d items (%@)?": "Vider la Corbeille : %d éléments (%@) ?",
        "Empty permanently": "Vider définitivement",
        "This is permanent: there is no moving to the Trash what is already in it. It is the only action in the app with no way back.":
            "C'est définitif : on ne met pas à la Corbeille ce qui y est déjà. C'est la seule action de l'app sans retour possible.",
        "\n\nScope: the Mac's Trash only. The Trash on external disks is not touched.":
            "\n\nPérimètre : uniquement la Corbeille du Mac. Celle des disques externes n'est pas touchée.",
        "Open in Finder": "Ouvrir dans le Finder",
        "Check only the safe ones": "Cocher seulement les sûrs",
        "Check safe + caution": "Cocher sûrs + prudence",
        "Check everything": "Tout cocher",
        "Uncheck everything": "Tout décocher",
        "+ %d items not listed (all included in the selection)": "+ %d éléments non listés (tous inclus dans la sélection)",
        "Show in Finder": "Afficher dans le Finder",
        "Copy path": "Copier le chemin",
        "\n\nCaution: %d items are in categories marked \"Review\" — they may be your own files.":
            "\n\nPrudence : %d éléments sont dans des catégories marquées « À revoir » — ce peuvent être vos fichiers.",

        // ── Risque de nettoyage ─────────────────────────────────────────────
        "Caution": "Prudence",
        "Temporary files the system recreates automatically.":
            "Fichiers temporaires que le système recrée automatiquement.",
        "Can be removed, but it will be downloaded or rebuilt the next time you use the app.":
            "Peut être supprimé, mais sera retéléchargé ou reconstruit à la prochaine utilisation de l'app.",
        "May contain your own files. Check item by item before selecting.":
            "Peut contenir vos propres fichiers. Vérifiez élément par élément avant de cocher.",
        "Move to Trash": "Mettre à la Corbeille",
        "Delete permanently": "Supprimer définitivement",
        "Safer: you can restore. The space only comes back when the Trash is emptied — which you can do right here, in the card at the top.":
            "Plus sûr : vous pouvez restaurer. L'espace ne revient qu'au vidage de la Corbeille — ce que vous pouvez faire ici même, dans la carte du haut.",
        "Frees the space immediately, with no chance of recovery.":
            "Libère l'espace immédiatement, sans possibilité de récupération.",

        // ── Célébration ─────────────────────────────────────────────────────
        "The space only comes back when you empty the Trash.":
            "L'espace ne revient qu'au vidage de la Corbeille.",
        "Achievement unlocked": "Succès débloqué",
        "Achievements unlocked": "Succès débloqués",
        " · health %d · ": " · santé %d · ",
        "moved to the Trash": "mis à la Corbeille",
        "freed": "libérés",

        // ── Succès ──────────────────────────────────────────────────────────
        "First cleanup": "Premier nettoyage",
        "Run your first cleanup": "Faites votre premier nettoyage",
        "Free up 50 GB in total": "Libérez 50 GB au total",
        "4-week streak": "Série de 4 semaines",
        "Clean 4 weeks in a row": "Nettoyez 4 semaines de suite",
        "First offload": "Premier déchargement",
        "Move a folder to another disk with a link": "Déplacez un dossier vers un autre disque avec un lien",
        "Free up 100 GB in total": "Libérez 100 GB au total",
        "Zero duplicates": "Zéro doublon",
        "End up with no duplicate files": "N'ayez plus aucun fichier en doublon",
        "Reach 95 health": "Atteignez 95 de santé",
        "Level 10": "Niveau 10",
        "Reach level 10": "Atteignez le niveau 10",
        "App spring cleaning": "Grand ménage des apps",
        "Uninstall 5 apps completely": "Désinstallez 5 apps complètement",
        "Zero cache": "Cache zéro",
        "Clear the cache of 10 apps": "Videz le cache de 10 apps",
        "Clean quarter": "Trimestre propre",
        "Clean 12 weeks in a row": "Nettoyez 12 semaines de suite",
        "Keep 100 GB off the Mac's disk": "Gardez 100 GB hors du disque du Mac",
        "uninstall": "désinstallation",

        "%@ ready to go": "%@ prêts à partir",
        "Empty": "Vider",
        "Cancel": "Annuler",
        "Grant Full Disk Access": "Accorder l'accès complet au disque",
        "\n\nThe oldest item was discarded %@.": "\n\nL'élément le plus ancien a été jeté %@.",

        // ── Migrated in batch ──
        "No apps scanned yet": "Aucune app analysée",
        "Lists installed apps with their real size, last use, and all the cache and support data each one left scattered around the Library.": "Liste les apps installées avec leur taille réelle, leur dernière utilisation et tout le cache et les données de support que chacune a laissés dans la Library.",
        "Last use comes from Spotlight. System apps are excluded.": "La dernière utilisation vient de Spotlight. Les apps système sont exclues.",
        "Move everything to the Trash": "Tout mettre à la Corbeille",
        "Installed apps": "Applications installées",
        "Scan apps": "Analyser les apps",
        "Filter by name…": "Filtrer par nom…",
        "used by apps and their data": "occupé par les apps et leurs données",
        "in cache alone, removable with no loss": "en cache seulement, supprimable sans perte",
        "unused for over 90 days": "inutilisées depuis plus de 90 jours",
        "Clear cache": "Vider le cache",
        "See all support data": "Voir toutes les données de support",
        "Copy identifier": "Copier l'identifiant",
        "App bundle": "Paquet de l'app",
        "Other data": "Autres données",
        "This app left nothing identifiable in the Library.": "Cette app n'a rien laissé d'identifiable dans la Library.",
        "Cache is regenerable. The rest only makes sense to remove along with the app.": "Le cache est régénérable. Le reste n'a de sens à supprimer qu'avec l'app.",
        "Walks your home folder and lists anything over 500 MB, sorted by kind. The same scan finds the duplicates.": "Parcourt votre dossier personnel et liste ce qui dépasse 500 MB, classé par type. La même analyse trouve les doublons.",
        "Files that exist only in iCloud and already-offloaded content are excluded.": "Les fichiers qui n'existent que dans iCloud et le contenu déjà déchargé sont exclus.",
        "Files over 500 MB": "Fichiers de plus de 500 MB",
        "Scan files": "Analyser les fichiers",
        "Click a band to filter the list": "Cliquez sur une bande pour filtrer la liste",
        "See duplicates": "Voir les doublons",
        "Offload to another disk…": "Décharger vers un autre disque…",
        "No duplicates found": "Aucun doublon trouvé",
        "The comparison is by content: it first groups by exact size, then checks 256 KB samples from the start, middle and end of each file.": "La comparaison porte sur le contenu : elle groupe d'abord par taille exacte, puis vérifie des échantillons de 256 KB au début, au milieu et à la fin de chaque fichier.",
        "Your files have no identical copies over 2 MB. Nothing to do here.": "Vos fichiers n'ont aucune copie identique au-delà de 2 MB. Rien à faire ici.",
        "Name and date don't matter — only content does.": "Le nom et la date n'importent pas — seul le contenu compte.",
        "Duplicate files": "Fichiers en doublon",
        "Compared by content — name and date don't matter. The oldest copy in each group is preserved.": "Comparaison par contenu — le nom et la date n'importent pas. La copie la plus ancienne de chaque groupe est conservée.",
        "reclaimable": "récupérable",
        "Remove copies": "Supprimer les copies",
        "use unknown": "usage inconnu",
        "used today": "utilisée aujourd'hui",
        "used yesterday": "utilisée hier",
        "Finding applications…": "Recherche des applications…",
        "Querying Spotlight…": "Interrogation de Spotlight…",
        "Indexing support data…": "Indexation des données de support…",
        "Done": "Terminé",
        "Support data": "Données de support",
        "Group container": "Conteneur de groupe",
        "Saved state": "État enregistré",
        "HTTP storage": "Stockage HTTP",
        "WebKit data": "Données WebKit",
        "Preferences": "Préférences",
        "Launch agent": "Agent de lancement",
        "Videos": "Vidéos",
        "Virtual machines": "Machines virtuelles",
        "Disk images": "Images disque",
        "Databases": "Bases de données",
        "Walking the home folder…": "Parcours du dossier personnel…",
        "Sorting the large files…": "Tri des gros fichiers…",
        "Comparing content to find duplicates…": "Comparaison du contenu pour trouver les doublons…",
        "Volume missing": "Volume absent",
        "Same disk": "Même disque",
        "The content is on the external volume and the link is working.": "Le contenu est sur le volume externe et le lien fonctionne.",
        "The destination volume is not mounted. Apps using this path will fail — and some may recreate the folder over the link, creating two diverging sets of data.": "Le volume de destination n'est pas monté. Les apps utilisant ce chemin échoueront — et certaines peuvent recréer le dossier par-dessus le lien, créant deux jeux de données divergents.",
        "The target no longer exists. The link has to be recreated or removed.": "La cible n'existe plus. Le lien doit être recréé ou supprimé.",
        "The destination is on the Mac's own disk, so this link saves no space.": "La destination est sur le disque du Mac, donc ce lien ne fait gagner aucune place.",
        "Verifying the copy": "Vérification de la copie",
        "Moving the original to quarantine": "Déplacement de l'original en quarantaine",
        "Publishing to the destination": "Publication vers la destination",
        "Creating the link": "Création du lien",
        "Testing the link": "Test du lien",
        "Good candidate": "Bon candidat",
        "Better to delete": "Mieux vaut supprimer",
        "Use the app's own setting": "Utilisez le réglage de l'app",
        "Do not link": "Ne pas lier",
        "Large volume, rarely accessed, no native alternative. The classic offload case.": "Gros volume, accès rare, aucune alternative native. Le cas classique de déchargement.",
        "It's regenerable cache and cheap to rebuild. Moving it is work with no real gain.": "C'est du cache régénérable et peu coûteux à reconstruire. Le déplacer donne du travail sans gain réel.",
        "The app itself lets you change the folder in its preferences, which is more robust than a link.": "L'app elle-même permet de changer le dossier dans ses préférences, ce qui est plus robuste qu'un lien.",
        "A system service manages this folder and does not handle symlinks well.": "Un service système gère ce dossier et gère mal les liens symboliques.",
        "Nothing checked yet": "Rien de vérifié",
        "No links and no candidates": "Aucun lien et aucun candidat",
        "Here you move a heavy folder to an external disk and leave a symlink in its place. macOS keeps finding everything; the space comes back to the SSD.": "Ici vous déplacez un dossier volumineux vers un disque externe et laissez un lien symbolique à sa place. macOS continue de tout trouver ; la place revient au SSD.",
        "The check is read-only.": "La vérification est en lecture seule.",
        "Move and create the link": "Déplacer et créer le lien",
        "Symlink offload": "Déchargement par lien symbolique",
        "Offload heavy folders": "Décharger les dossiers volumineux",
        "Check links": "Vérifier les liens",
        "Do not disconnect the external disk right now.": "Ne débranchez pas le disque externe maintenant.",
        "Offload destination": "Destination du déchargement",
        "No destination chosen. Create a dedicated folder on the external disk — for example, a mac-offload folder at the root.": "Aucune destination choisie. Créez un dossier dédié sur le disque externe — par exemple un dossier mac-offload à la racine.",
        "Set destination": "Configurer la destination",
        "off the Mac's disk": "hors du disque du Mac",
        "active links": "liens actifs",
        "with problems": "en défaut",
        "in quarantine": "en quarantaine",
        "orphans at the destination": "orphelins à la destination",
        "Offload candidates": "Candidats au déchargement",
        "Not everything large should become a link. The verdict on each row says why.": "Tout ce qui est volumineux ne doit pas devenir un lien. Le verdict de chaque ligne explique pourquoi.",
        "Move and link": "Déplacer et lier",
        "Choose the destination folder first": "Choisissez d'abord le dossier de destination",
        "NOT MOUNTED": "NON MONTÉ",
        "Show the link in Finder": "Afficher le lien dans le Finder",
        "Show the target in Finder": "Afficher la cible dans le Finder",
        "Copy command to recreate the link": "Copier la commande pour recréer le lien",
        "Release everything": "Tout libérer",
        "The originals are kept until you confirm everything works. **The space only comes back when you release them.** While they are here, each migration can be undone with one click.": "Les originaux sont conservés jusqu'à ce que vous confirmiez que tout fonctionne. **La place ne revient qu'à la libération.** Tant qu'ils sont là, chaque migration peut être annulée d'un clic.",
        "The journal records each step before it happens, so nothing was lost. Check the paths below before trying again.": "Le journal enregistre chaque étape avant qu'elle n'arrive, donc rien n'a été perdu. Vérifiez les chemins ci-dessous avant de réessayer.",
        "Orphan data at the destination": "Données orphelines à la destination",
        "Folders inside your offload area that **no link points to**. Usually leftovers from a removed link, taking up space on the external disk for nothing — but check before deleting.": "Dossiers dans votre zone de déchargement vers lesquels **aucun lien ne pointe**. Souvent des restes d'un lien supprimé, occupant de la place sur l'externe pour rien — mais vérifiez avant de supprimer.",
        "Worth knowing": "Bon à savoir",
        "The destination disk has to support symlinks.": "Le disque de destination doit accepter les liens symboliques.",
        "exFAT and FAT do not. The app checks this before touching any file and refuses the destination.": "exFAT et FAT ne les acceptent pas. L'app le vérifie avant de toucher un fichier et refuse la destination.",
        "A disconnected volume is the real risk.": "Un volume débranché est le vrai risque.",
        "Some apps and installers recreate the folder over the link when the target is missing, and then two sets of data start diverging silently.": "Certaines apps et installeurs recréent le dossier par-dessus le lien quand la cible manque, et deux jeux de données commencent alors à diverger en silence.",
        "Time Machine on the internal disk backs up the link, not the content.": "Time Machine du disque interne sauvegarde le lien, pas le contenu.",
        "Offloaded folders need their own backup.": "Les dossiers déchargés ont besoin de leur propre sauvegarde.",
        "The Cleanup tab ignores everything on the far side of a link.": "L'onglet Nettoyage ignore tout ce qui se trouve de l'autre côté d'un lien.",
        "Deleting on the external disk would not give space back to the Mac, so those paths are left out of the list on purpose.": "Supprimer sur le disque externe ne rendrait pas de place au Mac, donc ces chemins sont volontairement exclus de la liste.",

        "50 GB freed": "50 GB libérés",
        "100 GB freed": "100 GB libérés",
        "100 GB offloaded": "100 GB déchargés",

    ]
}
