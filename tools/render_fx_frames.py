#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Grava quadros das animações e do clima (via SDK simulado) e monta uma
folha de contatos PNG para conferência visual.

  python3 tools/render_fx_frames.py fx.png [ids...]
"""
import os
import sys

from lupa import lua54
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_harness as TH  # noqa: E402

RECORDER = r'''
REC = {}
local vp = SCENE.viewport
local cur = {fill = "#FFFFFF", draw = "#FFFFFF", th = 1}
vp.prepareFill = function(self, c) cur.fill = c end
vp.prepareDraw = function(self, c, th) cur.draw = c; cur.th = th or 1 end
vp.fillRect = function(self, l, t, r, b, a) REC[#REC+1] = {"rect", cur.fill, a or 1, l, t, r, b} end
vp.fillEllipse = function(self, l, t, r, b, a) REC[#REC+1] = {"ell", cur.fill, a or 1, l, t, r, b} end
vp.drawEllipse = function(self, l, t, r, b, a) REC[#REC+1] = {"ring", cur.draw, a or 1, l, t, r, b, cur.th} end
vp.drawLine = function(self, x1, y1, x2, y2, a) REC[#REC+1] = {"line", cur.draw, a or 1, x1, y1, x2, y2, cur.th} end
vp.fillPolygon = function(self, poly, a) local p = {} for i, q in ipairs(poly) do p[#p+1] = q.x; p[#p+1] = q.y end REC[#REC+1] = {"poly", cur.fill, a or 1, p} end
function FRAME(t)
  REC = {}
  MOCK.now = T0 + t * 1000
  vp:fire("onAfterDrawLayers")
  return REC
end
'''


def hexa(c, a):
    c = c.lstrip("#")
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    if len(c) >= 8:
        a = a * int(c[6:8], 16) / 255
    return (r, g, b, int(max(0, min(1, a)) * 255))


def raster(rec, W, H, bg=(59, 74, 58, 255)):
    img = Image.new("RGBA", (W, H), bg)
    for i in range(1, len(rec) + 1):
        r = rec[i]
        kind, col, a = r[1], r[2], r[3]
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        rgba = hexa(col, a)
        if kind == "rect":
            d.rectangle((r[4], r[5], r[6], r[7]), fill=rgba)
        elif kind == "ell":
            d.ellipse((r[4], r[5], r[6], r[7]), fill=rgba)
        elif kind == "ring":
            d.ellipse((r[4], r[5], r[6], r[7]), outline=rgba, width=max(1, int(r[8])))
        elif kind == "line":
            d.line((r[4], r[5], r[6], r[7]), fill=rgba, width=max(1, int(r[8])))
        elif kind == "poly":
            pts = r[4]
            xy = [(pts[j], pts[j + 1]) for j in range(1, len(pts) + 1, 2)]
            d.polygon(xy, fill=rgba)
        img.alpha_composite(layer)
    return img


def setup(L):
    L.execute(TH.MOCK)
    L.execute("require = function() end")
    for pname, files in {"SceneSuite_SpellFX": ["fsCommon.lua", "spellfx.lua"],
                         "SceneSuite_Weather": ["weather.lua"]}.items():
        for fn in files:
            L.execute(open(os.path.join(TH.P, pname, fn), encoding="utf-8").read())
        for lfm in os.listdir(os.path.join(TH.P, pname)):
            if lfm.endswith(".lfm"):
                name, fcode = TH.lfm_script(os.path.join(TH.P, pname, lfm))
                L.globals().MOCK.formScripts[name] = L.eval(fcode)
    L.execute('''
SCENE = MOCK.newScene()
SCENE.viewport.width = 480; SCENE.viewport.height = 360; SCENE.viewport.scale = 26
for _, fn in ipairs(SceneLib.plugins) do fn(SCENE, {}) end
MOCK.runTimers()
T0 = MOCK.now
''')
    L.execute(RECORDER)


def main(out, ids):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    setup(L)
    W, H = 480, 360
    times = [0.15, 0.45, 0.8, 1.3]
    rows = []
    for fid in ids:
        if fid.startswith("weather:"):
            fx = fid.split(":")[1]
            L.execute('SCENE.userData.fsWeather = FSC.encode({fx="%s", intensity="2", wind="0.25", opacity="0.8"})' % fx)
            L.execute("MOCK.tickIntervals(); T0 = MOCK.now")
            frames = []
            for t in times:
                for k in range(8):  # avança a simulação
                    L.eval("FRAME")(t - 0.04 * (8 - k))
                frames.append(raster(L.eval("FRAME")(t), W, H))
        else:
            L.execute('T0 = T0 + 100000; FRAME(0)')
            L.execute('SCENE:broadcastMessage("fsfx_play", {fx="%s", sx=3, sy=10, tx=13, ty=6, r=6, n=4, angle=70, '
                      'targets={{x=11,y=5},{x=14,y=9},{x=16,y=4}}}, true)' % fid)
            frames = [raster(L.eval("FRAME")(t), W, H) for t in times]
        row = Image.new("RGBA", (W * len(frames), H + 18), (20, 20, 20, 255))
        for i, f in enumerate(frames):
            row.paste(f, (i * W, 18))
        ImageDraw.Draw(row).text((4, 3), fid, fill=(255, 255, 255, 255))
        rows.append(row)
    sheet = Image.new("RGBA", (rows[0].width, sum(r.height for r in rows)), (0, 0, 0, 255))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
    sheet.save(out)
    print("salvo em", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
