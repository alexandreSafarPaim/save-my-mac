<img src="Resources/logo-1024.png" width="128" align="right" alt="SaveMyMac">

# SaveMyMac

🇬🇧 [Read in English](README.md)

App nativo em SwiftUI que mostra o estado real da máquina, lista o que pode ser removido **com checkbox item por item**, e descarrega pastas pesadas para um disco externo deixando um link simbólico no lugar.

Layout desenhado no Claude Design e portado para SwiftUI nativo. Seis telas, tema claro e escuro, fontes variáveis embutidas.

---

## 1. Compilar

Só precisa das Command Line Tools da Apple — não precisa abrir o Xcode:

```bash
xcode-select --install     # só se o swiftc ainda não existir
cd SaveMyMac
chmod +x build.sh
./build.sh --run
```

| Comando | O que faz |
|---|---|
| `./build.sh` | compila para a arquitetura da sua máquina |
| `./build.sh --universal` | binário universal (Apple Silicon + Intel) |
| `./build.sh --run` | compila e abre o app |
| `./build.sh --install` | **instala em `/Applications`** |
| `./build.sh --dmg` | gera um `.dmg` de instalação para distribuir |

### Instalar como um app de verdade

```bash
./build.sh --install --run
```

Isso faz o que arrastar à mão não faz:

- **Fecha a instância em execução** antes de substituir o bundle. Trocar arquivos debaixo de um app rodando deixa um processo apontando para caminhos que já não existem.
- **Remove o atributo de quarentena.** O app foi compilado aqui, não baixado — sem isso o macOS pediria confirmação a cada abertura.
- **Registra no Launch Services** (`lsregister -f`), então ele aparece no Spotlight e no Launchpad na hora, sem esperar reindexação.
- **Abre o painel de Acesso Total ao Disco** no fim, porque esse é o único passo que não pode ser automatizado.

Depois disso ele é um app normal: ⌘Space, "SaveMyMac", enter.

### Gerar um instalador para outra pessoa

```bash
python3 tools/make-dmg-background.py   # só na primeira vez
./build.sh --dmg
```

Sai um `build/SaveMyMac.dmg` com o app, um atalho para Aplicativos e o fundo com a seta indicando o arraste. O layout da janela é aplicado via Finder, o que depende da permissão de Automação — se falhar, o DMG continua funcionando, só abre sem o posicionamento.

#### O rótulo do Finder e a matemática do contraste

O Finder desenha o nome sob cada ícone por conta própria, na cor da aparência do sistema: **preto no modo claro, branco no escuro**. O fundo do DMG é uma imagem fixa, então nenhum extremo funciona:

| Fundo | Modo claro | Modo escuro |
|---|---|---|
| escuro | 1,1:1 — ilegível | 18,8:1 |
| claro | 17,9:1 | 1,2:1 — ilegível |

Dá para resolver com conta em vez de chute. Igualando as duas fórmulas de contraste da WCAG:

```
(L + 0,05) / 0,05  =  1,05 / (L + 0,05)   →   L = 0,179
```

Nessa luminância o contraste é **4,58:1 contra preto e 4,59:1 contra branco** — o melhor pior-caso possível. Em sRGB é o cinza `#757575`; na tinta da marca, `#7D6D9B`.

Daí o desenho: fundo escuro com duas **placas de meio-tom** atrás dos rótulos. O `make-dmg-background.py` mede isso a cada geração e imprime os dois contrastes, em vez de confiar no olho.

Duas tentativas descartadas: uma faixa atravessando a janela resolvia o contraste mas cortava os ícones ao meio; um pedestal grande atrás de ícone + rótulo virava um bloco pesado e tirava o ícone colorido do fundo escuro, onde ele fica melhor.

`--light` gera a variante de fundo claro, se você só usa modo claro.

**A limitação honesta:** o app é assinado **ad-hoc**, não notarizado. No seu Mac isso é irrelevante, porque compilar localmente não põe quarentena. Em **outro** Mac, o macOS vai bloquear a primeira abertura — a pessoa precisa de **Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim**, ou de `xattr -d com.apple.quarantine`. (O clique-direito → Abrir não oferece mais "Abrir" para apps não-notarizados nos macOS recentes.) Notarizar de verdade exige conta paga no Apple Developer Program e uma passada por `notarytool` — não tem como contornar isso com script.

**Permissão importante:** conceda **Acesso Total ao Disco** em Ajustes do Sistema → Privacidade e Segurança. Sem isso o app funciona, mas várias pastas retornam vazias e os números ficam subestimados. O `--install` abre o painel para você, e há um botão para isso dentro do app.

---

## 2. Sistema visual

Traduzido das variáveis CSS do design:

| Token | Escuro | Claro |
|---|---|---|
| Fundo | `#08070F` / `#0D0B18` | `#EFEDF7` / `#F7F6FC` |
| Acento | `#7C5CFF` → `#22E0FF` | `#6A3FF5` → `#0FA5C9` |
| OK / atenção / perigo | `#3BE8A0` / `#FFB020` / `#FF5A6E` | `#0FA86E` / `#C97A00` / `#E0344B` |
| Texto | `#F2F0FF` a 100 / 62 / 34 % | `#14102D` a 100 / 62 / 38 % |

**Fontes:** Space Grotesk na interface, JetBrains Mono em números e rótulos. Os `woff2` do bundle do design foram convertidos para **TTF variável** (eixo `wght` 300–700 e 400–800), renomeados para expor a família corretamente e embutidos em `Contents/Resources/Fonts`. O `ATSApplicationFontsPath` no Info.plist faz o macOS registrá-las só para este app — nada é instalado no sistema. Se o registro falhar, tudo cai para SF Pro e SF Mono sem quebrar o layout.

**Movimento:** as oito animações nomeadas do CSS (`smRise`, `smPop`, `smRing`, `smScan`, `smBar`, `smFloat`, `smPulse`, `smDash`) têm equivalente em `Theme/Motion.swift`.

### Duas divergências assumidas de propósito

**A janela falsa.** O design desenha os três botões coloridos do macOS e uma trilha centralizada no topo — isso é moldura de mockup. Reproduzir daria dois conjuntos de botões, porque a janela real já tem os dela. O app usa `.hiddenTitleBar` e põe a trilha e o botão de tema numa faixa própria, respeitando o espaço dos controles nativos.

**`backdrop-filter`.** O equivalente nativo é `.ultraThinMaterial`, que respeita o desfoque do sistema em vez de aceitar um raio arbitrário. Fica muito perto, não idêntico.

### A marca

O sparkle de 4 pontas do design (pontas nos eixos, cintura a 30 % na diagonal) dentro do quadrado com gradiente, com o anel de progresso a 78 %. Uma definição só, em `tools/make-icon.py`, gera tudo:

```bash
python3 tools/make-icon.py            # variante gradiente (padrão)
python3 tools/make-icon.py --dark     # variante escura como ícone principal
```

| Saída | Para quê |
|---|---|
| `Resources/AppIcon.iconset/` | os 10 PNGs que o `iconutil` empacota no `.icns` — o `build.sh` faz isso e só regenera quando a arte muda |
| `Resources/logo.svg` | a marca em vetor |
| `Resources/logo-1024.png` | README e divulgação |
| `Resources/logo-dark.png` | a variante alternativa |

O mesmo desenho existe em SwiftUI (`Theme/Brand.swift`) como `Sparkle` (um `Shape`) e `BrandMark`, usados na sidebar e na tela de conclusão. Nada de bitmap na interface.

Três detalhes que fazem o ícone não parecer amador:

**Arte diferente nos tamanhos pequenos.** A 16 px o anel e o sparkle se encostam e viram um borrão cinza. Abaixo de 64 px o iconset recebe uma versão sem anel, com o sparkle maior e mais gordo. Isso é o que ícone bem feito faz, e o formato iconset existe justamente para permitir.

**Squircle de verdade.** O canto do macOS é uma curva contínua, não um arco de círculo. A máscara é uma superelipse (`|x|ⁿ + |y|ⁿ = 1`, n = 6,2), porque o `rounded_rectangle` do PIL só faz canto circular. O SVG usa `rx` de 22,5 %, que é a aproximação padrão — SVG não tem canto contínuo.

**Grade da Apple.** Conteúdo de 824 px num canvas de 1024, com sombra discreta, como manda a especificação do macOS desde o Big Sur.

---

## 3. Painel

Atualiza a cada 2 segundos.

**Score de saúde 0–100.** Não existe "score de saúde" no macOS — este é um índice do próprio app, e por isso é totalmente explicável: clique em *Como esse número é calculado* e cada fator aparece com peso e motivo da nota.

| Fator | Peso |
|---|---|
| Espaço livre no disco de inicialização | 34 |
| Pressão de memória | 18 |
| Temperatura / estado térmico | 14 |
| Lixo acumulado (proporcional ao disco) | 14 |
| Uso de swap | 10 |
| Duplicados | 6 |
| Links de offload quebrados | 4 |

**Cards de métrica:** memória decomposta como no Monitor de Atividade (apps, travada, comprimida, cache) mais swap e pressão; CPU por delta de ticks com load average e contagem de processos; temperatura; armazenamento com todos os volumes. Mais o histórico real de limpezas.

### Memória: por que não existe botão de "liberar"

Este é o recurso mais vendido dos limpadores de Mac e o menos útil, então vale explicar a ausência.

**No macOS, RAM livre é RAM desperdiçada.** O kernel usa de propósito toda a memória sobrando como cache de disco. Ver "13% livre" não é problema — é o sistema funcionando. A métrica que importa é a **pressão de memória**.

As duas implementações comuns de "liberar memória":

| Truque | O que faz de verdade |
|---|---|
| `sudo purge` | descarta o cache de arquivos e páginas inativas. O número de "livre" sobe na hora e nos minutos seguintes tudo fica **mais lento**, porque o que estava em cache volta do disco. Não toca em swap. É ferramenta de benchmark, para medir com cache frio. |
| alocar um bloco gigante e liberar | força o kernel a comprimir e mandar para swap o conjunto de trabalho dos apps em uso. Piora ativamente. |

Então o app faz outra coisa, que ataca a causa:

**Curva de pressão dos últimos 15 minutos.** Um número instantâneo não responde à pergunta real. "Verde na última meia hora" diz que mais RAM não resolveria nada hoje; "vermelho há dez minutos" diz que algo está fora de controle. O gráfico tem as linhas de referência em 35% e 60%, os mesmos cortes dos rótulos Normal / Moderada / Alta.

**Detecção de crescimento.** O app acompanha o RSS de cada processo ao longo da sessão e marca com um selo âmbar quem cresceu mais de 250 MB **e** mais de 50% em relação ao primeiro momento em que foi visto, com no mínimo 2,5 minutos de observação. Esse mínimo evita acusar um app que acabou de abrir e naturalmente cresceu carregando. É o sintoma de vazamento que um número instantâneo esconde.

**Encerrar o que está comendo memória.** No menu de cada processo:

- *Pedir para encerrar* — para app com interface manda o mesmo evento do ⌘Q, então ele pode perguntar sobre trabalho não salvo; para daemon, `SIGTERM`.
- *Forçar encerramento* — `forceTerminate`/`SIGKILL`, só depois de confirmação explícita, porque aí o que não foi salvo é perdido.

Travas: nunca encerra pid ≤ 1, nem o próprio SaveMyMac, nem os ~29 processos da lista crítica (matar o `WindowServer` derruba a interface; matar o `launchd` reinicia a máquina), nem processo de outro usuário — e nesse caso o app **não** escala privilégio, porque trocar estabilidade por um número não vale. Processos que o macOS relança sozinho (Finder, Dock) são permitidos com aviso.

Detalhe de implementação que vale registrar: o nome bonito e o ícone vêm de `NSRunningApplication`, que é AppKit. Resolver isso no parse do `ps` significaria centenas de consultas AppKit em thread de fundo a cada 2 segundos — então o enriquecimento acontece na thread principal e só para as ~12 linhas que vão à tela.

### Sobre temperatura no Mac

A parte honestamente difícil: a Apple não expõe API pública de temperatura da CPU. O app tenta, em ordem:

1. **Sensores IOHID** (`IOHIDEventSystemClient`) — funciona em vários Macs Apple Silicon, sem senha. É API privada, resolvida em runtime com `dlsym`: se a Apple mudar algo, o app deixa de mostrar a temperatura em vez de quebrar.
2. **Temperatura da bateria**, do IORegistry — quase sempre disponível em notebooks.
3. **Estado térmico** (`ProcessInfo.thermalState`) — Normal / Aquecendo / Quente / Crítico. Sempre disponível.
4. **Botão de leitura com admin** — roda `powermetrics` uma vez via `osascript`, com o diálogo nativo de senha. Em Macs Intel entrega temperatura de CPU/GPU e RPM das ventoinhas de forma confiável.

---

## 4. Limpeza

A varredura é **somente leitura**. Nada sai até você marcar e confirmar.

Cada categoria tem nível de risco e uma nota **RISCO n/10**, mais granular que o nível — "atenção" abrange desde cache de npm (4) até simulador de iOS (5).

| Risco | Significado | Pré-marcado |
|---|---|---|
| 🟢 Seguro (1–2) | temporário, o sistema recria | sim |
| 🟠 Atenção (3–5) | recriável, mas custa download ou build | não |
| 🔴 Revisar (6–10) | pode conter arquivos seus | não |

**Categorias:** caches de aplicativos (incluindo dentro de containers sandboxados), logs e relatórios de travamento, `.DS_Store`, ferramentas de desenvolvedor (DerivedData, DeviceSupport, simuladores, VS Code, JetBrains, Android system images, VM do Docker), caches de 22 gerenciadores de pacotes, `node_modules` sem atividade há 90 dias, instaladores `.dmg`/`.pkg`/`.iso`, downloads antigos, backups locais de iPhone/iPad, e sobras de apps desinstalados.

Padrão de remoção é **Mover para a Lixeira**. A comemoração diz "movidos para a Lixeira" nesse caso, não "liberados", porque o espaço só volta ao esvaziá-la.

### Esvaziar a Lixeira

Card no topo da aba Limpeza, com total, contagem e a data do item mais antigo. **Escopo: apenas `~/.Trash`.** Cada volume externo tem a sua própria Lixeira em `/Volumes/<nome>/.Trashes/<uid>/` e essas não são tocadas.

Esta é a única operação irreversível do app — não existe "mover para a Lixeira" o que já está nela —, então sempre passa por confirmação com o total e a contagem.

A Lixeira **não** é mais uma categoria da varredura, e isso conserta um bug: no modo padrão o removedor chamava `trashItem` em algo que já estava na Lixeira, o que o Cocoa rejeita — ou, pior, renomeia dentro dela, fazendo o app reportar sucesso sem liberar byte nenhum. Esvaziar é sempre permanente, então não pode compartilhar o caminho das outras categorias.

Três salvaguardas:

- **Enumera a pasta ao vivo**, nunca a lista da tela. O snapshot da interface pode ser de antes da última limpeza — e é justamente a limpeza que enche a Lixeira. Iterando o snapshot, o app diria "esvaziada" sem apagar o que acabou de ser movido.
- **Recusa se `~/.Trash` não for uma pasta real.** `standardizedFileURL` resolve `.` e `..` mas não resolve symlink; sem essa checagem, uma Lixeira redirecionada faria o app apagar recursivamente o alvo.
- **Não premia remoção zero.** Lixeira já vazia ou itens travados com `chflags uchg` geram aviso, não XP e comemoração.

---

## 5. Aplicativos

Lista os apps instalados com tamanho real, ícone e **último uso** (via `kMDItemLastUsedDate` do Spotlight, consultado em paralelo). Apps embutidos da Apple ficam fora.

Para cada app, o scanner varre 12 lugares da Library e mostra tudo que ele deixou espalhado — cache, dados de apoio, containers, estado salvo, HTTPStorages, WebKit, logs, preferências, scripts, cookies, agentes de inicialização. O match é por bundle id, por prefixo (`com.foo.App.Helper`) e por nome.

Duas ações:

- **Limpar cache** — remove só o que é regenerável.
- **Desinstalar** — o bundle mais todos os dados de apoio, com o total confirmado antes.

Tudo pela Lixeira, sempre. Nenhuma operação pede senha. Se o bundle estiver num lugar que exige privilégio, a falha é reportada com a instrução em vez de escalar sozinho.

---

## 6. Grandes arquivos e duplicados

**Treemap** proporcional por tipo — vídeos, máquinas virtuais, imagens de disco, backups, áudio, imagens, compactados, bases de dados. Clique numa faixa para filtrar a lista.

**Duplicados agrupados.** Duas salvaguardas que valem explicar:

1. A varredura agrupa por **tamanho lógico** exato, não pelo alocado em disco. Em APFS, clones e arquivos esparsos têm alocado diferente do lógico: usar o alocado faria duplicados reais não se agruparem, e prometeria espaço que apagar um clone não devolve.
2. O hash de amostras (3 × 256 KB) é rápido o suficiente para centenas de milhares de arquivos, mas pode coincidir em arquivos diferentes — dois discos de VM clonados e depois divergidos no meio, por exemplo. Então **antes de apagar**, cada cópia é comparada **byte a byte** com a original. As que não passam são preservadas e reportadas.

A cópia mais antiga de cada grupo é sempre preservada e nunca aparece na remoção.

---

## 7. Offload por link simbólico

Move uma pasta pesada para outro disco e deixa um link no lugar. O macOS continua achando tudo; o espaço volta para o SSD interno.

### Candidatos

O app não sugere por tamanho. A distinção é entre grande-e-frio, regenerável, e gerenciado por outro:

| Veredito | Quando | Exemplos |
|---|---|---|
| **Bom candidato** | grande, frio, sem alternativa nativa | iOS DeviceSupport, simuladores, backups de iPhone, Android SDK, AVDs, Movies, VMs, modelos do Ollama |
| **Melhor apagar** | regenerável e barato | caches de npm, pip, Homebrew, e o DerivedData do Xcode — que em disco externo *piora* o tempo de build |
| **Use o ajuste do app** | o app gerencia o arquivo | Docker (Settings → Resources → Disk image location), Steam (Pastas da biblioteca), Adobe (Media Cache) |
| **Não linkar** | daemon do sistema mexe nisso | iCloud Drive, biblioteca do Fotos |

### A sequência da migração

Cada etapa é registrada no journal **antes** de acontecer:

1. **Checagens** — o volume aceita link simbólico? (`volumeSupportsSymbolicLinksKey` — exFAT e FAT não aceitam, e o app recusa antes de tocar em nada). Cabe? O caminho é permitido? Não há aninhamento?
2. **Cópia** com `ditto`, para uma área de staging no destino. `ditto` é da Apple e preserva metadados, xattrs, ACLs e resource forks — `rsync` foi evitado porque a implementação mudou no macOS 14.
3. **Verificação** — contagem de arquivos e bytes conferem, com tolerância de 0,5 %.
4. **Quarentena** — o original vai para `~/.savemymac-quarantine`. É rename no mesmo volume, instantâneo.
5. **Publicação** — o staging passa a ser o alvo definitivo.
6. **Link simbólico** no lugar do original.
7. **Validação** — lê pelo link, confere a contagem, e escreve/apaga um arquivo de teste. Este último pega volume montado só-leitura.

**O original nunca é apagado.** Fica na quarentena até você mandar liberar — e é só nesse momento que o espaço volta ao disco. Enquanto estiver lá, cada migração pode ser revertida com um clique.

Qualquer falha reverte tudo automaticamente, sempre devolvendo o original da quarentena (rename local instantâneo) em vez de trazer a cópia externa de volta.

### Inventário dos links existentes

| Status | Significado |
|---|---|
| **OK** | aponta para outro volume, montado, alvo existe |
| **Volume ausente** | o disco de destino não está montado agora |
| **Quebrado** | o volume está montado mas o alvo não existe mais |
| **Mesmo disco** | aponta para outro lugar do próprio Mac — funciona, mas não economiza nada |

Mais **dados órfãos**: pastas na área de offload que nenhum link aponta. Para evitar falso positivo, uma pasta-pai só é analisada se a maioria do que está nela já for alvo de link — assim um disco de trabalho comum não é acusado inteiro.

No menu de contexto de cada link: mostrar origem ou destino no Finder, e **copiar o comando `ln -s` pronto**.

### O bug que essa aba revelou

Se `~/.gradle` é um link para `/Volumes/CachePart/mac-offload/gradle`, o `fileExists` atravessa o link. Sem tratamento, a aba Limpeza faria duas coisas erradas: contar o espaço do disco externo como recuperável no interno, e apagar dados reais no SSD externo achando que estava limpando o Mac.

`VolumeResolver` resolve isso comparando a **identidade do volume** (`volumeIdentifierKey`) de cada caminho com a do volume onde a home está — e não com `/`, porque no macOS moderno a home fica no volume de Dados, ligado à raiz por *firmlink*, que não é symlink e não aparece na resolução de caminho.

---

## 8. Barra de menus, inicialização e alertas

### O item ao lado do relógio

`MenuBarExtra` com estilo `.window` — painel de verdade, não lista de menu, porque o conteúdo tem barras e números. Mostra espaço livre do disco de boot, pressão de memória, uso de CPU, temperatura e o que há na Lixeira, mais o score de saúde. Abaixo, atalhos que levam direto às abas.

O rótulo ao lado do ícone é configurável (espaço, memória, CPU, temperatura, ou só o ícone) e mantido minúsculo de propósito: a barra de menus é espaço compartilhado. **O ícone troca para um triângulo de alerta quando o espaço cai abaixo do limiar**, independente da métrica escolhida.

Clicar num atalho não mexe na política de ativação — se você escondeu o ícone do Dock, o app continua `.accessory` e ainda assim mostra a janela. Trazer o ícone de volta ali desfaria sua preferência pelas costas.

### Abrir ao ligar o Mac

Aqui há uma armadilha que vale explicar. A API correta no macOS 13+ é `SMAppService.mainApp.register()`: aparece em Ajustes do Sistema › Geral › Itens de Início e o usuário pode desativar por lá. Só que ela **exige assinatura de código válida** — e este build é assinado ad-hoc.

Então o app tenta a moderna e, se o registro for recusado, cai para um **LaunchAgent** em `~/Library/LaunchAgents`, que funciona sem assinatura. A tela de Ajustes **diz qual mecanismo está ativo** em vez de fingir que é tudo igual. Ao desativar, os dois caminhos são desfeitos: `unregister()` e `launchctl bootout` + remoção do plist.

Também há um toggle para **esconder o ícone do Dock**, aplicado na hora via `setActivationPolicy` — sem reiniciar. Com ele ligado, o app vira um utilitário de barra de menus.

Para o app sobreviver ao fechar a janela (requisito de qualquer app de barra de menus), um `NSApplicationDelegate` mínimo devolve `false` em `applicationShouldTerminateAfterLastWindowClosed`.

### Alerta de pouco espaço

Notificação via `UNUserNotificationCenter`, com limiar ajustável de 3 % a 30 % (padrão 10 %). Duas regras que separam um alerta útil de um irritante:

- **Histerese.** Dispara ao cruzar o limiar para baixo e só rearma depois de o espaço subir 3 pontos percentuais acima dele. Sem isso, um disco oscilando em torno de 10 % notificaria a cada checagem de 2 segundos.
- **Intervalo mínimo.** Mesmo continuando abaixo, no máximo um aviso a cada 6 horas.

A permissão de notificação é pedida quando você **liga** a opção, não na inicialização — pedir antes de o usuário querer é a maneira mais rápida de ela ser negada para sempre. Se for negada, o aviso na barra de menus continua funcionando e a tela de Ajustes diz isso.

---

## 9. Progresso e conquistas

Guardado em `~/Library/Application Support/SaveMyMac/game.json`, com escrita atômica.

Nível (1200 XP cada), XP proporcional ao espaço processado, streak de semanas ISO consecutivas, 12 conquistas e meta mensal. **Isto é estado do app, não do sistema** — XP, nível e streak são invenção do SaveMyMac. O que é real é o histórico: cada registro corresponde a bytes que de fato saíram do disco, com data e tipo.

O streak não zera só porque a semana corrente ainda não teve limpeza — ele só se rompe quando uma semana inteira passa em branco.

---

## 10. Travas de segurança

- Toda varredura é somente leitura.
- Remoção padrão é a Lixeira; *Apagar definitivamente* existe mas não é o padrão.
- `CleanupRemover.rejectionReason` recusa: links simbólicos, conteúdo em outro volume, qualquer coisa fora da sua pasta pessoal, as pastas de primeiro nível da home, e Keychains / Mail / AddressBook / CloudStorage / Mobile Documents / Group Containers / preferências `com.apple.*`.
- `AppUninstaller.rejectionReason` é mais permissiva (`/Applications` é alvo legítimo) mas barra `/System`, `/usr`, `/bin`, `/sbin`, `/Library/Apple` e `/Library/Security`.
- `MigrationEngine.sourceProblem` barra iCloud Drive, CloudStorage, Keychains, Mail, Messages, containers, preferências e biblioteca do Fotos.
- Duplicados só saem depois de comparação byte a byte.
- Migração não é cancelável no meio, de propósito.
- Nenhuma operação pede senha, exceto a leitura opcional de temperatura.
- Sem rede, sem telemetria, nada residente em background.

---

## 11. Estrutura

```
SaveMyMac/
├── build.sh                        compila e monta o .app
├── Info.plist
├── Resources/Fonts/                Space Grotesk + JetBrains Mono (variáveis)
└── Sources/
    ├── SaveMyMacApp.swift          @main, sidebar, faixa do topo, navegação
    ├── AppState.swift              estado observável e orquestração
    ├── Theme/
    │   ├── Palette.swift           paleta clara e escura
    │   ├── Typography.swift        Space Grotesk + JetBrains Mono
    │   └── Motion.swift            as oito animações do design
    ├── Support/
    │   ├── Preferences.swift       configuração persistida
    │   ├── LaunchAtLogin.swift     SMAppService com fallback para LaunchAgent
    │   ├── SpaceAlert.swift        alerta de pouco espaço com histerese
    │   ├── Formatting.swift        bytes, %, datas, durações
    │   ├── CancellationFlag.swift  flag thread-safe de cancelamento
    │   ├── VolumeResolver.swift    em que volume um caminho realmente vive
    │   └── Persistence.swift       JSON atômico no Application Support
    ├── Metrics/                    sistema, RAM, CPU, disco, bateria, térmico
    │   ├── ProcessMonitor.swift    lista de processos via ps, com locale fixo
    │   ├── ProcessController.swift encerrar com travas de segurança
    │   └── MemoryHistory.swift     curva de pressão e detecção de crescimento
    ├── Health/HealthScore.swift    score 0–100 explicável
    ├── Gamification/GameStore.swift nível, XP, streak, conquistas, histórico
    ├── Cleanup/                    modelos, scanner e removedor com travas
    ├── Apps/                       inventário, cache e desinstalação limpa
    ├── Files/FileScanner.swift     grandes + treemap + duplicados + comparador
    ├── Offload/
    │   ├── OffloadModels.swift     link, status, órfão, grupo por volume
    │   ├── OffloadScanner.swift    inventário dos links existentes
    │   ├── MigrationModels.swift   fases, journal, candidatos
    │   ├── MigrationEngine.swift   copiar, verificar, quarentena, linkar, validar
    │   └── CandidateScanner.swift  catálogo de candidatos com veredito
    └── Views/                      as seis telas + componentes + comemoração
```

## 12. Atalhos

| Atalho | Ação |
|---|---|
| ⌘R | Analisar o Mac |
| ⇧⌘F | Analisar arquivos e duplicados |
| ⇧⌘A | Analisar aplicativos |
| ⌘L | Verificar links de offload |
| ⌘U | Atualizar métricas |
| ⇧⌘T | Alternar tema |
| ⌘, | Ajustes |

## 13. Ajustando os limiares

| O que | Onde | Valor |
|---|---|---|
| Downloads antigos | `CleanupScanner.oldDownloads` | 90 dias |
| `node_modules` abandonados | `CleanupScanner.staleNodeModules` | 90 dias, > 20 MB |
| App sem uso | `InstalledApp.isStale` | 90 dias |
| Arquivo grande | `FileScanner.largeThreshold` | 500 MB |
| Mínimo para duplicados | `FileScanner.duplicateThreshold` | 2 MB |
| Candidato a offload | `CandidateScanner` | 200 MB no catálogo, 5 GB nas descobertas |
| XP por GB | `GameStore.xpReward` | 12, com piso de 20 |
| Janela da curva de pressão | `MemoryHistory.capacity` | 450 amostras (15 min) |
| Crescimento suspeito | `GrowthTracker` | 250 MB, +50%, mín. 2,5 min |
| Meta mensal | `GameState.monthlyGoalBytes` | 60 GB |
| Limiar de pouco espaço | Ajustes (ou `lowSpaceThreshold`) | 10 % livres |
| Rearme do alerta | `SpaceAlert.rearmMargin` | +3 pontos percentuais |
| Intervalo entre alertas | `SpaceAlert.minimumInterval` | 6 horas |

Para adicionar uma pasta ao catálogo de offload, inclua uma linha em `CandidateScanner.catalog` com o veredito. Para uma nova categoria de limpeza, um item em `CleanupScanner.scan` e a função correspondente.
