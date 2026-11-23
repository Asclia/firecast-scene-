#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build da Scene Suite.

  python3 tools/build.py            -> gera arquivos, copia a lib comum, valida
  python3 tools/build.py --package  -> idem + gera dist/*.zip (um por plugin + suíte completa)

O que ele faz:
  1. Copia common/fsCommon.lua para dentro de cada plugin (cada plugin é uma
     sandbox isolada no Firecast; não há como compartilhar arquivos em tempo
     de execução).
  2. Gera, para o plugin de Condições: condData.lua (ícones vetoriais),
     frmFSConditions.lfm (o formulário) e os PNGs dos ícones.
  3. Gera os PNGs dos botões de ferramenta de todos os plugins.
  4. Valida: XML bem formado, sintaxe Lua (lupa / Lua 5.4) de todos os .lua e
     dos <script>/<event> dos .lfm.

Dependências (apenas para quem for rodar o build): cairosvg, pillow,
svgelements, lupa. O resultado do build já está commitado no repositório, então
para apenas usar os plugins basta o rdk do Firecast.
"""
import io
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import conditions_def as CD  # noqa: E402

ICONS_DIR = os.path.join(ROOT, "assets", "icons")       # SVGs do game-icons usados (vendored)
PLUGINS_DIR = os.path.join(ROOT, "plugins")
COMMON = os.path.join(ROOT, "common", "fsCommon.lua")
GAME_ICONS_SRC = os.environ.get("GAME_ICONS_DIR")         # opcional: clone de github.com/game-icons/icons

PLUGINS = {
    "SceneSuite_Conditions": {
        "tools": {
            "tool_cond": "lorc/hourglass",
            "tool_next": "lorc/sands-of-time",
            "tool_undo": "delapouite/backward-time",
            "tool_cfg": "lorc/cog",
            "tool_clear": "delapouite/broom",
        },
    },
    "SceneSuite_Auras": {
        "tools": {
            "tool_aura": "lorc/aura",
            "tool_refresh": "lorc/cycle",
            "tool_clear": "delapouite/broom",
        },
    },
    "SceneSuite_Reach": {
        "tools": {
            "tool_reach": "lorc/halberd",
            "tool_view": "delapouite/eye-target",
            "tool_clear": "delapouite/broom",
        },
    },
    "SceneSuite_SpellAreas": {
        "tools": {
            "tool_area": "lorc/fire-zone",
            "tool_clear": "delapouite/broom",
        },
    },
    "SceneSuite_Weather": {
        "tools": {
            "tool_weather": "lorc/heavy-rain",
            "tool_local": "delapouite/sun-cloud",
        },
    },
    "SceneSuite_HP": {
        "tools": {
            "tool_hp": "zeromancer/heart-plus",
        },
    },
    "SceneSuite_Combat": {
        "tools": {
            "tool_combat": "lorc/crossed-swords",
            "tool_next": "lorc/sands-of-time",
            "tool_prev": "delapouite/backward-time",
            "tool_add": "delapouite/human-target",
            "tool_roll": "delapouite/dice-twenty-faces-twenty",
            "tool_end": "delapouite/broom",
        },
    },
    "SceneSuite_Light": {
        "tools": {
            "tool_light": "lorc/sun",
            "tool_torch": "delapouite/torch",
        },
    },
    "SceneSuite_Triggers": {
        "tools": {
            "tool_trigger": "lorc/lightning-trio",
            "tool_door": "lorc/wooden-door",
            "tool_edit": "delapouite/pencil",
            "tool_group": "lorc/cubes",
        },
    },
    "SceneSuite_TokenBar": {
        "tools": {
            "tool_bar": "delapouite/human-target",
            "tool_request": "delapouite/dice-twenty-faces-twenty",
        },
    },
    "SceneSuite_SpellFX": {
        "tools": {
            "tool_fx": "lorc/fireball",
            "tool_stop": "delapouite/broom",
        },
    },
}


# ---------------------------------------------------------------------------
# Ícones
# ---------------------------------------------------------------------------

def icon_svg_path(name):
    p = os.path.join(ICONS_DIR, name + ".svg")
    if not os.path.exists(p):
        if GAME_ICONS_SRC and os.path.exists(os.path.join(GAME_ICONS_SRC, name + ".svg")):
            os.makedirs(os.path.dirname(p), exist_ok=True)
            shutil.copy(os.path.join(GAME_ICONS_SRC, name + ".svg"), p)
        else:
            raise SystemExit("Ícone não encontrado: %s (defina GAME_ICONS_DIR)" % name)
    return p


def icon_path_d(name):
    """Retorna o 'd' do path do glifo (o último path do SVG do game-icons)."""
    txt = open(icon_svg_path(name), encoding="utf-8").read()
    ds = re.findall(r'<path[^>]*\sd="([^"]+)"', txt)
    if not ds:
        raise SystemExit("SVG sem path: " + name)
    # o primeiro path costuma ser o fundo "M0 0h512v512H0z"
    ds = [d for d in ds if not re.match(r"^\s*M0 0h512v512H0z\s*$", d)]
    return " ".join(ds)


def normalize_path(d):
    """Reescreve o path com comandos absolutos M/L/C/Q/Z e coordenadas inteiras.
    Arcos viram curvas cúbicas (evita diferenças de parser e reduz o tamanho).
    Retorna (d_normalizado, bbox) - bbox inclui pontos de controle."""
    from svgelements import Path, Move, Line, CubicBezier, QuadraticBezier, Arc, Close

    path = Path(d)
    out = []
    xs, ys = [], []

    def P(pt):
        x, y = int(round(pt.x)), int(round(pt.y))
        xs.append(x)
        ys.append(y)
        return "%d %d" % (x, y)

    for seg in path:
        if isinstance(seg, Move):
            out.append("M" + P(seg.end))
        elif isinstance(seg, Line):
            out.append("L" + P(seg.end))
        elif isinstance(seg, CubicBezier):
            out.append("C" + P(seg.control1) + " " + P(seg.control2) + " " + P(seg.end))
        elif isinstance(seg, QuadraticBezier):
            out.append("Q" + P(seg.control) + " " + P(seg.end))
        elif isinstance(seg, Arc):
            for c in seg.as_cubic_curves():
                out.append("C" + P(c.control1) + " " + P(c.control2) + " " + P(c.end))
        elif isinstance(seg, Close):
            out.append("Z")
    s = "".join(out)
    return s, (min(xs), min(ys), max(xs), max(ys))


def render_icon_png(name, out_path, size, bg=None, fg="#FFFFFF", pad=0.16, shape="circle"):
    import cairosvg
    from PIL import Image, ImageDraw

    txt = open(icon_svg_path(name), encoding="utf-8").read()
    # tira o fundo e pinta o glifo
    txt = re.sub(r'<path d="M0 0h512v512H0z"\s*/>', "", txt)
    txt = re.sub(r'fill="#fff"', 'fill="%s"' % fg, txt)
    inner = int(size * (1 - 2 * pad))
    png = cairosvg.svg2png(bytestring=txt.encode("utf-8"), output_width=inner, output_height=inner)
    glyph = Image.open(io.BytesIO(png)).convert("RGBA")

    scale = 4
    img = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    if bg:
        dr = ImageDraw.Draw(img)
        if shape == "circle":
            dr.ellipse((2, 2, size * scale - 3, size * scale - 3), fill=bg, outline=(0, 0, 0, 160), width=scale * 2)
        else:
            dr.rounded_rectangle((2, 2, size * scale - 3, size * scale - 3), radius=size * scale // 5,
                                 fill=bg, outline=(0, 0, 0, 160), width=scale * 2)
    img = img.resize((size, size), Image.LANCZOS)
    off = (size - inner) // 2
    img.alpha_composite(glyph, (off, off))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    img.save(out_path)


# ---------------------------------------------------------------------------
# Plugin de Condições: dados + formulário
# ---------------------------------------------------------------------------

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def gen_conditions():
    pdir = os.path.join(PLUGINS_DIR, "SceneSuite_Conditions")
    lines = [
        "-- ARQUIVO GERADO por tools/build.py a partir de tools/conditions_def.py. NÃO EDITE À MÃO.",
        "-- Ícones vetoriais: game-icons.net (CC BY 3.0) - ver CREDITS.md",
        "FSCOND_DATA = {};",
        "FSCOND_DATA.groups = {",
    ]
    for gid, gname in CD.GROUPS:
        lines.append("\t{id = %s, name = %s}," % (lua_str(gid), lua_str(gname)))
    lines.append("};")
    lines.append("FSCOND_DATA.list = {")

    entries = list(CD.CONDITIONS) + [("custom", "Personalizada", "Custom", "hidden", "magic", CD.CUSTOM_ICON)]
    cache = {}
    for cid, pt, en, grp, cat, icon in entries:
        if icon not in cache:
            cache[icon] = normalize_path(icon_path_d(icon))
        d, bb = cache[icon]
        color = CD.CATEGORY_COLORS[cat]
        lines.append(
            "\t{id = %s, name = %s, en = %s, group = %s, color = %s, bbox = {%d, %d, %d, %d},\n\t path = %s},"
            % (lua_str(cid), lua_str(pt), lua_str(en), lua_str(grp), lua_str(color),
               bb[0], bb[1], bb[2], bb[3], lua_str(d)))
        render_icon_png(icon, os.path.join(pdir, "images", "cond", cid + ".png"), 40, bg=color)
    lines.append("};")
    with open(os.path.join(pdir, "condData.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    gen_conditions_form(pdir)


def xml_attr(s):
    return (s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;").replace(">", "&gt;"))


def gen_conditions_form(pdir):
    tiles = []
    for gid, gname in CD.GROUPS:
        tiles.append('\t\t\t\t<flowPart name="grpHdr_%s" height="30" minWidth="240" maxWidth="5000" margins="{left=4, right=4, top=8}">\n'
                     '\t\t\t\t\t<label align="client" text="%s" fontSize="15" fontStyle="bold" fontColor="#FFCC66"/>\n'
                     '\t\t\t\t\t<horzLine align="bottom" strokeColor="#FFCC6670"/>\n'
                     '\t\t\t\t</flowPart>\n\t\t\t\t<flowLineBreak/>' % (gid, xml_attr(gname)))
        for cid, pt, en, grp, cat, icon in CD.CONDITIONS:
            if grp != gid:
                continue
            label = pt if pt == en else "%s (%s)" % (pt, en)
            tiles.append(
                '\t\t\t\t<flowPart name="flp_%(id)s" width="296" height="30" margins="{left=2, right=2, top=1, bottom=1}">\n'
                '\t\t\t\t\t<image left="2" top="3" width="24" height="24" src="/images/cond/%(id)s.png" hitTest="false"/>\n'
                '\t\t\t\t\t<checkBox name="cbx_%(id)s" left="30" top="3" width="150" height="24" fontSize="12" text="%(label)s"/>\n'
                '\t\t\t\t\t<edit name="edt_%(id)s" left="182" top="3" width="38" height="24" fontSize="12" textPrompt="&#8734;" horzTextAlign="center"/>\n'
                '\t\t\t\t\t<comboBox name="cmbU_%(id)s" left="222" top="3" width="70" height="24" fontSize="11"\n'
                '\t\t\t\t\t          items="{\'rodadas\', \'min\', \'horas\'}" values="{\'r\', \'min\', \'h\'}" value="r"/>\n'
                '\t\t\t\t</flowPart>' % {"id": cid, "label": xml_attr(label)})
        tiles.append('\t\t\t\t<flowLineBreak/>')

    tpl = open(os.path.join(ROOT, "tools", "templates", "frmFSConditions.lfm.tpl"), encoding="utf-8").read()
    out = tpl.replace("<!--@TILES@-->", "\n".join(tiles))
    with open(os.path.join(pdir, "frmFSConditions.lfm"), "w", encoding="utf-8", newline="\n") as f:
        f.write(out)


# ---------------------------------------------------------------------------
# Tracker de combate: janela acoplável + painel no Scene (mesmo template)
# ---------------------------------------------------------------------------

COMBAT_ROWS = 40


def gen_combat():
    pdir = os.path.join(PLUGINS_DIR, "SceneSuite_Combat")
    tpl = open(os.path.join(ROOT, "tools", "templates", "frmFSCombat.lfm.tpl"), encoding="utf-8").read()
    rows = []
    for i in range(1, COMBAT_ROWS + 1):
        rows.append(
            '\t\t<layout name="row%(i)d" align="top" height="40" margins="{bottom=2, right=4}" visible="false">\n'
            '\t\t\t<rectangle name="rowBg%(i)d" align="client" color="#FFFFFF0D" xradius="5" yradius="5" strokeSize="0" hitTest="false"/>\n'
            '\t\t\t<image name="rowImg%(i)d" left="3" top="3" width="34" height="34" style="proportional" hitTest="false"/>\n'
            '\t\t\t<button name="rowMenu%(i)d" align="right" width="28" text="..." margins="{top=6, bottom=6, right=3}" onClick="self:rowMenu(%(i)d)"/>\n'
            '\t\t\t<edit name="rowInit%(i)d" align="right" width="46" horzTextAlign="center" fontSize="14" fontStyle="bold" textPrompt="-" margins="{top=6, bottom=6, right=3}" onChange="self:rowInit(%(i)d)"/>\n'
            '\t\t\t<label name="rowName%(i)d" align="client" margins="{left=42}" vertTextAlign="center" wordWrap="false" textTrimming="character"/>\n'
            '\t\t</layout>' % {"i": i})
    body = tpl.replace("@ROWS@", "\n".join(rows)).replace("@MAX@", str(COMBAT_ROWS))
    variants = {
        "frmFSCombatDock.lfm": (
            '<form name="frmFSCombatDock" formType="tablesDock" dataType="SceneSuite.Combat.Dock" title="Combate" align="client" theme="dark">',
            "</form>", ""),
        "frmFSCombatPanel.lfm": (
            '<popupForm name="frmFSCombatPanel" width="300" height="420" drawContainer="true" resizable="true" placement="right" cancelable="false">',
            "</popupForm>",
            '<button align="right" width="28" text="X" onClick="self:doClose()"/>'),
    }
    for fn, (open_tag, close_tag, close_btn) in variants.items():
        out = body.replace("@ROOT_OPEN@", open_tag).replace("@ROOT_CLOSE@", close_tag).replace("@CLOSE_BUTTON@", close_btn)
        with open(os.path.join(pdir, fn), "w", encoding="utf-8", newline="\n") as f:
            f.write(out)


# ---------------------------------------------------------------------------
# Ícones de ferramentas
# ---------------------------------------------------------------------------

def gen_tool_icons():
    for pname, cfg in PLUGINS.items():
        for fname, icon in cfg["tools"].items():
            render_icon_png(icon, os.path.join(PLUGINS_DIR, pname, "images", fname + ".png"), 64,
                            bg=(38, 50, 56, 235), pad=0.14, shape="round")


# ---------------------------------------------------------------------------
# Lib comum
# ---------------------------------------------------------------------------

def sync_common():
    for pname in PLUGINS:
        dst = os.path.join(PLUGINS_DIR, pname, "fsCommon.lua")
        shutil.copy(COMMON, dst)


# ---------------------------------------------------------------------------
# Validação
# ---------------------------------------------------------------------------

def lua_check(code, chunkname):
    from lupa import lua54
    L = lua54.LuaRuntime()
    fn = L.eval("function(src, name) local f, err = load(src, name, 't'); return err end")
    err = fn(code, chunkname)
    return err


def validate():
    errors = 0
    for pname in PLUGINS:
        pdir = os.path.join(PLUGINS_DIR, pname)
        for dirpath, _, files in os.walk(pdir):
            if os.sep + "output" in dirpath or os.sep + "sdk" in dirpath:
                continue
            for fn in files:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ROOT)
                if fn.endswith(".lua"):
                    err = lua_check(open(full, encoding="utf-8").read(), "@" + rel)
                    if err:
                        print("ERRO Lua:", err)
                        errors += 1
                elif fn.endswith(".lfm") or fn == "module.xml":
                    raw = open(full, encoding="utf-8").read()
                    try:
                        root = ET.fromstring(raw.encode("utf-8"))
                    except ET.ParseError as e:
                        print("ERRO XML %s: %s" % (rel, e))
                        errors += 1
                        continue
                    if fn.endswith(".lfm"):
                        names = {}
                        for el in root.iter():
                            n = el.get("name")
                            if n:
                                if n in names:
                                    print("ERRO %s: nome duplicado %s" % (rel, n))
                                    errors += 1
                                names[n] = True
                            if el.tag in ("script", "event"):
                                code = el.text or ""
                                if el.tag == "event":
                                    code = "local function __ev(...)\n" + code + "\nend"
                                err = lua_check(code, "@%s<%s %s>" % (rel, el.tag, el.get("name", "")))
                                if err:
                                    print("ERRO Lua:", err)
                                    errors += 1
                            for attr, val in el.attrib.items():
                                if attr.startswith("on"):
                                    err = lua_check("local function __ev(...) " + val + " end", "@%s %s" % (rel, attr))
                                    if err:
                                        print("ERRO Lua:", err)
                                        errors += 1
    return errors


# ---------------------------------------------------------------------------
# Pacotes
# ---------------------------------------------------------------------------

def package():
    dist = os.path.join(ROOT, "dist")
    os.makedirs(dist, exist_ok=True)
    suite = zipfile.ZipFile(os.path.join(dist, "SceneSuite_completa.zip"), "w", zipfile.ZIP_DEFLATED)
    for pname in PLUGINS:
        pdir = os.path.join(PLUGINS_DIR, pname)
        z = zipfile.ZipFile(os.path.join(dist, pname + ".zip"), "w", zipfile.ZIP_DEFLATED)
        for dirpath, _, files in os.walk(pdir):
            if os.sep + "output" in dirpath or os.sep + "sdk" in dirpath:
                continue
            for fn in files:
                full = os.path.join(dirpath, fn)
                arc = os.path.join(pname, os.path.relpath(full, pdir))
                z.write(full, arc)
                suite.write(full, os.path.join("plugins", arc))
        z.close()
    for extra in ("README.md", "CREDITS.md", "instalar_todos.bat"):
        p = os.path.join(ROOT, extra)
        if os.path.exists(p):
            suite.write(p, extra)
    suite.close()
    print("Pacotes em", dist)


def main():
    sync_common()
    gen_conditions()
    gen_combat()
    gen_tool_icons()
    errs = validate()
    if errs:
        print("%d erro(s) encontrados" % errs)
        sys.exit(1)
    print("OK - build e validação sem erros")
    if "--package" in sys.argv:
        package()


if __name__ == "__main__":
    main()
