#!/usr/bin/env python3
"""
Gera a identidade visual do SaveMyMac a partir de uma única definição.

A marca vem do design: quadrado com o gradiente roxo→ciano, um anel de
progresso e o sparkle de 4 pontas no centro. O sparkle é exatamente o do
design (tips nos eixos a 102, cintura a 26 na diagonal — proporção 0,2549).

Saídas:
  Resources/AppIcon.iconset/   os 10 PNGs que o iconutil transforma em .icns
  Resources/logo.svg           a marca em vetor
  Resources/logo-1024.png      para README e divulgação
  Resources/logo-dark.png      variante escura (fundo grafite, marca luminosa)

Uso:
  python3 tools/make-icon.py            # variante gradiente (padrão)
  python3 tools/make-icon.py --dark     # variante escura como ícone principal

Depois, no macOS, o build.sh chama:
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
"""

import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- paleta

ACCENT = (0x7C, 0x5C, 0xFF)      # roxo do design
ACCENT_DEEP = (0x5E, 0x33, 0xE8)  # roxo profundo, para o canto
CYAN = (0x22, 0xE0, 0xFF)        # ciano
INK = (0x0A, 0x08, 0x14)         # grafite do fundo escuro
INK2 = (0x16, 0x12, 0x2A)

# ---------------------------------------------------------------- geometria

SS = 4                            # supersampling
BASE = 1024
CANVAS = BASE * SS

# Grade de ícone do macOS (Big Sur+): conteúdo de 824 num canvas de 1024.
CONTENT = 824 * SS
CORNER_N = 6.2                    # expoente da superelipse (canto contínuo da Apple)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources")
ICONSET = os.path.join(OUT, "AppIcon.iconset")


# ---------------------------------------------------------------- helpers


def squircle_mask(size: int, n: float = CORNER_N) -> Image.Image:
    """Máscara de superelipse |x|^n + |y|^n = 1 — o canto contínuo da Apple,
    que o `rounded_rectangle` do PIL (canto circular) não reproduz."""
    axis = np.linspace(-1.0, 1.0, size)
    x, y = np.meshgrid(axis, axis)
    d = np.abs(x) ** n + np.abs(y) ** n
    # borda suave de ~1.5px na resolução supersampled
    edge = 2.0 / size * n
    alpha = np.clip((1.0 - d) / edge + 0.5, 0.0, 1.0)
    return Image.fromarray((alpha * 255).astype(np.uint8), mode="L")


def linear_gradient(size: int, start, end, angle_deg: float = 140.0) -> Image.Image:
    """Gradiente linear na convenção do CSS: 0° aponta para cima, cresce no
    sentido horário. O design usa 140deg."""
    rad = math.radians(angle_deg)
    dx, dy = math.sin(rad), -math.cos(rad)

    axis = np.linspace(-0.5, 0.5, size)
    x, y = np.meshgrid(axis, axis)
    t = x * dx + y * dy
    t = (t - t.min()) / (t.max() - t.min())

    channels = [
        (start[i] + (end[i] - start[i]) * t).astype(np.uint8) for i in range(3)
    ]
    rgb = np.dstack(channels)
    return Image.fromarray(rgb, mode="RGB")


def three_stop_gradient(size: int, a, b, c, angle_deg: float = 140.0) -> Image.Image:
    """Gradiente com parada no meio. Com duas cores o roxo virava um detalhe de
    canto; com a parada intermediária ele ocupa de fato a metade superior."""
    rad = math.radians(angle_deg)
    dx, dy = math.sin(rad), -math.cos(rad)

    axis = np.linspace(-0.5, 0.5, size)
    x, y = np.meshgrid(axis, axis)
    t = x * dx + y * dy
    t = (t - t.min()) / (t.max() - t.min())

    channels = []
    for i in range(3):
        first = a[i] + (b[i] - a[i]) * np.clip(t / 0.45, 0, 1)
        second = b[i] + (c[i] - b[i]) * np.clip((t - 0.45) / 0.55, 0, 1)
        channels.append(np.where(t < 0.45, first, second).astype(np.uint8))
    return Image.fromarray(np.dstack(channels), mode="RGB")


def radial_glow(size: int, center, radius: float, color, strength: float) -> Image.Image:
    """Halo radial usado para dar volume ao quadrado."""
    axis = np.arange(size)
    x, y = np.meshgrid(axis, axis)
    d = np.sqrt((x - center[0]) ** 2 + (y - center[1]) ** 2) / radius
    a = np.clip(1.0 - d, 0.0, 1.0) ** 2 * strength
    layer = np.zeros((size, size, 4), dtype=np.uint8)
    layer[..., 0] = color[0]
    layer[..., 1] = color[1]
    layer[..., 2] = color[2]
    layer[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(layer, mode="RGBA")


def sparkle_points(cx: float, cy: float, tip: float, waist_ratio: float = 0.30):
    """O sparkle de 4 pontas do design: pontas nos eixos, cintura na diagonal."""
    w = tip * waist_ratio
    return [
        (cx, cy - tip),
        (cx + w, cy - w),
        (cx + tip, cy),
        (cx + w, cy + w),
        (cx, cy + tip),
        (cx - w, cy + w),
        (cx - tip, cy),
        (cx - w, cy - w),
    ]


def draw_arc(draw: ImageDraw.ImageDraw, cx, cy, r, width, start_deg, end_deg, fill):
    """Arco com ponta arredondada.

    Atenção: o `arc` do PIL cresce a espessura para DENTRO do bounding box, de
    modo que a linha de centro fica em `r - width/2`. As tampas têm de ir nesse
    mesmo raio — no raio `r` elas ficariam meio traço para fora e apareceriam
    como bolinhas soltas.
    """
    box = [cx - r, cy - r, cx + r, cy + r]
    draw.arc(box, start=start_deg, end=end_deg, fill=fill, width=int(round(width)))

    center_r = r - width / 2
    h = width / 2
    for deg in (start_deg, end_deg):
        rad = math.radians(deg)
        px, py = cx + center_r * math.cos(rad), cy + center_r * math.sin(rad)
        draw.ellipse([px - h, py - h, px + h, py + h], fill=fill)


# ---------------------------------------------------------------- a marca


def render_mark(dark: bool, simplified: bool = False) -> Image.Image:
    """Desenha o ícone em CANVAS×CANVAS, com sombra.

    `simplified` remove o anel e engorda o sparkle. Isso não é preguiça: a 16px
    o anel e o sparkle se encostam e viram um borrão cinza. Ícone bem feito
    troca de arte nos tamanhos pequenos, e o iconset permite justamente isso.
    """
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # --- corpo do quadrado ---
    if dark:
        body = linear_gradient(CONTENT, INK, INK2, angle_deg=140)
    else:
        body = three_stop_gradient(CONTENT, ACCENT_DEEP, ACCENT, CYAN, angle_deg=140)
    body = body.convert("RGBA")

    # volume: luz no canto superior esquerdo
    body.alpha_composite(
        radial_glow(
            CONTENT,
            (CONTENT * 0.22, CONTENT * 0.18),
            CONTENT * 0.85,
            (255, 255, 255),
            0.13 if not dark else 0.10,
        )
    )
    if dark:
        # na variante escura o halo colorido é o que dá vida
        body.alpha_composite(
            radial_glow(CONTENT, (CONTENT * 0.30, CONTENT * 0.24), CONTENT * 0.80, ACCENT, 0.55)
        )
        body.alpha_composite(
            radial_glow(CONTENT, (CONTENT * 0.78, CONTENT * 0.82), CONTENT * 0.70, CYAN, 0.30)
        )

    # --- anel + sparkle, na mesma proporção do design ---
    art = Image.new("RGBA", (CONTENT, CONTENT), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    cx = cy = CONTENT / 2
    ring_r = CONTENT * 0.335
    ring_w = CONTENT * 0.068

    if not simplified:
        ring_color = (255, 255, 255, 64) if not dark else (255, 255, 255, 34)
        d.ellipse(
            [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
            outline=ring_color,
            width=int(ring_w),
        )

        # arco de 78%, começando no topo — o mesmo recorte do design
        sweep = 360 * 0.78
        start = -90.0
        arc_color = (255, 255, 255, 255) if not dark else CYAN + (255,)
        draw_arc(d, cx, cy, ring_r, ring_w, start, start + sweep, arc_color)

    # sparkle no centro — protagonista sozinho na versão simplificada
    tip = CONTENT * (0.375 if simplified else 0.205)
    spark_color = (255, 255, 255, 255)
    waist = 0.36 if simplified else 0.30
    d.polygon(sparkle_points(cx, cy, tip, waist_ratio=waist), fill=spark_color)

    if dark:
        # brilho em volta do sparkle
        glow = Image.new("RGBA", (CONTENT, CONTENT), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.polygon(sparkle_points(cx, cy, tip * 1.25), fill=CYAN + (150,))
        glow = glow.filter(ImageFilter.GaussianBlur(CONTENT * 0.035))
        art = Image.alpha_composite(glow, art)

    body.alpha_composite(art)

    # --- recorte no squircle ---
    body.putalpha(squircle_mask(CONTENT))

    # --- sombra ---
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    margin = (CANVAS - CONTENT) // 2
    silhouette = Image.new("RGBA", (CONTENT, CONTENT), (0, 0, 0, 255))
    silhouette.putalpha(
        Image.eval(squircle_mask(CONTENT), lambda v: int(v * 0.20))
    )
    shadow.paste(silhouette, (margin, margin + int(CONTENT * 0.014)), silhouette)
    shadow = shadow.filter(ImageFilter.GaussianBlur(CONTENT * 0.014))

    icon = Image.alpha_composite(icon, shadow)
    icon.alpha_composite(body, (margin, margin))

    return icon


# ---------------------------------------------------------------- SVG


def write_svg(path: str) -> None:
    """A mesma marca em vetor, para README e para quem quiser reaproveitar."""
    c = 512.0
    tip = 1024 * 0.185 * (824 / 1024)
    pts = sparkle_points(c, c, tip)
    poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)

    ring_r = 1024 * 0.315 * (824 / 1024)
    ring_w = 1024 * 0.082 * (824 / 1024)
    circumference = 2 * math.pi * ring_r
    dash = circumference * 0.78

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7C5CFF"/>
      <stop offset="1" stop-color="#22E0FF"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.22" cy="0.18" r="0.85">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.28"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <!-- SVG não tem canto contínuo; rx de 22,5 % é a aproximação padrão do
         squircle da Apple e é o que ferramentas de design usam. -->
    <clipPath id="squircle">
      <rect x="100" y="100" width="824" height="824" rx="185.4" ry="185.4"/>
    </clipPath>
  </defs>

  <g clip-path="url(#squircle)">
    <rect x="100" y="100" width="824" height="824" fill="url(#body)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>
    <circle cx="512" cy="512" r="{ring_r:.1f}" fill="none"
            stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="{ring_w:.1f}"/>
    <circle cx="512" cy="512" r="{ring_r:.1f}" fill="none"
            stroke="#FFFFFF" stroke-width="{ring_w:.1f}" stroke-linecap="round"
            stroke-dasharray="{dash:.1f} {circumference:.1f}"
            transform="rotate(-90 512 512)"/>
    <polygon points="{poly}" fill="#FFFFFF"/>
  </g>
</svg>
"""
    with open(path, "w") as f:
        f.write(svg)


# ---------------------------------------------------------------- iconset

# Nomes que o iconutil exige.
ICONSET_SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dark", action="store_true",
                        help="usa a variante escura como ícone principal")
    args = parser.parse_args()

    os.makedirs(ICONSET, exist_ok=True)

    print("==> Desenhando a marca a 4096px (arte completa e simplificada)…")
    primary = render_mark(dark=args.dark)
    primary_small = render_mark(dark=args.dark, simplified=True)
    alternate = render_mark(dark=not args.dark)

    # Abaixo de 64px o anel não sobrevive: usa a arte simplificada.
    SIMPLIFY_BELOW = 64

    print("==> Gerando o iconset")
    for size, scale in ICONSET_SIZES:
        px = size * scale
        source = primary_small if px < SIMPLIFY_BELOW else primary
        img = source.resize((px, px), Image.LANCZOS)
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        img.save(os.path.join(ICONSET, name))
        kind = "simplificada" if px < SIMPLIFY_BELOW else "completa"
        print(f"    {name:24} {px:>4}×{px:<4} arte {kind}")

    print("==> Gerando os PNGs de divulgação")
    primary.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "logo-1024.png"))
    alternate.resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(OUT, "logo-dark.png" if not args.dark else "logo-gradient.png")
    )

    write_svg(os.path.join(OUT, "logo.svg"))
    print("    logo-1024.png, logo.svg e a variante alternativa")

    print("\n✅ Pronto. No macOS, o build.sh converte o iconset em AppIcon.icns.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
