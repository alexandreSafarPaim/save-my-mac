#!/usr/bin/env python3
"""
Gera o fundo da janela do DMG.

## O problema do rótulo do Finder

O Finder desenha o rótulo de cada ícone ("SaveMyMac", "Applications") por conta
própria, na cor da aparência do sistema: **preto no modo claro, branco no
escuro**. O fundo do DMG é uma imagem fixa, então nenhum extremo agrada aos dois:

  - fundo escuro  -> 18,8:1 no modo escuro, 1,1:1 no claro  (ilegível)
  - fundo claro   -> 17,9:1 no modo claro,  1,2:1 no escuro (ilegível)

O padrão aqui é **fundo claro**, que é o que a maioria dos apps Mac usa. A
identidade fica no gradiente da marca e no ícone, não no fundo.

Houve uma tentativa de resolver os dois modos com placas de meio-tom na
luminância 0,179 — o ponto onde o contraste fica 4,58:1 contra preto e 4,59:1
contra branco, matematicamente o melhor pior-caso. Funcionava na medição e ficou
feio na tela: dois retângulos no meio da janela. Contraste medido não é o mesmo
que desenho bom, e aqui o desenho ganhou.

`contrast_report` continua medindo e imprimindo os dois valores, para a escolha
ser informada em vez de adivinhada.

## Zona livre

A faixa de y=205 a y=305 é dos rótulos do Finder. Nenhum texto desenhado entra
nela — na primeira versão o texto de instrução colidia com eles.

Uso:
  python3 tools/make-dmg-background.py            # fundo claro (padrão)
  python3 tools/make-dmg-background.py --dark     # fundo escuro

Saída:
  Resources/dmg-background.png     (1x)
  Resources/dmg-background@2x.png  (2x, para telas Retina)
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Paleta repetida aqui de propósito: o hífen em `make-icon.py` impede o import
# direto, e dois rótulos não justificam renomear o outro script.
ACCENT = (0x7C, 0x5C, 0xFF)
CYAN = (0x22, 0xE0, 0xFF)

# Tema claro (usa a variante clara da paleta do app)
L_BG = (0xF7, 0xF6, 0xFC)
L_BG2 = (0xEB, 0xE8, 0xF6)
L_T1 = (0x14, 0x10, 0x2D)
L_T3 = (0x6E, 0x6A, 0x86)

# Tema escuro
D_BG = (0x0D, 0x0B, 0x18)
D_BG2 = (0x08, 0x07, 0x0F)
D_T1 = (0xF2, 0xF0, 0xFF)
D_T3 = (0x8A, 0x86, 0xA8)

# Faixa de meio-tom: luminância 0,177 — o ponto que equilibra o contraste
# contra rótulo preto e branco. Ver o cabeçalho.
BAND = (0x7D, 0x6D, 0x9B)

W, H = 660, 420
SS = 2

# Onde o Finder põe ícone e rótulo (coordenadas 1x). O ícone é de 128px
# centrado em y=150; o rótulo cai logo abaixo.
ICON_CENTERS = (165, 495)
ICON_CENTER_Y = 150
LABEL_ZONE = (222, 272)      # faixa vertical ocupada pelo rótulo
PLATE = (214, 282)           # a placa cobre só o rótulo, não o ícone
PLATE_WIDTH = 188

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources")


def radial(size, center, radius, color, strength):
    w, h = size
    x, y = np.meshgrid(np.arange(w), np.arange(h))
    d = np.sqrt((x - center[0]) ** 2 + (y - center[1]) ** 2) / radius
    a = np.clip(1.0 - d, 0.0, 1.0) ** 2 * strength
    layer = np.zeros((h, w, 4), dtype=np.uint8)
    layer[..., 0], layer[..., 1], layer[..., 2] = color
    layer[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(layer, mode="RGBA")


def load_font(size_px):
    """Tenta a Space Grotesk embutida no projeto; cai para a default do PIL."""
    candidate = os.path.join(OUT, "Fonts", "SpaceGrotesk-Variable.ttf")
    if os.path.exists(candidate):
        try:
            return ImageFont.truetype(candidate, size_px)
        except Exception:
            pass
    try:
        return ImageFont.load_default(size=size_px)
    except Exception:
        return None


def render(dark: bool):
    w, h = W * SS, H * SS
    bg, bg2 = (D_BG, D_BG2) if dark else (L_BG, L_BG2)
    t1, t3 = (D_T1, D_T3) if dark else (L_T1, L_T3)

    # gradiente vertical sutil
    grad = np.linspace(0, 1, h).reshape(-1, 1)
    body = np.zeros((h, w, 3), dtype=np.uint8)
    for i in range(3):
        body[..., i] = (bg[i] + (bg2[i] - bg[i]) * grad).astype(np.uint8)
    img = Image.fromarray(np.dstack([body, np.full((h, w), 255, np.uint8)]), "RGBA")

    # Grade e seta vão em camadas próprias e são COMPOSTAS. `ImageDraw`
    # sobrescreve o pixel inteiro, alfa incluído — desenhar direto com alfa baixo
    # deixa o PIXEL translúcido, não a linha, e o `convert("RGB")` final descarta
    # o alfa fazendo a linha aparecer sólida.
    grid_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid_layer)
    step = 56 * SS
    grid = ACCENT + (20 if dark else 14,)
    for x in range(0, w, step):
        gd.line([(x, 0), (x, h)], fill=grid, width=SS)
    for y in range(0, h, step):
        gd.line([(0, y), (w, y)], fill=grid, width=SS)
    img.alpha_composite(grid_layer)

    # halos da marca — no tema claro entram bem mais suaves para não comprometer
    # o contraste do rótulo preto do Finder
    strength = (0.55, 0.38) if dark else (0.20, 0.14)
    img.alpha_composite(radial((w, h), (w * 0.14, -h * 0.06), w * 0.62, ACCENT, strength[0]))
    img.alpha_composite(radial((w, h), (w * 0.93, h * 1.04), w * 0.55, CYAN, strength[1]))

    # Seta entre as duas posições de ícone (x=165 e x=495 no espaço 1x),
    # na altura do centro dos ícones.
    arrow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)
    y = int(150 * SS)
    x0, x1 = int(268 * SS), int(392 * SS)
    arrow_color = CYAN if dark else (0x0F, 0xA5, 0xC9)
    ad.line([(x0, y), (x1 - 15 * SS, y)], fill=arrow_color + (255,), width=3 * SS)
    ad.polygon(
        [
            (x1, y),
            (x1 - 17 * SS, y - 10 * SS),
            (x1 - 17 * SS, y + 10 * SS),
        ],
        fill=arrow_color + (255,),
    )
    img.alpha_composite(arrow)

    d = ImageDraw.Draw(img)

    def label(text, cy, color, size_px, weight_hint=None):
        font = load_font(int(size_px * SS))
        d.text(
            (w // 2, int(cy * SS)),
            text,
            fill=color + (255,),
            anchor="mm",
            font=font,
        )

    label("SaveMyMac", 44, t1, 28)

    # Tudo abaixo dos pedestais, para não disputar espaço com o rótulo do Finder.
    label("Arraste o app para a pasta Aplicativos", 328, t1, 15)
    label("Depois, conceda Acesso Total ao Disco em", 360, t3, 12)
    label("Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco", 380, t3, 12)

    return img


def contrast_report(img, dark):
    """Confere o contraste da faixa dos rótulos do Finder contra preto e branco.

    Não é enfeite: é exatamente o defeito que motivou este redesenho, então vale
    medir em vez de confiar no olho.
    """
    # Amostra apenas os dois retângulos onde o Finder desenha o rótulo — medir a
    # janela toda daria uma média sem significado.
    crops = []
    for cx in ICON_CENTERS:
        crops.append(img.convert("RGB").crop((
            int((cx - 90) * SS), LABEL_ZONE[0] * SS,
            int((cx + 90) * SS), LABEL_ZONE[1] * SS,
        )))
    pixels = np.concatenate(
        [np.asarray(c, dtype=np.float64).reshape(-1, 3) for c in crops]
    ) / 255.0

    # luminância relativa (WCAG)
    linear = np.where(pixels <= 0.04045, pixels / 12.92, ((pixels + 0.055) / 1.055) ** 2.4)
    lum = 0.2126 * linear[..., 0] + 0.7152 * linear[..., 1] + 0.0722 * linear[..., 2]
    mean = float(lum.mean())

    against_black = (mean + 0.05) / 0.05
    against_white = 1.05 / (mean + 0.05)

    print(f"    luminância média sob os rótulos: {mean:.3f}")
    print(f"    contraste com rótulo PRETO  (modo claro):  {against_black:.2f}:1")
    print(f"    contraste com rótulo BRANCO (modo escuro): {against_white:.2f}:1")
    worst = min(against_black, against_white)
    verdict = "ok" if worst >= 3.0 else "BAIXO"
    print(f"    pior caso: {worst:.2f}:1 — {verdict}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dark", action="store_true",
                        help="gera a variante escura (rótulo do Finder só legível em modo escuro)")
    args = parser.parse_args()
    dark = args.dark

    os.makedirs(OUT, exist_ok=True)
    art = render(dark=dark)

    normal = art.resize((W, H), Image.LANCZOS)
    retina = art.resize((W * 2, H * 2), Image.LANCZOS)

    normal.convert("RGB").save(os.path.join(OUT, "dmg-background.png"))
    retina.convert("RGB").save(os.path.join(OUT, "dmg-background@2x.png"))

    tema = "escuro" if dark else "claro"
    print(f"==> Resources/dmg-background.png ({W}×{H}, tema {tema})")
    print(f"==> Resources/dmg-background@2x.png ({W * 2}×{H * 2})")
    contrast_report(art, dark)
    return 0


if __name__ == "__main__":
    sys.exit(main())
