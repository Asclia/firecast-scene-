#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Renderiza uma prévia (PNG) de como as operações gráficas criadas pelos
plugins ficam no tabuleiro, usando o SDK simulado do test_harness.

  python3 tools/render_preview.py saida.png
"""
import os
import sys

import cairosvg
from lupa import lua54
from svgelements import Path, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_harness as TH  # noqa: E402

SCENARIO = r'''
local scene = MOCK.newScene()
local cs = 1.5
local function tk(a, b, n, name, fof)
  local t = scene:addToken(a * cs, b * cs, n * cs, n * cs); t.name = name; t.friendOrFoe = fof or "foe"; return t
end
local guerreiro = tk(3, 9, 1, "Guerreiro", "friend")
local ogro = tk(9, 8, 2, "Ogro", "foe")
local goblin = tk(4, 3, 1, "Goblin", "foe")
local paladino = tk(15, 9, 1, "Paladino", "friend")
local dragao = tk(17, 2, 3, "Dragão", "foe")
for _, fn in ipairs(SceneLib.plugins) do fn(scene, {}) end
MOCK.runTimers()

-- condições
FSCOND.setList(scene, goblin, {{id="shaken", r="3", h="0"}, {id="prone", r="", h="0"}, {id="blinded", r="2", h="0"}, {id="bleed", r="", h="0"}})
FSCOND.setList(scene, ogro, {{id="entangled", r="5", h="0"}, {id="ff_slow", r="", h="0"}})
FSCOND.setList(scene, guerreiro, {{id="haste", r="10", h="0"}, {id="bless", r="", h="0"}, {id="custom", n="Marcado", r="2", c="#00838F", h="0"}})

-- alcance: ogro (grande, alto) e guerreiro com arma de haste
scene.userData.fsReachView = "always"
FSREACH.setRecord(scene, ogro, {preset="tall", weapon="0", diag10="1", autoColor="1", diag="pf"})
FSREACH.setRecord(scene, guerreiro, {preset="tall", weapon="1", adjacent="0", diag10="1", autoColor="1", diag="pf"})

-- auras: paladino (aura de coragem 10 ft), dragão (cone 30 ft suave seguindo direção)
local function aura(t, slot, r)
  local slots = FSAURA.getSlots(t); slots[slot] = r
  t.userData.fsAuras = FSC.encodeList(slots); FSAURA.renderToken(scene, t, slots)
end
aura(paladino, 1, {on="1", name="Aura de Coragem", shape="emanation", radius="10 ft", dir="0", color="#FFD54F", fill="0.15", mode="grid", diag="pf", show="always", gm="0"})
aura(dragao, 1, {on="1", name="Sopro", shape="cone", radius="30 ft", dir="225", color="#FF5722", fill="0.15", mode="smooth", diag="pf", show="always", gm="0"})

-- áreas de magia: bola de fogo 20 ft (grid) e cone 15 ft
local cfg1 = {shape="burst", size="20 ft", width="", mode="grid", diag="pf", color="#FF6D00", fill="0.3", name="Bola de Fogo", gm=false}
local g1 = FSSA.compute(scene, cfg1, 9, 17, 0); FSSA.create(scene, cfg1, g1, 9, 17, 0)
local cfg2 = {shape="cone", size="15 ft", width="", mode="grid", diag="pf", color="#E040FB", fill="0.3", name="Spray de Cores", gm=false}
local g2 = FSSA.compute(scene, cfg2, 18, 15, 45); FSSA.create(scene, cfg2, g2, 18, 15, 45)
local cfg3 = {shape="line", size="40 ft", width="5 ft", mode="grid", diag="pf", color="#40C4FF", fill="0.3", name="Relâmpago", gm=false}
local g3 = FSSA.compute(scene, cfg3, 21, 21, 300); FSSA.create(scene, cfg3, g3, 21, 21, 300)

-- exporta
EXPORT = {}
for _, it in ipairs(scene._items) do
  local e = {kind = it.objectType, x = it.x, y = it.y, w = it.width, h = it.height, name = it.name, ops = {}}
  for i = 0, it.canvas.opCount - 1 do
    local op = it.canvas:getOp(i)
    e.ops[#e.ops+1] = {kind = op.objectType, name = op.name, x = op.x, y = op.y, w = op.width, h = op.height,
      xm = op.xMetric, ym = op.yMetric, xo = op.xOrigin or 0, yo = op.yOrigin or 0, z = op.z or 0,
      data = op.data, fill = op.color, stroke = op.strokeColor, ss = op.strokeSize or 0, dash = op.strokeDash,
      text = op.text, ooo = op.outOfOrderMode, trig = (op.drawingTrigger and #op.drawingTrigger or 0)}
  end
  EXPORT[#EXPORT+1] = e
end
'''

PX = 40  # pixels por metro (1 quadrado = 60 px)


def color(c):
    if not c:
        return "none", 0
    c = c.lstrip("#")
    if len(c) == 8:
        return "#" + c[:6], int(c[6:8], 16) / 255
    return "#" + c[:6], 1.0


def main(out):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(TH.MOCK)
    L.execute("require = function() end")
    order = {
        "SceneSuite_Conditions": ["fsCommon.lua", "condData.lua", "conditions.lua"],
        "SceneSuite_Auras": ["fsCommon.lua", "auras.lua"],
        "SceneSuite_Reach": ["fsCommon.lua", "reach.lua"],
        "SceneSuite_SpellAreas": ["fsCommon.lua", "spellAreas.lua"],
    }
    for pname, files in order.items():
        for fn in files:
            L.execute(open(os.path.join(TH.P, pname, fn), encoding="utf-8").read())
        for lfm in os.listdir(os.path.join(TH.P, pname)):
            if lfm.endswith(".lfm"):
                name, fcode = TH.lfm_script(os.path.join(TH.P, pname, lfm))
                L.globals().MOCK.formScripts[name] = L.eval(fcode)
    L.execute(SCENARIO)
    items = L.globals().EXPORT
    cs = 1.5
    W, H = int(26 * cs * PX), int(24 * cs * PX)

    layers = {"below": [], "item": [], "above": []}
    for i in range(1, len(items) + 1):
        it = items[i]
        ix, iy, iw, ih = it.x, it.y, it.w, it.h
        if it.kind == "token":
            cx, cy, r = (ix + iw / 2) * PX, (iy + ih / 2) * PX, iw / 2 * PX * 0.92
            fof = "#C62828" if it.name in ("Ogro", "Goblin", "Dragão") else "#1565C0"
            layers["item"].append((0, '<circle cx="%f" cy="%f" r="%f" fill="%s" stroke="#111" stroke-width="3"/>'
                                   '<text x="%f" y="%f" fill="#fff" font-size="13" font-family="sans-serif" '
                                   'text-anchor="middle">%s</text>' % (cx, cy, r, fof, cx, cy + 4, it.name)))
        ops = it.ops
        for k in range(1, len(ops) + 1):
            op = ops[k]
            if op.xm == "cellMetric":
                x = ix + op.xo * iw + op.x * cs
                y = iy + op.yo * ih + op.y * cs
                w, h = op.w * cs, op.h * cs
            else:
                x, y, w, h = ix + op.x * iw, iy + op.y * ih, op.w * iw, op.h * ih
            x, y, w, h = x * PX, y * PX, w * PX, h * PX
            dest = "below" if op.ooo == "beforeOwnerLayer" or it.kind == "userDrawing" else "above"
            if op.kind == "opPath":
                pth = Path(op.data)
                bb = pth.bbox()
                bw, bh = max(bb[2] - bb[0], 1e-6), max(bb[3] - bb[1], 1e-6)
                sx, sy = w / bw, h / bh
                pth = pth * Matrix("translate(%f %f) scale(%f %f) translate(%f %f)" % (x, y, sx, sy, -bb[0], -bb[1]))
                fc, fa = color(op.fill)
                sc, sa = color(op.stroke)
                dash = ' stroke-dasharray="6,4"' if op.dash == "dash" else ""
                layers[dest].append((op.z, '<path d="%s" fill="%s" fill-opacity="%f" stroke="%s" stroke-opacity="%f" '
                                     'stroke-width="%f" fill-rule="nonzero"%s/>'
                                     % (pth.d(), fc, fa, sc, sa, op.ss, dash)))
            elif op.kind == "opText":
                hov = op.trig > 0
                layers[dest].append((op.z, '<text x="%f" y="%f" fill="#fff" font-size="%f" font-weight="bold" '
                                     'font-family="sans-serif" text-anchor="middle" opacity="%s">%s</text>'
                                     % (x + w / 2, y + h * 0.8, h * 0.8, "0.85" if hov else "1", op.text)))
    grid = []
    for a in range(27):
        grid.append('<line x1="%f" y1="0" x2="%f" y2="%d" stroke="#ffffff22"/>' % (a * cs * PX, a * cs * PX, H))
    for b in range(25):
        grid.append('<line x1="0" y1="%f" x2="%d" y2="%f" stroke="#ffffff22"/>' % (b * cs * PX, W, b * cs * PX))
    body = ['<rect width="100%" height="100%" fill="#3b4a3a"/>'] + grid
    for key in ("below", "item", "above"):
        body += [s for _, s in sorted(layers[key], key=lambda t: t[0])]
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">%s</svg>' % (W, H, "".join(body))
    cairosvg.svg2png(bytestring=svg.encode("utf-8"), write_to=out)
    print("salvo em", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "preview.png")
