#!/usr/bin/env python3
"""One-shot helper used to migrate hardcoded Portuguese literals to L() calls.

Kept in the repo because the same job will come up again for any language added
later, and because it documents how the migration was done rather than leaving
a 3000-line diff with no explanation.

It only touches literals with no string interpolation. Interpolated strings need
a format string with `%@`/`%d` placeholders and argument reordering, which is a
judgement call per string, not a substitution.

Usage:
    python3 tools/i18n-batch.py            # report only
    python3 tools/i18n-batch.py --apply    # rewrite sources and append tables
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
TABLE = SOURCES / "Support" / "Strings.swift"

# pt literal -> (english key, es, fr)
MAP = {
    # ── Apps ────────────────────────────────────────────────────────────────
    "Nenhum app analisado ainda": ("No apps scanned yet", "Ninguna app analizada aún", "Aucune app analysée"),
    "Lista os apps instalados com tamanho real, último uso e todo o cache e dados de apoio que cada um deixou espalhado pela Library.": (
        "Lists installed apps with their real size, last use, and all the cache and support data each one left scattered around the Library.",
        "Lista las apps instaladas con su tamaño real, último uso y toda la caché y datos de apoyo que cada una dejó repartida por la Library.",
        "Liste les apps installées avec leur taille réelle, leur dernière utilisation et tout le cache et les données de support que chacune a laissés dans la Library."),
    "O último uso vem do Spotlight. Apps do sistema ficam de fora.": (
        "Last use comes from Spotlight. System apps are excluded.",
        "El último uso viene de Spotlight. Las apps del sistema quedan fuera.",
        "La dernière utilisation vient de Spotlight. Les apps système sont exclues."),
    "Mover tudo para a Lixeira": ("Move everything to the Trash", "Mover todo a la Papelera", "Tout mettre à la Corbeille"),
    "Aplicativos instalados": ("Installed apps", "Aplicaciones instaladas", "Applications installées"),
    "Analisar apps": ("Scan apps", "Analizar apps", "Analyser les apps"),
    "Filtrar por nome…": ("Filter by name…", "Filtrar por nombre…", "Filtrer par nom…"),
    "ocupado por apps e seus dados": ("used by apps and their data", "ocupado por apps y sus datos", "occupé par les apps et leurs données"),
    "só em cache, removível sem perda": ("in cache alone, removable with no loss", "solo en caché, eliminable sin pérdida", "en cache seulement, supprimable sans perte"),
    "sem uso há mais de 90 dias": ("unused for over 90 days", "sin usar desde hace más de 90 días", "inutilisées depuis plus de 90 jours"),
    "Limpar cache": ("Clear cache", "Limpiar caché", "Vider le cache"),
    "Abrir no Finder": ("Open in Finder", "Abrir en el Finder", "Ouvrir dans le Finder"),
    "Ver todos os dados de apoio": ("See all support data", "Ver todos los datos de apoyo", "Voir toutes les données de support"),
    "Copiar identificador": ("Copy identifier", "Copiar identificador", "Copier l'identifiant"),
    "Bundle do app": ("App bundle", "Paquete de la app", "Paquet de l'app"),
    "Outros dados": ("Other data", "Otros datos", "Autres données"),
    "Este app não deixou nada identificável na Library.": (
        "This app left nothing identifiable in the Library.",
        "Esta app no dejó nada identificable en la Library.",
        "Cette app n'a rien laissé d'identifiable dans la Library."),
    "Cache é regenerável. O resto só faz sentido remover junto com o app.": (
        "Cache is regenerable. The rest only makes sense to remove along with the app.",
        "La caché es regenerable. El resto solo tiene sentido eliminarlo junto con la app.",
        "Le cache est régénérable. Le reste n'a de sens à supprimer qu'avec l'app."),

    # ── Grandes arquivos ────────────────────────────────────────────────────
    "Nada analisado ainda": ("Nothing scanned yet", "Nada analizado aún", "Rien d'analysé"),
    "Percorre sua pasta pessoal e lista o que passa de 500 MB, classificado por tipo. A mesma varredura encontra os duplicados.": (
        "Walks your home folder and lists anything over 500 MB, sorted by kind. The same scan finds the duplicates.",
        "Recorre tu carpeta personal y lista lo que pasa de 500 MB, clasificado por tipo. El mismo análisis encuentra los duplicados.",
        "Parcourt votre dossier personnel et liste ce qui dépasse 500 MB, classé par type. La même analyse trouve les doublons."),
    "Arquivos que só existem no iCloud e conteúdo já descarregado ficam de fora.": (
        "Files that exist only in iCloud and already-offloaded content are excluded.",
        "Los archivos que solo existen en iCloud y el contenido ya descargado quedan fuera.",
        "Les fichiers qui n'existent que dans iCloud et le contenu déjà déchargé sont exclus."),
    "Arquivos acima de 500 MB": ("Files over 500 MB", "Archivos de más de 500 MB", "Fichiers de plus de 500 MB"),
    "Analisar arquivos": ("Scan files", "Analizar archivos", "Analyser les fichiers"),
    "Clique numa faixa para filtrar a lista": ("Click a band to filter the list", "Haz clic en una franja para filtrar la lista", "Cliquez sur une bande pour filtrer la liste"),
    "Ver duplicados": ("See duplicates", "Ver duplicados", "Voir les doublons"),
    "Descarregar para outro disco…": ("Offload to another disk…", "Descargar a otro disco…", "Décharger vers un autre disque…"),

    # ── Duplicados ──────────────────────────────────────────────────────────
    "Nenhum duplicado encontrado": ("No duplicates found", "No se encontraron duplicados", "Aucun doublon trouvé"),
    "A comparação é por conteúdo: primeiro agrupa por tamanho exato, depois confere amostras de 256 KB do início, meio e fim de cada arquivo.": (
        "The comparison is by content: it first groups by exact size, then checks 256 KB samples from the start, middle and end of each file.",
        "La comparación es por contenido: primero agrupa por tamaño exacto, luego comprueba muestras de 256 KB del inicio, medio y final de cada archivo.",
        "La comparaison porte sur le contenu : elle groupe d'abord par taille exacte, puis vérifie des échantillons de 256 KB au début, au milieu et à la fin de chaque fichier."),
    "Seus arquivos estão sem cópias idênticas acima de 2 MB. Nada a fazer aqui.": (
        "Your files have no identical copies over 2 MB. Nothing to do here.",
        "Tus archivos no tienen copias idénticas de más de 2 MB. Nada que hacer aquí.",
        "Vos fichiers n'ont aucune copie identique au-delà de 2 MB. Rien à faire ici."),
    "Nome e data não importam — só o conteúdo.": (
        "Name and date don't matter — only content does.",
        "El nombre y la fecha no importan — solo el contenido.",
        "Le nom et la date n'importent pas — seul le contenu compte."),
    "Arquivos duplicados": ("Duplicate files", "Archivos duplicados", "Fichiers en doublon"),
    "Comparação por conteúdo — nome e data não importam. A cópia mais antiga de cada grupo é preservada.": (
        "Compared by content — name and date don't matter. The oldest copy in each group is preserved.",
        "Comparación por contenido — el nombre y la fecha no importan. La copia más antigua de cada grupo se conserva.",
        "Comparaison par contenu — le nom et la date n'importent pas. La copie la plus ancienne de chaque groupe est conservée."),
    "recuperável": ("reclaimable", "recuperable", "récupérable"),
    "Remover cópias": ("Remove copies", "Eliminar copias", "Supprimer les copies"),

    # ── Inventário de apps ──────────────────────────────────────────────────
    "uso desconhecido": ("use unknown", "uso desconocido", "usage inconnu"),
    "usado hoje": ("used today", "usado hoy", "utilisée aujourd'hui"),
    "usado ontem": ("used yesterday", "usado ayer", "utilisée hier"),
    "Localizando aplicativos…": ("Finding applications…", "Localizando aplicaciones…", "Recherche des applications…"),
    "Consultando o Spotlight…": ("Querying Spotlight…", "Consultando Spotlight…", "Interrogation de Spotlight…"),
    "Indexando dados de apoio…": ("Indexing support data…", "Indexando datos de apoyo…", "Indexation des données de support…"),
    "Concluído": ("Done", "Listo", "Terminé"),
    "Dados de apoio": ("Support data", "Datos de apoyo", "Données de support"),
    "Container de grupo": ("Group container", "Contenedor de grupo", "Conteneur de groupe"),
    "Estado salvo": ("Saved state", "Estado guardado", "État enregistré"),
    "Armazenamento HTTP": ("HTTP storage", "Almacenamiento HTTP", "Stockage HTTP"),
    "Dados WebKit": ("WebKit data", "Datos de WebKit", "Données WebKit"),
    "Preferências": ("Preferences", "Preferencias", "Préférences"),
    "Agente de inicialização": ("Launch agent", "Agente de inicio", "Agent de lancement"),

    # ── Varredura de arquivos ───────────────────────────────────────────────
    "Vídeos": ("Videos", "Vídeos", "Vidéos"),
    "Máquinas virtuais": ("Virtual machines", "Máquinas virtuales", "Machines virtuelles"),
    "Imagens de disco": ("Disk images", "Imágenes de disco", "Images disque"),
    "Áudio": ("Audio", "Audio", "Audio"),
    "Bases de dados": ("Databases", "Bases de datos", "Bases de données"),
    "Percorrendo a pasta pessoal…": ("Walking the home folder…", "Recorriendo la carpeta personal…", "Parcours du dossier personnel…"),
    "Separando os arquivos grandes…": ("Sorting the large files…", "Separando los archivos grandes…", "Tri des gros fichiers…"),
    "Comparando conteúdo para achar duplicados…": (
        "Comparing content to find duplicates…",
        "Comparando contenido para encontrar duplicados…",
        "Comparaison du contenu pour trouver les doublons…"),

    # ── Offload: modelos ────────────────────────────────────────────────────
    "Volume ausente": ("Volume missing", "Volumen ausente", "Volume absent"),
    "Mesmo disco": ("Same disk", "Mismo disco", "Même disque"),
    "O conteúdo está no volume externo e o link está funcionando.": (
        "The content is on the external volume and the link is working.",
        "El contenido está en el volumen externo y el enlace funciona.",
        "Le contenu est sur le volume externe et le lien fonctionne."),
    "O volume de destino não está montado. Apps que usarem este caminho vão falhar — e alguns podem recriar a pasta por cima do link, criando dois conjuntos de dados divergentes.": (
        "The destination volume is not mounted. Apps using this path will fail — and some may recreate the folder over the link, creating two diverging sets of data.",
        "El volumen de destino no está montado. Las apps que usen esta ruta fallarán — y algunas pueden recrear la carpeta encima del enlace, creando dos conjuntos de datos divergentes.",
        "Le volume de destination n'est pas monté. Les apps utilisant ce chemin échoueront — et certaines peuvent recréer le dossier par-dessus le lien, créant deux jeux de données divergents."),
    "O alvo não existe mais. O link precisa ser refeito ou removido.": (
        "The target no longer exists. The link has to be recreated or removed.",
        "El destino ya no existe. El enlace debe recrearse o eliminarse.",
        "La cible n'existe plus. Le lien doit être recréé ou supprimé."),
    "O destino está no mesmo disco do Mac, então este link não economiza espaço.": (
        "The destination is on the Mac's own disk, so this link saves no space.",
        "El destino está en el mismo disco del Mac, así que este enlace no ahorra espacio.",
        "La destination est sur le disque du Mac, donc ce lien ne fait gagner aucune place."),

    # ── Migração ────────────────────────────────────────────────────────────
    "Conferindo a cópia": ("Verifying the copy", "Comprobando la copia", "Vérification de la copie"),
    "Movendo o original para a quarentena": ("Moving the original to quarantine", "Moviendo el original a cuarentena", "Déplacement de l'original en quarantaine"),
    "Publicando no destino": ("Publishing to the destination", "Publicando en el destino", "Publication vers la destination"),
    "Criando o link": ("Creating the link", "Creando el enlace", "Création du lien"),
    "Testando o link": ("Testing the link", "Probando el enlace", "Test du lien"),
    "Bom candidato": ("Good candidate", "Buen candidato", "Bon candidat"),
    "Melhor apagar": ("Better to delete", "Mejor borrar", "Mieux vaut supprimer"),
    "Use o ajuste do app": ("Use the app's own setting", "Usa el ajuste de la app", "Utilisez le réglage de l'app"),
    "Não linkar": ("Do not link", "No enlazar", "Ne pas lier"),
    "Volume grande, acesso raro e sem alternativa nativa. É o caso clássico de offload.": (
        "Large volume, rarely accessed, no native alternative. The classic offload case.",
        "Volumen grande, acceso raro y sin alternativa nativa. Es el caso clásico de descarga.",
        "Gros volume, accès rare, aucune alternative native. Le cas classique de déchargement."),
    "É cache regenerável e barato de refazer. Mover dá trabalho sem ganho real.": (
        "It's regenerable cache and cheap to rebuild. Moving it is work with no real gain.",
        "Es caché regenerable y barata de reconstruir. Moverla da trabajo sin ganancia real.",
        "C'est du cache régénérable et peu coûteux à reconstruire. Le déplacer donne du travail sans gain réel."),
    "O próprio app permite mudar a pasta nas preferências, o que é mais robusto que um link.": (
        "The app itself lets you change the folder in its preferences, which is more robust than a link.",
        "La propia app permite cambiar la carpeta en sus preferencias, lo que es más robusto que un enlace.",
        "L'app elle-même permet de changer le dossier dans ses préférences, ce qui est plus robuste qu'un lien."),
    "Um serviço do sistema gerencia esta pasta e não lida bem com links simbólicos.": (
        "A system service manages this folder and does not handle symlinks well.",
        "Un servicio del sistema gestiona esta carpeta y no lleva bien los enlaces simbólicos.",
        "Un service système gère ce dossier et gère mal les liens symboliques."),

    # ── Offload: tela ───────────────────────────────────────────────────────
    "Nada verificado ainda": ("Nothing checked yet", "Nada verificado aún", "Rien de vérifié"),
    "Nenhum link e nenhum candidato": ("No links and no candidates", "Ningún enlace y ningún candidato", "Aucun lien et aucun candidat"),
    "Aqui você move uma pasta pesada para um disco externo e deixa um link simbólico no lugar. O macOS continua achando tudo; o espaço volta para o SSD.": (
        "Here you move a heavy folder to an external disk and leave a symlink in its place. macOS keeps finding everything; the space comes back to the SSD.",
        "Aquí mueves una carpeta pesada a un disco externo y dejas un enlace simbólico en su lugar. macOS sigue encontrando todo; el espacio vuelve al SSD.",
        "Ici vous déplacez un dossier volumineux vers un disque externe et laissez un lien symbolique à sa place. macOS continue de tout trouver ; la place revient au SSD."),
    "A verificação é somente leitura.": ("The check is read-only.", "La verificación es de solo lectura.", "La vérification est en lecture seule."),
    "Mover e criar o link": ("Move and create the link", "Mover y crear el enlace", "Déplacer et créer le lien"),
    "Offload por link simbólico": ("Symlink offload", "Descarga por enlace simbólico", "Déchargement par lien symbolique"),
    "Descarregar pastas pesadas": ("Offload heavy folders", "Descargar carpetas pesadas", "Décharger les dossiers volumineux"),
    "Verificar links": ("Check links", "Verificar enlaces", "Vérifier les liens"),
    "Não desconecte o disco externo agora.": ("Do not disconnect the external disk right now.", "No desconectes el disco externo ahora.", "Ne débranchez pas le disque externe maintenant."),
    "Destino do offload": ("Offload destination", "Destino de la descarga", "Destination du déchargement"),
    "Nenhum destino escolhido. Crie uma pasta dedicada no disco externo — por exemplo, uma pasta mac-offload na raiz.": (
        "No destination chosen. Create a dedicated folder on the external disk — for example, a mac-offload folder at the root.",
        "Ningún destino elegido. Crea una carpeta dedicada en el disco externo — por ejemplo, una carpeta mac-offload en la raíz.",
        "Aucune destination choisie. Créez un dossier dédié sur le disque externe — par exemple un dossier mac-offload à la racine."),
    "Configurar destino": ("Set destination", "Configurar destino", "Configurer la destination"),
    "fora do disco do Mac": ("off the Mac's disk", "fuera del disco del Mac", "hors du disque du Mac"),
    "links ativos": ("active links", "enlaces activos", "liens actifs"),
    "com problema": ("with problems", "con problemas", "en défaut"),
    "em quarentena": ("in quarantine", "en cuarentena", "en quarantaine"),
    "órfãos no destino": ("orphans at the destination", "huérfanos en el destino", "orphelins à la destination"),
    "Candidatos a offload": ("Offload candidates", "Candidatos a descarga", "Candidats au déchargement"),
    "Nem tudo que é grande deve virar link. O veredito de cada linha diz o porquê.": (
        "Not everything large should become a link. The verdict on each row says why.",
        "No todo lo grande debe convertirse en enlace. El veredicto de cada fila dice por qué.",
        "Tout ce qui est volumineux ne doit pas devenir un lien. Le verdict de chaque ligne explique pourquoi."),
    "Mover e linkar": ("Move and link", "Mover y enlazar", "Déplacer et lier"),
    "Escolha primeiro a pasta de destino": ("Choose the destination folder first", "Elige primero la carpeta de destino", "Choisissez d'abord le dossier de destination"),
    "NÃO MONTADO": ("NOT MOUNTED", "NO MONTADO", "NON MONTÉ"),
    "Mostrar o link no Finder": ("Show the link in Finder", "Mostrar el enlace en el Finder", "Afficher le lien dans le Finder"),
    "Mostrar o destino no Finder": ("Show the target in Finder", "Mostrar el destino en el Finder", "Afficher la cible dans le Finder"),
    "Copiar comando para refazer o link": ("Copy command to recreate the link", "Copiar comando para recrear el enlace", "Copier la commande pour recréer le lien"),
    "Liberar tudo": ("Release everything", "Liberar todo", "Tout libérer"),
    "Os originais ficam guardados até você conferir que tudo funciona. **O espaço só volta ao liberar.** Enquanto estiverem aqui, cada migração pode ser revertida com um clique.": (
        "The originals are kept until you confirm everything works. **The space only comes back when you release them.** While they are here, each migration can be undone with one click.",
        "Los originales se guardan hasta que confirmes que todo funciona. **El espacio solo vuelve al liberar.** Mientras estén aquí, cada migración puede revertirse con un clic.",
        "Les originaux sont conservés jusqu'à ce que vous confirmiez que tout fonctionne. **La place ne revient qu'à la libération.** Tant qu'ils sont là, chaque migration peut être annulée d'un clic."),
    "O journal registra cada etapa antes dela acontecer, então nada foi perdido. Confira os caminhos abaixo antes de tentar de novo.": (
        "The journal records each step before it happens, so nothing was lost. Check the paths below before trying again.",
        "El diario registra cada paso antes de que ocurra, así que nada se perdió. Revisa las rutas de abajo antes de intentarlo de nuevo.",
        "Le journal enregistre chaque étape avant qu'elle n'arrive, donc rien n'a été perdu. Vérifiez les chemins ci-dessous avant de réessayer."),
    "Dados órfãos no destino": ("Orphan data at the destination", "Datos huérfanos en el destino", "Données orphelines à la destination"),
    "Pastas dentro da sua área de offload que **nenhum link aponta**. Costuma ser sobra de um link removido, ocupando espaço no externo sem servir para nada — mas confira antes de apagar.": (
        "Folders inside your offload area that **no link points to**. Usually leftovers from a removed link, taking up space on the external disk for nothing — but check before deleting.",
        "Carpetas dentro de tu área de descarga a las que **ningún enlace apunta**. Suelen ser restos de un enlace eliminado, ocupando espacio en el externo sin servir de nada — pero revisa antes de borrar.",
        "Dossiers dans votre zone de déchargement vers lesquels **aucun lien ne pointe**. Souvent des restes d'un lien supprimé, occupant de la place sur l'externe pour rien — mais vérifiez avant de supprimer."),
    "O que vale saber": ("Worth knowing", "Lo que conviene saber", "Bon à savoir"),
    "O disco de destino precisa aceitar link simbólico.": (
        "The destination disk has to support symlinks.",
        "El disco de destino debe aceptar enlaces simbólicos.",
        "Le disque de destination doit accepter les liens symboliques."),
    "exFAT e FAT não aceitam. O app checa isso antes de tocar em qualquer arquivo e recusa o destino.": (
        "exFAT and FAT do not. The app checks this before touching any file and refuses the destination.",
        "exFAT y FAT no lo hacen. La app lo comprueba antes de tocar ningún archivo y rechaza el destino.",
        "exFAT et FAT ne les acceptent pas. L'app le vérifie avant de toucher un fichier et refuse la destination."),
    "Volume desconectado é o risco real.": ("A disconnected volume is the real risk.", "El volumen desconectado es el riesgo real.", "Un volume débranché est le vrai risque."),
    "Alguns apps e instaladores recriam a pasta por cima do link quando o destino não existe, e aí passam a existir dois conjuntos de dados divergindo em silêncio.": (
        "Some apps and installers recreate the folder over the link when the target is missing, and then two sets of data start diverging silently.",
        "Algunas apps e instaladores recrean la carpeta encima del enlace cuando falta el destino, y entonces dos conjuntos de datos empiezan a divergir en silencio.",
        "Certaines apps et installeurs recréent le dossier par-dessus le lien quand la cible manque, et deux jeux de données commencent alors à diverger en silence."),
    "O Time Machine do disco interno guarda o link, não o conteúdo.": (
        "Time Machine on the internal disk backs up the link, not the content.",
        "Time Machine del disco interno guarda el enlace, no el contenido.",
        "Time Machine du disque interne sauvegarde le lien, pas le contenu."),
    "As pastas descarregadas precisam de backup próprio.": (
        "Offloaded folders need their own backup.",
        "Las carpetas descargadas necesitan su propia copia de seguridad.",
        "Les dossiers déchargés ont besoin de leur propre sauvegarde."),
    "A aba Limpeza ignora tudo que está do outro lado de um link.": (
        "The Cleanup tab ignores everything on the far side of a link.",
        "La pestaña Limpieza ignora todo lo que está al otro lado de un enlace.",
        "L'onglet Nettoyage ignore tout ce qui se trouve de l'autre côté d'un lien."),
    "Apagar no disco externo não devolveria espaço ao Mac, então esses caminhos ficam fora da lista de propósito.": (
        "Deleting on the external disk would not give space back to the Mac, so those paths are left out of the list on purpose.",
        "Borrar en el disco externo no devolvería espacio al Mac, así que esas rutas quedan fuera de la lista a propósito.",
        "Supprimer sur le disque externe ne rendrait pas de place au Mac, donc ces chemins sont volontairement exclus de la liste."),

    # ── Segundo lote: mensagens de estado, erros e verdictos ────────────────
    # Estas não são moldura de tela: aparecem quando algo acontece. Ficaram para
    # depois porque errar aqui é pior — é o texto que o usuário lê no momento em
    # que uma remoção falhou ou um link quebrou.
    "Concluída": ("Done", "Lista", "Terminée"),
    "Limpeza concluída": ("Cleanup finished", "Limpieza terminada", "Nettoyage terminé"),
    "A Lixeira já estava vazia.": ("The Trash was already empty.", "La Papelera ya estaba vacía.", "La Corbeille était déjà vide."),
    "Conferindo o conteúdo…": ("Verifying content…", "Comprobando el contenido…", "Vérification du contenu…"),
    "Sem uso há 90 d": ("Unused for 90 d", "Sin usar 90 d", "Inutilisée depuis 90 j"),
    "Escolha a pasta de destino no disco externo. Sugestão: crie uma pasta dedicada, como mac-offload.": (
        "Choose the destination folder on the external disk. Suggestion: create a dedicated folder, such as mac-offload.",
        "Elige la carpeta de destino en el disco externo. Sugerencia: crea una carpeta dedicada, como mac-offload.",
        "Choisissez le dossier de destination sur le disque externe. Suggestion : créez un dossier dédié, comme mac-offload."),
    "Offload concluído": ("Offload finished", "Descarga terminada", "Déchargement terminé"),
    "Espaço devolvido": ("Space returned", "Espacio devuelto", "Place rendue"),

    # Desinstalação e remoção: recusas de segurança
    "Aplicativo do sistema — não pode ser removido": (
        "System application — cannot be removed",
        "Aplicación del sistema — no se puede eliminar",
        "Application système — suppression impossible"),
    "Sem permissão. Arraste o app para a Lixeira manualmente.": (
        "No permission. Drag the app to the Trash manually.",
        "Sin permiso. Arrastra la app a la Papelera manualmente.",
        "Pas d'autorisation. Glissez l'app dans la Corbeille manuellement."),
    "É um link simbólico — remova pelo painel de Offload": (
        "It's a symlink — remove it from the Offload panel",
        "Es un enlace simbólico — elimínalo desde el panel de Descarga",
        "C'est un lien symbolique — supprimez-le depuis le panneau Déchargement"),
    "Pasta protegida do usuário": ("Protected user folder", "Carpeta protegida del usuario", "Dossier utilisateur protégé"),
    "Caminho sensível protegido": ("Protected sensitive path", "Ruta sensible protegida", "Chemin sensible protégé"),
    "Não se remove a pasta Aplicativos": ("The Applications folder is not removable", "La carpeta Aplicaciones no se elimina", "Le dossier Applications ne se supprime pas"),
    "É um link simbólico — remover não libera espaço no Mac": (
        "It's a symlink — removing it frees no space on the Mac",
        "Es un enlace simbólico — eliminarlo no libera espacio en el Mac",
        "C'est un lien symbolique — le supprimer ne libère aucune place sur le Mac"),
    "Caminho inválido": ("Invalid path", "Ruta no válida", "Chemin non valide"),
    "Pasta de sistema do usuário protegida": ("Protected user system folder", "Carpeta de sistema del usuario protegida", "Dossier système utilisateur protégé"),

    # Lixeira
    "~/.Trash não é uma pasta real — nada foi removido": (
        "~/.Trash is not a real folder — nothing was removed",
        "~/.Trash no es una carpeta real — no se eliminó nada",
        "~/.Trash n'est pas un vrai dossier — rien n'a été supprimé"),
    "Não foi possível ler a Lixeira": ("Could not read the Trash", "No se pudo leer la Papelera", "Impossible de lire la Corbeille"),
    "Fora da Lixeira do usuário": ("Outside the user's Trash", "Fuera de la Papelera del usuario", "Hors de la Corbeille de l'utilisateur"),
    "Arquivo travado. Destrave no Finder (Obter Informações) e tente de novo.": (
        "File is locked. Unlock it in Finder (Get Info) and try again.",
        "Archivo bloqueado. Desbloquéalo en el Finder (Obtener información) e inténtalo de nuevo.",
        "Fichier verrouillé. Déverrouillez-le dans le Finder (Lire les informations) et réessayez."),
    "Sem permissão. Pode pertencer a outro usuário ou estar em uso.": (
        "No permission. It may belong to another user or be in use.",
        "Sin permiso. Puede pertenecer a otro usuario o estar en uso.",
        "Pas d'autorisation. Il peut appartenir à un autre utilisateur ou être en cours d'utilisation."),

    # Varredura de limpeza: descrições de categoria
    "Dados temporários que os apps recriam sozinhos": (
        "Temporary data the apps recreate on their own",
        "Datos temporales que las apps recrean por sí solas",
        "Données temporaires que les apps recréent d'elles-mêmes"),
    "Relatórios de travamento antigos": ("Old crash reports", "Informes de fallo antiguos", "Anciens rapports de plantage"),
    "Logs e relatórios de erro": ("Logs and error reports", "Registros e informes de error", "Journaux et rapports d'erreur"),
    "Registros de diagnóstico que não são mais consultados": (
        "Diagnostic records nobody reads anymore",
        "Registros de diagnóstico que ya nadie consulta",
        "Enregistrements de diagnostic que plus personne ne consulte"),
    "Builds intermediários; o Xcode reconstrói na próxima compilação": (
        "Intermediate builds; Xcode rebuilds them on the next compile",
        "Compilaciones intermedias; Xcode las reconstruye en la próxima compilación",
        "Compilations intermédiaires ; Xcode les reconstruit à la prochaine compilation"),
    "Arquivos de distribuição antigos": ("Old distribution archives", "Archivos de distribución antiguos", "Anciennes archives de distribution"),
    "Símbolos de versões de iOS que você provavelmente não depura mais": (
        "Symbols for iOS versions you probably no longer debug",
        "Símbolos de versiones de iOS que probablemente ya no depuras",
        "Symboles de versions d'iOS que vous ne déboguez probablement plus"),
    "Símbolos de watchOS antigos": ("Old watchOS symbols", "Símbolos de watchOS antiguos", "Anciens symboles watchOS"),
    "Cada simulador criado ocupa espaço; recriáveis pelo Xcode": (
        "Every simulator you create takes space; Xcode can recreate them",
        "Cada simulador creado ocupa espacio; Xcode puede recrearlos",
        "Chaque simulateur créé prend de la place ; Xcode peut les recréer"),
    "Cache de índice e download do Xcode": ("Xcode index and download cache", "Caché de índice y descargas de Xcode", "Cache d'index et de téléchargement Xcode"),
    "Temporários de simulador": ("Simulator temporaries", "Temporales de simulador", "Fichiers temporaires du simulateur"),
    "Índices das IDEs JetBrains": ("JetBrains IDE indexes", "Índices de los IDE de JetBrains", "Index des IDE JetBrains"),
    "Máquinas virtuais Android": ("Android virtual machines", "Máquinas virtuales de Android", "Machines virtuelles Android"),
    "Builds, símbolos e simuladores — normalmente o maior ganho num Mac de dev": (
        "Builds, symbols and simulators — usually the biggest win on a dev Mac",
        "Compilaciones, símbolos y simuladores — normalmente la mayor ganancia en un Mac de desarrollo",
        "Compilations, symboles et simulateurs — souvent le plus gros gain sur un Mac de dev"),
    "Será baixado de novo quando necessário": (
        "It will be downloaded again when needed",
        "Se descargará de nuevo cuando sea necesario",
        "Il sera retéléchargé au besoin"),
    "Projetos sem atividade há mais de 90 dias": (
        "Projects with no activity for over 90 days",
        "Proyectos sin actividad desde hace más de 90 días",
        "Projets sans activité depuis plus de 90 jours"),
    "Backup local de iPhone/iPad — confirme que você tem backup no iCloud antes de remover": (
        "Local iPhone/iPad backup — confirm you have an iCloud backup before removing",
        "Copia local de iPhone/iPad — confirma que tienes copia en iCloud antes de eliminar",
        "Sauvegarde locale d'iPhone/iPad — vérifiez d'avoir une sauvegarde iCloud avant de supprimer"),
    "Sem uso há mais de 90 dias": ("Unused for over 90 days", "Sin usar desde hace más de 90 días", "Inutilisé depuis plus de 90 jours"),
    "Imagens de instalação que já cumpriram seu papel": (
        "Installer images that already did their job",
        "Imágenes de instalación que ya cumplieron su función",
        "Images d'installation qui ont déjà fait leur travail"),
    "Metadados de visualização do Finder — recriados automaticamente": (
        "Finder view metadata — recreated automatically",
        "Metadatos de visualización del Finder — se recrean automáticamente",
        "Métadonnées d'affichage du Finder — recréées automatiquement"),
    "Poluição do Finder espalhada pelas pastas": (
        "Finder clutter scattered across folders",
        "Basura del Finder repartida por las carpetas",
        "Pollution du Finder éparpillée dans les dossiers"),

    # Memória e térmica
    "Memória de apps": ("App memory", "Memoria de apps", "Mémoire des apps"),
    "Sensor da bateria (CPU indisponível sem privilégios)": (
        "Battery sensor (CPU unavailable without privileges)",
        "Sensor de la batería (CPU no disponible sin privilegios)",
        "Capteur de la batterie (CPU indisponible sans privilèges)"),
    "Apenas estado térmico do sistema": ("System thermal state only", "Solo el estado térmico del sistema", "Uniquement l'état thermique du système"),

    # Processos
    "Processo do núcleo do sistema.": ("Core system process.", "Proceso del núcleo del sistema.", "Processus du noyau système."),
    "Este é o próprio SaveMyMac.": ("This is SaveMyMac itself.", "Este es SaveMyMac.", "C'est SaveMyMac lui-même."),
    "O /bin/ps respondeu, mas nenhuma linha pôde ser interpretada.": (
        "/bin/ps answered, but no line could be parsed.",
        "/bin/ps respondió, pero no se pudo interpretar ninguna línea.",
        "/bin/ps a répondu, mais aucune ligne n'a pu être analysée."),

    # Offload: verdictos dos candidatos
    "Símbolos de versões antigas de iOS. Enorme e consultado raramente.": (
        "Symbols for old iOS versions. Huge and rarely consulted.",
        "Símbolos de versiones antiguas de iOS. Enorme y consultado rara vez.",
        "Symboles d'anciennes versions d'iOS. Énorme et rarement consulté."),
    "Costuma ser o maior arquivo escondido do Mac e você quase nunca abre.": (
        "Usually the biggest hidden file on the Mac, and you almost never open it.",
        "Suele ser el archivo oculto más grande del Mac y casi nunca lo abres.",
        "Souvent le plus gros fichier caché du Mac, et vous ne l'ouvrez presque jamais."),
    "Imagens de sistema e ferramentas pesadas, lidas só ao compilar.": (
        "System images and heavy tools, read only when compiling.",
        "Imágenes de sistema y herramientas pesadas, leídas solo al compilar.",
        "Images système et outils lourds, lus seulement à la compilation."),
    "Jogos ocupam dezenas de GB e você joga um por vez.": (
        "Games take tens of GB and you play one at a time.",
        "Los juegos ocupan decenas de GB y juegas uno a la vez.",
        "Les jeux prennent des dizaines de GB et vous en jouez un à la fois."),
    "Filmes e vídeos": ("Movies and video", "Películas y vídeos", "Films et vidéos"),
    "Mídia bruta é o maior consumidor típico e raramente é reaberta.": (
        "Raw media is the typical biggest consumer and is rarely reopened.",
        "El material bruto es el mayor consumidor típico y rara vez se reabre.",
        "Les médias bruts sont le plus gros consommateur typique et sont rarement réouverts."),
    "Máquinas virtuais Parallels": ("Parallels virtual machines", "Máquinas virtuales de Parallels", "Machines virtuelles Parallels"),
    "Máquinas virtuais UTM": ("UTM virtual machines", "Máquinas virtuales de UTM", "Machines virtuelles UTM"),
    "Pesos de modelos ocupam muitos GB e são só leitura.": (
        "Model weights take many GB and are read-only.",
        "Los pesos de modelos ocupan muchos GB y son de solo lectura.",
        "Les poids de modèles prennent beaucoup de GB et sont en lecture seule."),
    "Build intermediário. Em disco externo o build fica mais lento, não mais rápido.": (
        "Intermediate build. On an external disk the build gets slower, not faster.",
        "Compilación intermedia. En disco externo la compilación se vuelve más lenta, no más rápida.",
        "Compilation intermédiaire. Sur un disque externe, la compilation devient plus lente, pas plus rapide."),
    "Apague pela aba Limpeza; o Xcode reconstrói.": (
        "Delete it from the Cleanup tab; Xcode rebuilds it.",
        "Bórralo desde la pestaña Limpieza; Xcode lo reconstruye.",
        "Supprimez-le depuis l'onglet Nettoyage ; Xcode le reconstruit."),
    "Regenerável e barato — mover dá trabalho sem ganho.": (
        "Regenerable and cheap — moving it is work with no gain.",
        "Regenerable y barato — moverlo da trabajo sin ganancia.",
        "Régénérable et peu coûteux — le déplacer donne du travail sans gain."),
    "Downloads já instalados. Apagar é imediato.": (
        "Downloads already installed. Deleting is immediate.",
        "Descargas ya instaladas. Borrar es inmediato.",
        "Téléchargements déjà installés. La suppression est immédiate."),
    "Pesado, porém os apps Adobe têm ajuste de cache de mídia.": (
        "Heavy, but Adobe apps have a media cache setting.",
        "Pesado, pero las apps de Adobe tienen ajuste de caché de medios.",
        "Volumineux, mais les apps Adobe ont un réglage de cache média."),
    "A Apple não suporta link aqui e há risco real de corrupção.": (
        "Apple does not support a link here and there is a real risk of corruption.",
        "Apple no admite un enlace aquí y hay riesgo real de corrupción.",
        "Apple ne prend pas en charge un lien ici et il y a un risque réel de corruption."),

    # Motor de migração
    "A pasta de destino não existe ou o volume não está montado.": (
        "The destination folder does not exist, or the volume is not mounted.",
        "La carpeta de destino no existe o el volumen no está montado.",
        "Le dossier de destination n'existe pas, ou le volume n'est pas monté."),
    "Não foi possível ler as características do volume de destino.": (
        "Could not read the destination volume's characteristics.",
        "No se pudieron leer las características del volumen de destino.",
        "Impossible de lire les caractéristiques du volume de destination."),
    "O volume de destino está somente para leitura.": (
        "The destination volume is read-only.",
        "El volumen de destino es de solo lectura.",
        "Le volume de destination est en lecture seule."),
    "Sem permissão de escrita na pasta de destino.": (
        "No write permission on the destination folder.",
        "Sin permiso de escritura en la carpeta de destino.",
        "Pas d'autorisation d'écriture sur le dossier de destination."),
    "A pasta de origem não existe.": ("The source folder does not exist.", "La carpeta de origen no existe.", "Le dossier source n'existe pas."),
    "Esta pasta já é um link simbólico.": ("This folder is already a symlink.", "Esta carpeta ya es un enlace simbólico.", "Ce dossier est déjà un lien symbolique."),
    "O conteúdo já está fora do disco do Mac.": ("The content is already off the Mac's disk.", "El contenido ya está fuera del disco del Mac.", "Le contenu est déjà hors du disque du Mac."),
    "Só é possível descarregar pastas de dentro da sua pasta pessoal.": (
        "Only folders inside your home folder can be offloaded.",
        "Solo se pueden descargar carpetas de dentro de tu carpeta personal.",
        "Seuls les dossiers situés dans votre dossier personnel peuvent être déchargés."),
    "Não descarregue uma pasta de topo inteira — escolha algo dentro dela.": (
        "Don't offload a whole top-level folder — pick something inside it.",
        "No descargues una carpeta de nivel superior completa — elige algo dentro de ella.",
        "Ne déchargez pas un dossier de premier niveau entier — choisissez quelque chose à l'intérieur."),
    "as preferências": ("its preferences", "sus preferencias", "ses préférences"),
    "A Apple não suporta link na biblioteca do Fotos. Mova a biblioteca e abra o Fotos com Option pressionado.": (
        "Apple does not support a link on the Photos library. Move the library and open Photos holding Option.",
        "Apple no admite un enlace en la biblioteca de Fotos. Mueve la biblioteca y abre Fotos con Opción pulsada.",
        "Apple ne prend pas en charge un lien sur la bibliothèque Photos. Déplacez la bibliothèque et ouvrez Photos en maintenant Option."),
    "Origem e destino são o mesmo caminho.": ("Source and destination are the same path.", "Origen y destino son la misma ruta.", "La source et la destination sont le même chemin."),
    "Cancelado durante a cópia.": ("Cancelled during the copy.", "Cancelado durante la copia.", "Annulé pendant la copie."),
    "Criando o link simbólico…": ("Creating the symlink…", "Creando el enlace simbólico…", "Création du lien symbolique…"),
    "O original não está mais na quarentena — não há como reverter.": (
        "The original is no longer in quarantine — there is no way to undo.",
        "El original ya no está en cuarentena — no hay forma de revertir.",
        "L'original n'est plus en quarantaine — impossible d'annuler."),
    "A quarentena já estava vazia.": ("Quarantine was already empty.", "La cuarentena ya estaba vacía.", "La quarantaine était déjà vide."),
    "O link ou o destino não estão íntegros. A quarentena fica onde está.": (
        "The link or the target is not intact. Quarantine stays where it is.",
        "El enlace o el destino no están íntegros. La cuarentena se queda donde está.",
        "Le lien ou la cible n'est pas intact. La quarantaine reste où elle est."),
    "o link não foi criado": ("the link was not created", "el enlace no se creó", "le lien n'a pas été créé"),
    "o link não resolve para um caminho existente": (
        "the link does not resolve to an existing path",
        "el enlace no resuelve a una ruta existente",
        "le lien ne résout pas vers un chemin existant"),

    # Varredura de offload
    "Procurando links simbólicos…": ("Looking for symlinks…", "Buscando enlaces simbólicos…", "Recherche de liens symboliques…"),
    "Procurando dados órfãos no destino…": ("Looking for orphan data at the destination…", "Buscando datos huérfanos en el destino…", "Recherche de données orphelines à la destination…"),

    # Menu do sistema e diálogo de forçar
    "Ações": ("Actions", "Acciones", "Actions"),
    "Atualizar métricas": ("Refresh metrics", "Actualizar métricas", "Actualiser les mesures"),
    "Forçar encerramento": ("Force quit", "Forzar la salida", "Forcer à quitter"),

    # Abrir no login
    "Registrado. Aprove em Ajustes do Sistema › Geral › Itens de Início para valer.": (
        "Registered. Approve it in System Settings › General › Login Items to take effect.",
        "Registrado. Apruébalo en Ajustes del Sistema › General › Ítems de inicio para que surta efecto.",
        "Enregistré. Approuvez-le dans Réglages Système › Général › Ouverture au démarrage pour qu'il prenne effet."),
    "O SaveMyMac não vai mais abrir junto com o Mac.": (
        "SaveMyMac will no longer open with the Mac.",
        "SaveMyMac ya no se abrirá junto con el Mac.",
        "SaveMyMac ne s'ouvrira plus avec le Mac."),

    # Alerta de espaço
    "Notificações precisam do app rodando como bundle (.app).": (
        "Notifications require the app to run as a bundle (.app).",
        "Las notificaciones requieren que la app se ejecute como paquete (.app).",
        "Les notifications exigent que l'app tourne comme paquet (.app)."),
}

# Literals that must stay as they are: date format patterns, shell commands,
# paths. Translating any of these produces something that does not run.
NEVER_TRANSLATE = {
    "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss",
    "Library/Application Support", "Library/Group Containers",
    "Library/Saved Application State", "Library/Application Scripts",
}


def main() -> int:
    apply = "--apply" in sys.argv
    changed_files = 0
    replaced = 0
    untouched = []

    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name == "Strings.swift":
            continue
        src = original = path.read_text(encoding="utf-8")
        for pt, (en, _es, _fr) in MAP.items():
            if pt in NEVER_TRANSLATE:
                continue
            needle = f'"{pt}"'
            if needle in src:
                escaped = en.replace('"', '\\"')
                src = src.replace(needle, f'L("{escaped}")')
                replaced += 1
        if src != original:
            changed_files += 1
            if apply:
                path.write_text(src, encoding="utf-8")

    for pt in MAP:
        if not any(
            f'"{pt}"' in p.read_text(encoding="utf-8")
            for p in SOURCES.rglob("*.swift")
        ):
            untouched.append(pt)

    print(f"{replaced} replacement(s) across {changed_files} file(s)")
    if untouched and not apply:
        print(f"\n{len(untouched)} entries in MAP no longer found in source:")
        for pt in untouched:
            print(f"  {pt[:70]}")

    if apply:
        rows = {"pt": [], "es": [], "fr": []}
        for pt, (en, es, fr) in MAP.items():
            escaped = en.replace('"', '\\"')
            for lang, text in (("pt", pt), ("es", es), ("fr", fr)):
                if text == en:
                    continue  # identity: the lookup already falls back to the key
                rows[lang].append(f'        "{escaped}": "{text}",')

        table_src = TABLE.read_text(encoding="utf-8")
        for lang in ("pt", "es", "fr"):
            block = "\n        // ── Migrated in batch ──\n" + "\n".join(rows[lang]) + "\n"
            match = re.search(
                rf"(static let {lang}: \[String: String\] = \[.*?)(\n    \])",
                table_src,
                re.S,
            )
            table_src = table_src[: match.end(1)] + block + table_src[match.end(1):]
        TABLE.write_text(table_src, encoding="utf-8")
        print("tables updated")

    return 0


if __name__ == "__main__":
    sys.exit(main())
