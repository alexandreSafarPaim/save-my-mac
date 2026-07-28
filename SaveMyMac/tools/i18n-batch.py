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
