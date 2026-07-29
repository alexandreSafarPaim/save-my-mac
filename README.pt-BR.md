<img src="SaveMyMac/Resources/logo-1024.png" width="120" align="right" alt="SaveMyMac">

# SaveMyMac

App nativo em SwiftUI que mostra o que o seu Mac está realmente fazendo, lista o
que pode ser removido **com checkbox em cada item**, e descarrega pastas pesadas
para um disco externo deixando um link simbólico no lugar.

[![Build](https://github.com/alexandreSafarPaim/save-my-mac/actions/workflows/build.yml/badge.svg)](https://github.com/alexandreSafarPaim/save-my-mac/actions/workflows/build.yml)
[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-brightgreen.svg)](LICENSE)
![Plataforma](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

🇬🇧 [Read in English](README.md)

---

## O que importa saber primeiro

**Este app nunca apaga nada por conta própria.**

Isso é uma restrição de projeto, não uma configuração padrão — não existe botão
de "limpar tudo" escondido em algum canto. Toda varredura produz uma lista, todo
item tem checkbox, nada vem marcado por descuido. A limpeza manda para a Lixeira
quando possível, então uma decisão ruim é reversível.

Se você procura limpeza automática com um clique, esta é a ferramenta errada, de
propósito. Limpadores de disco que decidem no seu lugar são como as pessoas
perdem trabalho.

## O que ele faz

| Tela | O que entrega |
|---|---|
| **Painel** | Disco, pressão de memória, CPU, temperatura, tempo ligado, processos que mais consomem, e uma nota de saúde que explica como foi calculada |
| **Limpeza** | Caches, logs e sobras agrupados por categoria — você escolhe o que vai |
| **Aplicativos** | Todo app instalado com tamanho de cache e último uso; limpa o cache ou desinstala por completo, arquivos de suporte inclusos |
| **Grandes arquivos** | Os maiores arquivos do volume de inicialização, com filtro |
| **Duplicados** | Agrupados por conteúdo e comparados **byte a byte** antes de qualquer remoção |
| **Offload** | Move uma pasta pesada para outro volume e deixa um link simbólico, então os apps continuam achando o caminho enquanto o espaço é liberado |

Mais o item na barra de menus com métricas ao vivo, alerta de pouco espaço,
abertura automática ao ligar o Mac, e temas claro e escuro.

### Temperatura sem pedir senha

As leituras vêm do `IOHIDEventSystemClient`, uma API privada da Apple resolvida
em tempo de execução com `dlopen`/`dlsym`. Se a Apple mudar ou remover, o app
mostra o estado térmico grosseiro em vez de quebrar. Existe também um caminho
opcional via `powermetrics`, que pede senha de administrador, para a temperatura
do die da CPU.

## Requisitos

- macOS 13 (Ventura) ou mais novo
- Command Line Tools da Apple — **não precisa do Xcode**

## Instalar

Dois caminhos. Os dois terminam no mesmo app; a diferença é se o macOS faz
perguntas no meio.

### Opção A — baixar uma release

Baixe o DMG da [release mais recente](https://github.com/alexandreSafarPaim/save-my-mac/releases/latest),
abra e arraste o **SaveMyMac** para Aplicativos.

Na primeira abertura, o macOS vai dizer que *"não foi possível verificar se
está livre de malware"*. É esperado: as releases são **assinadas ad-hoc** —
não há certificado pago de Apple Developer por trás, então a Apple nunca
escaneou o app e o Gatekeeper avisa isso. Não é um veredito sobre o código
(que você pode ler). Clique em **OK** (não em "Mover para o Lixo") e então
abra **Ajustes do Sistema › Privacidade e Segurança**, role até o fim e clique
em **Abrir Mesmo Assim** — ou rode:

```bash
xattr -d com.apple.quarantine /Applications/SaveMyMac.app
```

Só é preciso uma vez. (O truque antigo de clique-direito → Abrir não oferece
mais "Abrir" para apps não-notarizados nos macOS recentes.)

Prefere pular o diálogo por completo? A marca de quarentena é posta pelo
*navegador* no download — baixando com `curl`, ela nunca existe:

```bash
curl -L -o /tmp/SaveMyMac.dmg https://github.com/alexandreSafarPaim/save-my-mac/releases/latest/download/SaveMyMac-v1.0.dmg
hdiutil attach /tmp/SaveMyMac.dmg
cp -R /Volumes/SaveMyMac/SaveMyMac.app /Applications/
hdiutil detach /Volumes/SaveMyMac
```

### Opção B — compilar você mesmo

Nenhum diálogo do Gatekeeper: um app compilado na sua própria máquina não
carrega marca de quarentena, e você lê exatamente o que vai rodar. Não existe
`.xcodeproj` — o app é compilado chamando o `swiftc` direto, o que mantém o
build inteiro legível num único script de shell. Leva cerca de um minuto.

```bash
xcode-select --install        # só se o swiftc não existir ainda
git clone https://github.com/alexandreSafarPaim/save-my-mac.git
cd save-my-mac/SaveMyMac
chmod +x build.sh
./build.sh --install --run
```

| Comando | Resultado |
|---|---|
| `./build.sh` | compila para a arquitetura da sua máquina |
| `./build.sh --universal` | binário universal (Apple Silicon + Intel) |
| `./build.sh --run` | compila e abre |
| `./build.sh --install` | compila e instala em `/Applications` |
| `./build.sh --dmg` | gera uma imagem de disco distribuível |

### Nos dois casos

A assinatura ad-hoc também significa que o `SMAppService` (a API moderna de Itens de Início)
pode recusar o registro. O app detecta e cai para um LaunchAgent do usuário, e
os Ajustes dizem qual mecanismo está de fato ativo.

### Acesso Total ao Disco

Sem isso a varredura pula pastas protegidas em silêncio e subestima o que pode
ser recuperado. Libere em:

**Ajustes do Sistema → Privacidade e Segurança → Acesso Total ao Disco**

## Contribuir

Pull requests são bem-vindos. Leia o [CONTRIBUTING.md](CONTRIBUTING.md) antes —
em especial a parte sobre código que apaga arquivos, que é revisado com critério
mais rígido que o resto por motivos que devem ser óbvios.

Duas coisas para saber de antemão:

- **Os comentários do código estão sendo traduzidos** de português para inglês.
  Os identificadores sempre foram em inglês; a prosa não era.
- **A interface é bilíngue** (português e inglês), trocável em Ajustes e com
  padrão vindo do idioma do seu Mac.

## Arquitetura

O documento técnico completo está em
[SaveMyMac/README.pt-BR.md](SaveMyMac/README.pt-BR.md) (em português;
[English version](SaveMyMac/README.md)) —
organização dos módulos, como cada varredura decide o que é seguro, o desenho do
diário e do rollback do offload, e uma lista dos bugs que deram trabalho para
encontrar e que vale não reintroduzir.

## Segurança

O app lê todo o seu disco e pode apagar arquivos. Se você encontrar uma forma de
fazê-lo apagar algo que não devia, avise em particular — veja o
[SECURITY.md](SECURITY.md).

## Licença

[MIT](LICENSE) © Alexandre Safar Paim
