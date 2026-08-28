#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Fonds calculés sur le processeur graphique. L'ancienne génération dessinait
// chaque image sur le processeur central via Canvas ; ici la carte graphique
// évalue chaque pixel en parallèle, ce qui coûte incomparablement moins cher
// pour un rendu bien plus riche.
//
// Le motif « Soie » est adapté de React Bits (MIT + Commons Clause,
// Copyright (c) 2026 David Haz — https://reactbits.dev), utilisé ici au sein
// d'une application, ce que sa licence autorise.

// MARK: - Bruit

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    // Lissage cubique : sans lui, le bruit laisse voir sa grille carrée.
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Deux octaves suffisent pour un fond : chaque octave supplémentaire est un
/// coût par pixel, sur des millions de pixels, soixante fois par seconde.
static float fbm2(float2 p) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int i = 0; i < 2; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

static float fbm3(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.02;
        amplitude *= 0.5;
    }
    return value;
}

/// Bascule lumière / encre.
///
/// Certains motifs ajoutent de la lumière au fond. C'est éclatant sur un fond
/// sombre, mais invisible sur un fond pâle : la valeur sature vers le blanc.
/// En thème clair ils déposent donc de la couleur sombre, comme une encre sur
/// du papier, au lieu d'éclairer.
static float3 applyInk(float3 base, float3 additive, float3 paint, float coverage, float ink) {
    float3 inked = mix(base, paint, clamp(coverage, 0.0, 1.0));
    return mix(additive, inked, ink);
}

/// Grain léger : sans lui, les dégradés très doux montrent des bandes sur les
/// écrans OLED, faute de nuances intermédiaires disponibles.
static float3 dither(float3 color, float2 pos) {
    return color + (hash21(pos) - 0.5) * 0.012;
}

// MARK: - Soie

[[ stitchable ]] half4 birthdaySilk(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 uv = pos / max(size, float2(1.0));
    float2 tex = uv * 2.4;
    float t = time * 0.28;

    tex.y += 0.03 * sin(8.0 * tex.x - t);

    float pattern = 0.6 + 0.4 * sin(
        5.0 * (tex.x + tex.y + cos(3.0 * tex.x + 5.0 * tex.y) + 0.02 * t)
        + sin(20.0 * (tex.x + tex.y - 0.1 * t))
    );

    // Un second pli, plus lent et plus large, casse la régularité du premier
    // et donne au tissu son mouvement paresseux.
    float fold = 0.5 + 0.5 * sin(2.2 * (tex.x - tex.y) + t * 0.6);
    float shade = mix(pattern, pattern * fold, 0.45);

    float3 col = mix(base, tint, shade * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Aurore

[[ stitchable ]] half4 birthdayAurora(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength,
    float ink
) {
    float2 uv = pos / max(size, float2(1.0));
    float t = time * 0.05;

    float3 glow = float3(0.0);
    float coverage = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float anchor = 0.28 + fi * 0.21;
        // Une sinusoïde donne l'ondulation d'ensemble, le bruit lui retire sa
        // régularité mécanique.
        float wave = sin(uv.x * (2.1 + fi * 0.8) + t * 6.0 + fi * 1.9) * 0.05
                   + (fbm2(float2(uv.x * 2.4 + fi * 7.0, t * 2.0 + fi)) - 0.5) * 0.24;
        float distance = abs(uv.y - (anchor + wave));
        // L'exponentielle donne un cœur lumineux qui se dissout en douceur,
        // là où un dégradé linéaire laisserait une arête.
        float band = exp(-distance * (13.0 + fi * 4.5));
        float3 ribbon = mix(tintA, tintB, clamp(fi * 0.5 + uv.x * 0.3, 0.0, 1.0));
        float weight = band * (0.95 - fi * 0.2);
        glow += ribbon * weight;
        coverage += weight;
    }

    // Moyenne pondérée des rubans : la teinte à déposer en mode encre.
    float3 paint = glow / max(coverage, 0.0001);
    float3 col = applyInk(base, base + glow * strength, paint, coverage * strength * 1.7, ink);

    // Voile vertical : le haut reste dense, le bas s'éclaircit.
    col *= 1.0 - 0.18 * smoothstep(0.4, 1.0, uv.y);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Nébuleuse

[[ stitchable ]] half4 birthdayNebula(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    // Correction du rapport d'écran : sans elle, les volutes sont étirées.
    uv.x *= safeSize.x / safeSize.y;

    float t = time * 0.035;
    float2 p = uv * 1.6;

    // Déformation du domaine : on évalue le bruit à une position elle-même
    // issue du bruit. C'est ce repli sur lui-même qui crée les volutes.
    float2 q = float2(fbm2(p + t), fbm2(p + float2(5.2, 1.3) - t));
    float2 r = float2(
        fbm2(p + 1.7 * q + float2(1.7, 9.2) + t * 1.4),
        fbm2(p + 1.7 * q + float2(8.3, 2.8) - t * 1.1)
    );
    float f = fbm3(p + 1.4 * r);

    float3 col = mix(base, tintA, clamp(f * 1.5, 0.0, 1.0) * strength);
    col = mix(col, tintB, clamp(length(r) * 0.75, 0.0, 1.0) * strength * 0.8);
    // Les crêtes reçoivent un surcroît de lumière, comme des nuages éclairés.
    col += tintB * pow(clamp(f, 0.0, 1.0), 3.0) * strength * 0.5;

    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Nacre
//
// Adapté d'« Iridescence » (React Bits). La boucle où chaque terme réinjecte
// le précédent produit des irisations impossibles à obtenir avec de simples
// dégradés superposés.

[[ stitchable ]] half4 birthdayIridescence(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float minSide = min(safeSize.x, safeSize.y);
    float2 uv = (pos / safeSize * 2.0 - 1.0) * safeSize / minSide;

    float d = -time * 0.22;
    float a = 0.0;
    // Six passes suffisent : au-delà, le motif se brouille sans rien apporter.
    for (int i = 0; i < 6; i++) {
        a += cos(float(i) - d - a * uv.x);
        d += sin(uv.y * float(i) + a);
    }
    d += time * 0.22;

    float3 col = float3(cos(uv * float2(d, a)) * 0.6 + 0.4, cos(a + d) * 0.5 + 0.5);
    col = cos(col * cos(float3(d, a, 2.5)) * 0.5 + 0.5) * tint;

    return half4(half3(dither(mix(base, col, strength), pos)), 1.0h);
}

// MARK: - Mercure
//
// Adapté de « Liquid Chrome » (React Bits). Le suréchantillonnage d'origine
// évaluait le motif neuf fois par pixel ; une seule passe suffit ici, le
// mouvement étant lent et le contraste plus doux.

[[ stitchable ]] half4 birthdayChrome(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength,
    float ink
) {
    float2 safeSize = max(size, float2(1.0));
    float minSide = min(safeSize.x, safeSize.y);
    float2 uv = (2.0 * pos - safeSize) / minSide;

    float t = time * 0.35;
    for (int i = 1; i < 7; i++) {
        float fi = float(i);
        uv.x += 0.30 / fi * cos(fi * 3.0 * uv.y + t);
        uv.y += 0.30 / fi * cos(fi * 3.0 * uv.x + t);
    }

    // La division par un sinus crée les bandes serrées du métal poli ; on la
    // borne, sinon les valeurs explosent près de zéro et l'écran blanchit.
    float bands = 1.0 / max(abs(sin(t - uv.y - uv.x)), 0.30);
    float level = clamp(bands * 0.32, 0.0, 1.6);
    // En encre, seules les bandes les plus marquées se déposent : sinon le
    // métal recouvrirait tout l'écran d'un aplat uniforme.
    float3 col = applyInk(base, mix(base, tint * level, strength),
                          tint, (level - 0.55) * 1.4 * strength, ink);

    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Fils
//
// Adapté de « Threads » (React Bits). L'original trace quarante brins, chacun
// avec deux évaluations de bruit de Perlin — soit quatre-vingts par pixel. Sur
// un écran de téléphone à soixante images par seconde, c'est intenable : on
// descend à dix-huit brins, ce qui ne se voit pas puisqu'ils se recouvrent.

static float perlin2D(float2 P) {
    float2 Pi = floor(P);
    float4 Pf_Pfmin1 = P.xyxy - float4(Pi, Pi + 1.0);
    float4 Pt = float4(Pi.xy, Pi.xy + 1.0);
    Pt = Pt - floor(Pt * (1.0 / 71.0)) * 71.0;
    Pt += float2(26.0, 161.0).xyxy;
    Pt *= Pt;
    Pt = Pt.xzxz * Pt.yyww;
    float4 hash_x = fract(Pt * (1.0 / 951.135664));
    float4 hash_y = fract(Pt * (1.0 / 642.949883));
    float4 grad_x = hash_x - 0.49999;
    float4 grad_y = hash_y - 0.49999;
    float4 grad_results = rsqrt(grad_x * grad_x + grad_y * grad_y)
        * (grad_x * Pf_Pfmin1.xzxz + grad_y * Pf_Pfmin1.yyww);
    grad_results *= 1.4142135623730950;
    float2 blend = Pf_Pfmin1.xy * Pf_Pfmin1.xy * Pf_Pfmin1.xy
                 * (Pf_Pfmin1.xy * (Pf_Pfmin1.xy * 6.0 - 15.0) + 10.0);
    float4 blend2 = float4(blend, float2(1.0 - blend));
    return dot(grad_results, blend2.zxzx * blend2.wwyy);
}

static float threadLine(float2 st, float width, float perc, float time, float blurUnit) {
    float split_point = 0.1 + perc * 0.4;
    float amplitude = smoothstep(split_point, 0.7, st.x) * 0.5;
    float t = time / 10.0;
    float blur = smoothstep(split_point, split_point + 0.05, st.x) * perc;

    float xnoise = mix(
        perlin2D(float2(t, st.x + perc) * 2.5),
        perlin2D(float2(t, st.x + t) * 3.5) / 1.5,
        st.x * 0.3
    );

    float y = 0.5 + (perc - 0.5) * 0.7 + xnoise * 0.5 * amplitude;
    float feather = width * 0.5 + blurUnit * 10.0 * blur;
    float start = smoothstep(y + feather, y, st.y);
    float end = smoothstep(y, y - feather, st.y);
    return clamp((start - end) * (1.0 - smoothstep(0.0, 1.0, pow(perc, 0.3))), 0.0, 1.0);
}

[[ stitchable ]] half4 birthdayThreads(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float unit = 1.0 / max(safeSize.x, safeSize.y);

    float remaining = 1.0;
    for (int i = 0; i < 18; i++) {
        float p = float(i) / 18.0;
        remaining *= 1.0 - threadLine(uv, 7.0 * unit * (1.0 - p), p, time, unit);
    }

    float glow = 1.0 - remaining;
    return half4(half3(dither(mix(base, tint, glow * strength), pos)), 1.0h);
}

// MARK: - Tourbillon
//
// Adapté de « Balatro » (React Bits). La rotation dépend de la distance au
// centre, ce qui enroule la matière au lieu de la faire tourner d'un bloc.

[[ stitchable ]] half4 birthdaySwirl(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float diagonal = length(safeSize);
    float2 uv = (pos - 0.5 * safeSize) / diagonal;
    float radius = length(uv);

    float spin = time * 0.08 + 302.2;
    float angle = atan2(uv.y, uv.x) + spin - 4.0 * (0.2 * radius + 0.8);
    float2 mid = (safeSize / diagonal) * 0.5;
    uv = float2(radius * cos(angle) + mid.x, radius * sin(angle) + mid.y) - mid;

    uv *= 30.0;
    float speed = time * 0.5;
    float2 uv2 = float2(uv.x + uv.y);

    for (int i = 0; i < 5; i++) {
        uv2 += sin(max(uv.x, uv.y)) + uv;
        uv += 0.5 * float2(
            cos(5.1123314 + 0.353 * uv2.y + speed * 0.131121),
            sin(uv2.x - 0.113 * speed)
        );
        uv -= cos(uv.x + uv.y) - sin(uv.x * 0.711 - uv.y);
    }

    float contrast = 1.9;
    float paint = min(2.0, max(0.0, length(uv) * 0.035 * contrast));
    float c1 = max(0.0, 1.0 - contrast * abs(1.0 - paint));
    float c2 = max(0.0, 1.0 - contrast * abs(paint));
    float c3 = 1.0 - min(1.0, c1 + c2);

    float3 col = tintA * c1 + tintB * c2 + base * c3;
    return half4(half3(dither(mix(base, col, strength), pos)), 1.0h);
}

// MARK: - Rayons
//
// Inspiré de « Light Rays » (React Bits), réécrit : leur version accumule des
// échantillons le long du rayon, ce qui multiplie le coût par pixel. Ici les
// faisceaux sont décrits analytiquement — un seul calcul, aucun échantillonnage.

[[ stitchable ]] half4 birthdayRays(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    // Source hors cadre, en haut à gauche : les faisceaux traversent l'écran
    // en diagonale au lieu de rayonner depuis un point visible.
    float2 origin = float2(-0.15, -0.25);
    float2 delta = uv - origin;
    float angle = atan2(delta.y, delta.x);
    float radius = length(delta);

    float t = time * 0.06;
    float beams = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float frequency = 9.0 + fi * 5.0;
        float ray = sin(angle * frequency + t * (1.0 + fi * 0.4) + fi * 2.1);
        beams += pow(max(ray, 0.0), 5.0) * (0.5 - fi * 0.12);
    }
    // Les faisceaux s'éteignent en s'éloignant de la source.
    beams *= exp(-radius * 1.5);

    float3 col = mix(base, tint, clamp(beams, 0.0, 1.0) * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Vagues

[[ stitchable ]] half4 birthdayWaves(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float t = time * 0.09;

    float3 col = base;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        // Fréquences non entières : les crêtes ne se réalignent jamais, la
        // houle ne se répète donc pas visiblement.
        float crest = 0.5
            + 0.09 * sin(uv.x * (3.1 + fi * 1.7) + t * (1.0 + fi * 0.35) + fi)
            + 0.05 * sin(uv.x * (7.3 - fi * 0.9) - t * 1.6 + fi * 2.4);
        float band = smoothstep(0.055, 0.0, abs(uv.y - crest + (fi - 1.5) * 0.16));
        col = mix(col, mix(tintA, tintB, fi / 3.0), band * strength * 0.75);
    }
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Grain

[[ stitchable ]] half4 birthdayGrain(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float t = time * 0.03;

    // Trois foyers lents : un dégradé de maillage, mais sans maillage.
    float a = exp(-length(uv - float2(0.2 + 0.1 * sin(t), 0.25 + 0.08 * cos(t * 1.3))) * 2.2);
    float b = exp(-length(uv - float2(0.85 + 0.07 * cos(t * 0.9), 0.4 + 0.1 * sin(t * 1.1))) * 2.4);
    float c = exp(-length(uv - float2(0.5 + 0.12 * sin(t * 0.7), 0.9 + 0.06 * cos(t))) * 2.0);

    float3 col = base;
    col = mix(col, tintA, clamp(a + c * 0.5, 0.0, 1.0) * strength);
    col = mix(col, tintB, clamp(b, 0.0, 1.0) * strength * 0.8);
    // Grain marqué : c'est lui qui donne la matière, comme un papier photo.
    col += (hash21(pos) - 0.5) * 0.06;
    return half4(half3(col), 1.0h);
}

// MARK: - Ondes

[[ stitchable ]] half4 birthdayRipple(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float2 center = float2(0.5 * safeSize.x / safeSize.y, 0.42);

    float radius = length(uv - center);
    float t = time * 0.35;
    // Les crêtes s'espacent en s'éloignant : des anneaux régulièrement
    // espacés donneraient une cible, pas une onde.
    float rings = sin(radius * 26.0 - t) * exp(-radius * 1.8);
    float shimmer = sin(radius * 52.0 - t * 1.7) * exp(-radius * 3.2) * 0.4;

    float intensity = clamp((rings + shimmer) * 0.5 + 0.5, 0.0, 1.0);
    float3 col = mix(base, tint, intensity * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Bokeh

[[ stitchable ]] half4 birthdayBokeh(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float t = time * 0.04;

    float3 col = base;
    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float2 seed = float2(fi * 12.9898, fi * 78.233);
        float2 anchor = float2(hash21(seed), hash21(seed + 3.7));
        // Chaque halo dérive à sa propre vitesse : sans cela l'ensemble
        // glisserait en bloc, comme une image qu'on translate.
        float2 drift = float2(sin(t * (0.6 + hash21(seed + 9.1)) + fi),
                              cos(t * (0.5 + hash21(seed + 4.3)) + fi * 1.7));
        float2 center = anchor * float2(safeSize.x / safeSize.y, 1.0) + drift * 0.08;
        float radius = 0.05 + hash21(seed + 1.3) * 0.11;

        float d = length(uv - center);
        // Bord net puis dégradé doux : c'est ce qui distingue un flou d'objectif
        // d'une simple tache floue.
        float disc = smoothstep(radius, radius * 0.55, d);
        float rim = smoothstep(radius, radius * 0.92, d) - smoothstep(radius * 0.92, radius * 0.7, d);
        float3 tone = mix(tintA, tintB, hash21(seed + 6.6));
        col += tone * (disc * 0.35 + max(rim, 0.0) * 0.25) * strength;
    }
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Éclats

[[ stitchable ]] half4 birthdayBurst(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;

    float3 col = base;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        // Chaque éclat a son propre cycle : ils ne partent jamais ensemble.
        float cycle = fract(time * 0.055 + fi * 0.27);
        float2 seed = float2(fi * 34.1, fi * 91.7);
        float2 center = float2(hash21(seed), hash21(seed + 2.2)) * float2(safeSize.x / safeSize.y, 1.0);

        float2 delta = uv - center;
        float radius = length(delta);
        float angle = atan2(delta.y, delta.x);

        float front = cycle * 0.55;
        // Anneau qui s'élargit et s'efface : la trace d'une gerbe.
        float ring = smoothstep(0.05, 0.0, abs(radius - front)) * (1.0 - cycle);
        float spokes = 0.55 + 0.45 * sin(angle * 14.0 + fi * 2.0);
        col += mix(tintA, tintB, fi / 3.0) * ring * spokes * strength * 0.8;
    }
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Marbre

[[ stitchable ]] half4 birthdayMarble(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float t = time * 0.02;

    // Bruit « en crêtes » : on replie la valeur autour de son sommet, ce qui
    // transforme des bosses molles en veines nettes.
    float2 p = uv * 3.0 + float2(t, -t * 0.6);
    float veins = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        float n = valueNoise(p);
        veins += amplitude * (1.0 - abs(n * 2.0 - 1.0));
        p *= 2.05;
        amplitude *= 0.55;
    }
    veins = pow(clamp(veins, 0.0, 1.0), 3.0);

    float3 col = mix(base, tint, veins * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Néon

[[ stitchable ]] half4 birthdayNeon(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength,
    float ink
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float t = time * 0.10;

    float3 glow = float3(0.0);
    float coverage = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float path = 0.5
            + 0.18 * sin(uv.x * 2.3 + t * (1.0 + fi * 0.5) + fi * 2.2)
            + 0.08 * sin(uv.x * 5.1 - t * 1.4 + fi);
        float d = abs(uv.y - path + (fi - 1.0) * 0.22);
        // Cœur très fin doublé d'un halo large : la signature d'un tube néon.
        float core = 0.004 / (d + 0.004);
        float halo = 0.05 / (d + 0.05);
        float weight = core * 0.5 + halo * 0.22;
        glow += mix(tintA, tintB, fi / 2.0) * weight;
        coverage += weight;
    }
    float3 paint = glow / max(coverage, 0.0001);
    float3 col = applyInk(base, base + glow * strength, paint, coverage * strength * 1.3, ink);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Poussière

[[ stitchable ]] half4 birthdayDust(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength,
    float ink
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float t = time * 0.03;

    // Grille de cellules : une seule particule est évaluée par pixel, quel que
    // soit leur nombre à l'écran.
    float2 grid = uv * 14.0;
    float2 cell = floor(grid);
    float2 local = fract(grid) - 0.5;

    float seed = hash21(cell);
    float2 offset = float2(sin(t * 6.0 + seed * 30.0), cos(t * 5.0 + seed * 21.0)) * 0.22;
    float d = length(local - offset);
    float twinkle = 0.5 + 0.5 * sin(t * 22.0 + seed * 60.0);
    float grainSize = 0.03 + seed * 0.05;
    float spark = smoothstep(grainSize, 0.0, d) * twinkle * step(0.55, seed);

    float3 col = applyInk(base, base + tint * spark * strength * 1.4,
                          tint, spark * strength * 2.0, ink);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Spirale

[[ stitchable ]] half4 birthdaySpiral(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = (pos - 0.5 * safeSize) / min(safeSize.x, safeSize.y);
    float radius = length(uv);
    float angle = atan2(uv.y, uv.x);
    float t = time * 0.08;

    // L'angle décalé par le logarithme du rayon donne une spirale véritable,
    // dont les bras s'écartent en s'éloignant du centre.
    float arms = sin(angle * 2.0 + log(radius + 0.08) * 6.0 - t * 3.0);
    float intensity = smoothstep(-0.2, 0.9, arms) * exp(-radius * 1.4);

    float3 col = mix(base, mix(tintA, tintB, clamp(radius * 1.6, 0.0, 1.0)), intensity * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Caustiques

[[ stitchable ]] half4 birthdayCaustics(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float t = time * 0.12;

    // Trois ondes croisées : leurs interférences dessinent le réseau lumineux
    // qu'on voit au fond d'une piscine.
    float w = sin(uv.x * 9.0 + t) + sin(uv.y * 11.0 - t * 1.2)
            + sin((uv.x + uv.y) * 7.0 + t * 0.8);
    float light = pow(clamp(w * 0.25 + 0.5, 0.0, 1.0), 6.0);

    float3 col = mix(base, tint, light * strength * 1.6);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Trame

[[ stitchable ]] half4 birthdayDotGrid(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    uv.x *= safeSize.x / safeSize.y;
    float t = time * 0.20;

    float2 grid = uv * 22.0;
    float2 cell = floor(grid);
    float2 local = fract(grid) - 0.5;

    // Une onde traverse la trame : les points grossissent sur son passage.
    float wave = sin(length(cell * 0.16 - float2(1.4, 0.9)) * 3.0 - t);
    float radius = 0.10 + 0.16 * (wave * 0.5 + 0.5);
    float dot = smoothstep(radius, radius * 0.35, length(local));

    float3 col = mix(base, tint, dot * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Boréale
//
// Portage du composant « Aurora » de React Bits, bruit simplex compris. Sa
// hauteur passe par une exponentielle, ce qui donne un bord franc en bas et un
// dégradé long vers le haut — l'inverse d'un dégradé symétrique.

static float3 permute289(float3 x) {
    return fmod(((x * 34.0) + 1.0) * x, 289.0);
}

static float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439,
                            -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = fmod(i, 289.0);

    float3 p = permute289(permute289(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;

    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

[[ stitchable ]] half4 birthdayBoreal(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    // Repère inversé : dans le shader d'origine l'origine est en bas.
    float y = 1.0 - uv.y;

    float3 ramp = mix(tintA, tintB, smoothstep(0.0, 1.0, uv.x));

    float height = snoise(float2(uv.x * 2.0 + time * 0.1, time * 0.25)) * 0.5;
    height = exp(height);
    height = (y * 2.0 - height + 0.2);
    float intensity = 0.6 * height;

    float alpha = smoothstep(-0.05, 0.45, intensity);
    float3 col = mix(base, intensity * ramp, clamp(alpha, 0.0, 1.0) * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}

// MARK: - Foudre
//
// Portage du composant « Lightning » de React Bits. L'original empile dix
// octaves de bruit ; cinq suffisent ici pour une décharge crédible, et divisent
// le coût par deux sur un écran de téléphone.

static float2x2 rotate2d(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return float2x2(c, -s, s, c);
}

static float lightningFbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * valueNoise(p);
        p = rotate2d(0.45) * p;
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

[[ stitchable ]] half4 birthdayLightning(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = 2.0 * (pos / safeSize) - 1.0;
    uv.x *= safeSize.x / safeSize.y;

    uv += 2.0 * lightningFbm(uv * 1.1 + 0.8 * time * 0.35) - 1.0;

    float dist = abs(uv.x);
    // La lueur naît d'une division par la distance : le trait est infiniment
    // fin en son centre et se dissout latéralement.
    float3 col = tint * (0.045 / max(dist, 0.012));
    col = clamp(col, 0.0, 1.4);

    float glow = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
    return half4(half3(dither(mix(base, col, glow * strength), pos)), 1.0h);
}

// MARK: - Grainé
//
// Portage du composant « Grainient » de React Bits. Trois plans de couleur
// mélangés selon un axe incliné, l'ensemble tordu par deux sinusoïdes croisées
// et couvert d'un grain marqué. L'interaction souris de l'original est retirée.

static float2 grainHash(float2 p) {
    p = float2(dot(p, float2(2127.1, 81.17)), dot(p, float2(1269.5, 283.37)));
    return fract(sin(p) * 43758.5453);
}

static float gradientNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float n = mix(
        mix(dot(-1.0 + 2.0 * grainHash(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
            dot(-1.0 + 2.0 * grainHash(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
        mix(dot(-1.0 + 2.0 * grainHash(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
            dot(-1.0 + 2.0 * grainHash(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x),
        u.y);
    return 0.5 + 0.5 * n;
}

[[ stitchable ]] half4 birthdayGrainient(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tintA,
    float3 tintB,
    float3 base,
    float strength
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float ratio = safeSize.x / safeSize.y;
    float t = time * 0.12;

    float2 tuv = uv - 0.5;
    // La rotation est pilotée par le bruit : le dégradé pivote lentement sans
    // jamais revenir exactement au même angle.
    float degree = gradientNoise(float2(t * 0.1, tuv.x * tuv.y) * 6.0);
    tuv.y *= 1.0 / ratio;
    float angle = ((degree - 0.5) * 60.0 + 180.0) * 0.017453292;
    tuv = rotate2d(angle) * tuv;
    tuv.y *= ratio;

    tuv.x += sin(tuv.y * 6.0 + t) / 12.0;
    tuv.y += sin(tuv.x * 9.0 + t) / 6.0;

    float blendX = tuv.x;
    float3 layer1 = mix(base, tintB, smoothstep(-0.45, 0.35, blendX));
    float3 layer2 = mix(tintB, tintA, smoothstep(-0.45, 0.35, blendX));
    float3 col = mix(layer1, layer2, smoothstep(0.65, -0.45, tuv.y));

    // Grain appuyé : c'est la signature du procédé, il ne doit pas être discret.
    col += (hash21(uv * 320.0) - 0.5) * 0.10;

    return half4(half3(mix(base, col, strength)), 1.0h);
}

// MARK: - Grille
//
// Portage du composant « Ripple Grid » de React Bits, sans l'interaction
// souris. Une onde part du centre et déforme la grille en la traversant.

[[ stitchable ]] half4 birthdayRippleGrid(
    float2 pos,
    half4 color,
    float2 size,
    float time,
    float3 tint,
    float3 base,
    float strength
) {
    const float pi = 3.141592;
    float2 safeSize = max(size, float2(1.0));
    float2 uv = (pos / safeSize) * 2.0 - 1.0;
    uv.x *= safeSize.x / safeSize.y;

    float t = time * 0.35;
    float dist = length(uv);
    // L'onde dépend de la distance au centre : elle s'y propage au lieu de
    // balayer l'écran d'un bord à l'autre.
    float func = sin(pi * (t - dist));
    float2 rippleUv = uv + uv * func * 0.06;

    float2 a = sin(8.0 * 0.5 * pi * rippleUv - pi / 2.0);
    float2 b = abs(a);
    float2 smoothB = float2(smoothstep(0.0, 0.5, b.x), smoothstep(0.0, 0.5, b.y));

    float thickness = 22.0;
    float3 grid = float3(0.0);
    grid += exp(-thickness * smoothB.x * (0.8 + 0.5 * sin(pi * t)));
    grid += exp(-thickness * smoothB.y);
    grid += 0.35 * exp(-(thickness / 4.0) * sin(smoothB.x));
    grid += 0.35 * exp(-(thickness / 3.0) * smoothB.y);

    // Double atténuation : par la distance au centre, puis par une vignette,
    // pour que la grille ne heurte jamais les bords de l'écran.
    float fade = exp(-2.0 * clamp(pow(dist, 1.6), 0.0, 1.0));
    float vignette = clamp(1.0 - pow(length(pos / safeSize - 0.5) * 2.0, 2.0), 0.0, 1.0);

    float intensity = clamp(length(grid) * fade * vignette * 0.45, 0.0, 1.0);
    float3 col = mix(base, tint, intensity * strength);
    return half4(half3(dither(col, pos)), 1.0h);
}
