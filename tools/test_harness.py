#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Teste de execução dos plugins contra um SDK do Firecast SIMULADO (mock).

Não substitui testar no Firecast, mas pega erros de execução (nil, nomes
errados, argumentos inválidos para as funções de desenho) em todos os
caminhos principais: formulários, ferramentas, cliques, desenho por frame.

  python3 tools/test_harness.py
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

from lupa import lua54

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "plugins")

MOCK = r'''
-- ===================== SDK simulado =====================
local unpack = table.unpack
MOCK = {log = {}, timers = {}, intervals = {}, nextId = 1, messages = {}, broadcastListeners = {}, now = 1000}

function mlog(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end MOCK.log[#MOCK.log+1] = table.concat(t, " ") end
function showMessage(m) mlog("showMessage:", m) end
function setTimeout(fn, ms) local id = MOCK.nextId; MOCK.nextId = id + 1; MOCK.timers[id] = fn; return id end
function clearTimeout(id) MOCK.timers[id] = nil end
function setInterval(fn, ms) local id = MOCK.nextId; MOCK.nextId = id + 1; MOCK.intervals[id] = fn; return id end
function clearInterval(id) MOCK.intervals[id] = nil end
function MOCK.runTimers() local t = MOCK.timers; MOCK.timers = {}; for _, fn in pairs(t) do fn() end end
function MOCK.tickIntervals() for _, fn in pairs(MOCK.intervals) do fn() end end

system = {getTickCount = function() return MOCK.now end}
System = system

function colorToRGBA(c)
  local h = tostring(c):match("^#(%x+)")
  if h == nil then return 1, 1, 1, 1 end
  local r, g, b = tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
  local a = (#h >= 8) and tonumber(h:sub(7,8),16)/255 or 1
  return r, g, b, a
end
function RGBAToColor(r, g, b, a) return string.format("#%02X%02X%02X%02X", math.floor(r*255+.5), math.floor(g*255+.5), math.floor(b*255+.5), math.floor(a*255+.5)) end

local function num(v, name) assert(type(v) == "number" and v == v, "esperado número em " .. name .. ", veio " .. tostring(v)) end

-- listeners genéricos
local function makeListenable(o)
  o._l = {}
  function o:listen(ev, fn) local id = MOCK.nextId; MOCK.nextId = id + 1; self._l[id] = {ev = ev, fn = fn}; return id end
  function o:unlisten(id) self._l[id] = nil end
  function o:fire(ev, ...) local n = 0 for _, l in pairs(self._l) do if l.ev == ev then l.fn(...); n = n + 1 end end return n end
  return o
end

-- operações gráficas
local VALID = {
  xMetric = {screenMetric=1, worldMetric=1, canvasMetric=1, cellMetric=1},
  rotMode = {default=1, ignoreCanvasRot=1},
  outOfOrderMode = {noOutOfOrder=1, afterFogOfWarLayer=1, beforeOwnerLayer=1, afterOwnerLayer=1},
  visibility = {everyone=1, gmOnly=1},
  strokeDash = {solid=1, dash=1, dot=1, dashDot=1, dashDotDot=1},
  strokeCap = {flat=1, round=1}, strokeJoin = {miter=1, round=1, bevel=1},
  strokeSizeMetric = {screenMetric=1, worldMetric=1, canvasMetric=1, cellMetric=1},
  horzTextAlign = {leading=1, center=1, trailing=1}, vertTextAlign = {leading=1, center=1, trailing=1},
}
VALID.yMetric = VALID.xMetric; VALID.widthMetric = VALID.xMetric; VALID.heightMetric = VALID.xMetric
local NUMERIC = {x=1, y=1, z=1, width=1, height=1, opacity=1, xOrigin=1, yOrigin=1, strokeSize=1, rotation=1}

local function newOp(canvas, kind)
  local data = {objectType = kind, name = ""}
  local op = setmetatable({}, {
    __index = function(t, k)
      if k == "delete" then return function() for i, o in ipairs(canvas._ops) do if o == t then table.remove(canvas._ops, i) break end end end end
      if k == "aspect" then return math.max(1, #(data.text or "x") * 0.5) end
      return data[k]
    end,
    __newindex = function(t, k, v)
      if VALID[k] then assert(VALID[k][v], "valor inválido para " .. k .. ": " .. tostring(v)) end
      if NUMERIC[k] then num(v, k) end
      if k == "data" then assert(type(v) == "string" and #v > 0, "path vazio") ; assert(not v:find("nan") and not v:find("inf"), "path com nan/inf: " .. v:sub(1,80)) end
      if k == "drawingTrigger" or k == "fontStyle" then assert(type(v) == "table", k .. " deve ser tabela") end
      if k == "color" or k == "strokeColor" then assert(type(v) == "string", k .. " deve ser string") end
      data[k] = v
    end})
  canvas._ops[#canvas._ops + 1] = op
  return op
end

local function newCanvas()
  local c = {_ops = {}}
  c.addPath = function(self) return newOp(self, "opPath") end
  c.addText = function(self) return newOp(self, "opText") end
  c.addBitmap = function(self) return newOp(self, "opBitmap") end
  c.getOp = function(self, i)
    if MOCK.oneBasedOps then
      assert(i >= 1, "índice inválido"); return self._ops[i]
    end
    return self._ops[i + 1]
  end
  c.findByName = function(self, n) for _, o in ipairs(self._ops) do if o.name == n then return o end end return nil end
  c.clear = function(self) self._ops = {} end
  setmetatable(c, {__index = function(t, k) if k == "opCount" then return #rawget(t, "_ops") end end})
  return c
end

local function newItem(scene, kind, x, y, w, h)
  local it = makeListenable({objectType = kind, x = x, y = y, width = w, height = h, rotation = 0,
                             isObjectAlive = true, isMine = false, name = "Goblin", friendOrFoe = "foe",
                             userData = {}, canvas = newCanvas(), scene = scene, layer = "tokens", selected = false})
  it.objectID = MOCK.nextId; MOCK.nextId = MOCK.nextId + 1
  function it:beginUpdate() end
  function it:endUpdate() end
  function it:getCenter() return self.x + self.width / 2, self.y + self.height / 2 end
  function it:setCenter(cx, cy) self.x = cx - self.width / 2; self.y = cy - self.height / 2; self:fire("onBoundsChange", self) end
  function it:markAsMyDrawing() end
  function it:delete() for i, o in ipairs(scene._items) do if o == self then table.remove(scene._items, i) break end end self.isObjectAlive = false end
  return it
end

function MOCK.newScene()
  local scene = makeListenable({isGM = true, currentUserID = "mestre", workingLayer = "tokens", worldMetricName = "m",
                                userData = {}, isObjectAlive = true, _items = {}})
  scene.objectID = MOCK.nextId; MOCK.nextId = MOCK.nextId + 1
  scene.grid = {cellSize = 1.5, gridType = "square", squareDiagonals = "simplified",
                cellToWorld = function(self, i, j) return j * 1.5 + 0.75, i * 1.5 + 0.75 end,
                worldToCell = function(self, x, y) return math.floor(y / 1.5), math.floor(x / 1.5) end}
  local vp = makeListenable({width = 1200, height = 800, worldX = 0, worldY = 0, scale = 40, cursor = "default", scene = scene,
                             draws = 0, tools = {}})
  scene.viewport = vp
  function vp:worldToScreen(x, y) num(x, "worldToScreen.x"); num(y, "worldToScreen.y"); return (x - self.worldX) * self.scale, (y - self.worldY) * self.scale end
  function vp:screenToWorld(x, y) num(x, "screenToWorld.x"); num(y, "screenToWorld.y"); return x / self.scale + self.worldX, y / self.scale + self.worldY end
  function vp:setupToolCategory(n, t, o) end
  function vp:addToolButton(cat, title, icon, order, opts, cb, deact)
    assert(type(cb) == "function"); self.tools[#self.tools + 1] = {title = title, icon = icon, cb = cb, deact = deact}; return #self.tools end
  function vp:selectDefaultToolButton() end
  function vp:needRepaint() self.needs = true end
  function vp:showForm(f, o) f._shown = true; return true end
  function vp:closeForm(f) f._shown = false; return true end
  vp.prepareFill = function(self, c) assert(type(c) == "string", "prepareFill cor") self._fill = true end
  vp.prepareDraw = function(self, c, t, cap, join, dash) assert(type(c) == "string"); if t ~= nil then num(t, "thickness") end
    if cap ~= nil then assert(VALID.strokeCap[cap], "cap") end; if join ~= nil then assert(VALID.strokeJoin[join], "join") end
    if dash ~= nil then assert(VALID.strokeDash[dash], "dash") end; self._draw = true end
  local function rect4(self, a, b, c, d, op) num(a,"l") num(b,"t") num(c,"r") num(d,"b") if op ~= nil then num(op, "opacity"); assert(op >= 0 and op <= 1.0001, "opacity fora de 0..1: " .. op) end self.draws = self.draws + 1 end
  vp.fillRect = function(self, ...) assert(self._fill, "fill sem prepareFill"); rect4(self, ...) end
  vp.fillEllipse = vp.fillRect
  vp.drawEllipse = function(self, ...) assert(self._draw, "draw sem prepareDraw"); rect4(self, ...) end
  vp.drawRect = vp.drawEllipse
  vp.drawLine = function(self, ...) assert(self._draw, "line sem prepareDraw"); rect4(self, ...) end
  vp.fillPolygon = function(self, poly, op) assert(type(poly) == "table" and #poly >= 3, "poly"); for _, p in ipairs(poly) do num(p.x, "poly.x"); num(p.y, "poly.y") end if op then num(op, "op"); assert(op >= 0 and op <= 1.0001, "opacity poly " .. op) end self.draws = self.draws + 1 end
  vp.prepareFont = function(self, size, name, bold) num(size, "font size"); self._font = true end
  vp.textSize = function(self, txt) assert(self._font, "textSize sem prepareFont"); return #tostring(txt) * 8, 16 end
  vp.fillText = function(self, x, y, txt, op) assert(self._fill, "fillText sem prepareFill"); num(x, "tx"); num(y, "ty"); assert(type(txt) == "string"); if op then num(op, "op"); assert(op >= 0 and op <= 1.0001, "opacity texto " .. op) end self.draws = self.draws + 1 end
  vp.fillACell = function(self, i, j, op) num(i, "i"); num(j, "j"); self.draws = self.draws + 1 end

  scene.fogOfWar = {opaque = {},
    addOpaqueArea = function(self, poly) assert(#poly >= 3); for _, p in ipairs(poly) do num(p.x, "fow.x"); num(p.y, "fow.y") end; self.opaque[#self.opaque+1] = poly end,
    removeOpaqueArea = function(self, poly) assert(#poly >= 3); for i, p in ipairs(self.opaque) do if p[1].x == poly[1].x and p[1].y == poly[1].y then table.remove(self.opaque, i) return end end end}
  local items = makeListenable({})
  scene.items = items
  setmetatable(items, {__len = function() return #scene._items end,
    __index = function(t, k) if type(k) == "number" then return scene._items[k] end
      if k == "selection" then local s = {} for _, it in ipairs(scene._items) do if it.selected then s[#s+1] = it end end return s end end})
  function items:enumAtPoint(x, y, layer)
    local out = {} for _, it in ipairs(scene._items) do if x >= it.x and x <= it.x + it.width and y >= it.y and y <= it.y + it.height then out[#out+1] = it end end return out end
  function items:clearSelection() for _, it in ipairs(scene._items) do it.selected = false end end
  function items:itemAtPoint(x, y, l) local o = self:enumAtPoint(x, y, l) return o[#o] end
  function items:addUserDrawing(layer) local it = newItem(scene, "userDrawing", 0, 0, 1, 1); it.isMine = true; scene._items[#scene._items+1] = it; return it end
  function scene:addToken(x, y, w, h) local it = newItem(scene, "token", x, y, w, h); scene._items[#scene._items+1] = it; items:fire("onItemAdded", it); return it end
  function scene:broadcastMessage(id, msg, loop) MOCK.messages[#MOCK.messages+1] = {id = id, msg = msg}
    if loop then for _, l in ipairs(MOCK.broadcastListeners) do if l.id == id then l.fn("mestre", id, msg) end end end end
  function scene:newBroadcastListener(id, fn) local l = {id = id, fn = fn}; MOCK.broadcastListeners[#MOCK.broadcastListeners+1] = l; return l end
  return scene
end

SceneLib = {plugins = {}}
function SceneLib.registerPlugin(fn) SceneLib.plugins[#SceneLib.plugins+1] = fn end
Firecast = {getMesaDe = function() return {chat = {escrever = function(_, t) mlog("chat:", t) end}, meuJogador = {isEspectador = false}} end}
Dialogs = {choose = function(p, opts, cb, def) assert(type(opts) == "table") cb(true, def or 1, opts[def or 1]) end,
           confirmYesNo = function(p, cb) cb(true) end,
           inputQuery = function(t, p, d, cb) cb(d) end}

-- Controles de formulário simulados
local function newControl()
  return {text = "", checked = false, value = "", visible = true, enabled = true, color = "#FFFFFF", items = {}, values = {}}
end
function MOCK.newForm(name)
  local f = setmetatable({_name = name}, {__index = function(t, k)
    local c = newControl(); rawset(t, k, c); return c end})
  rawset(f, "beginUpdate", function() end); rawset(f, "endUpdate", function() end)
  rawset(f, "close", function(self) self._shown = false end)
  rawset(f, "show", function(self) self._shown = true end)
  return f
end
GUI = {newForm = function(name) local f = MOCK.newForm(name); local init = MOCK.formScripts[name]; assert(init, "form desconhecido " .. name); init(f); MOCK.forms[name] = f; return f end}
MOCK.formScripts = {}
MOCK.forms = {}

-- control setters que imitam o comboBox (value precisa existir em values)
'''

def lfm_script(path):
    root = ET.parse(path).getroot()
    name = root.get("name")
    codes = []
    # valores iniciais dos controles
    init = []
    for el in root.iter():
        n = el.get("name")
        if n and el.tag in ("comboBox", "edit", "checkBox", "colorComboBox", "label"):
            if el.get("value") is not None:
                init.append("self.%s.value = %r" % (n, el.get("value")))
            if el.get("text") is not None:
                init.append("self.%s.text = %r" % (n, el.get("text")))
            if el.get("checked") is not None:
                init.append("self.%s.checked = %s" % (n, "true" if el.get("checked") == "true" else "false"))
            if el.get("color") is not None:
                init.append("self.%s.color = %r" % (n, el.get("color")))
        if el.tag == "script":
            codes.append(el.text or "")
    body = "\n".join(init) + "\n" + "\n".join(codes)
    return name, "function(self)\n" + body + "\nend"


def main():
    for one_based in (False, True):
        print("== getOp %s ==" % ("1-based" if one_based else "0-based"))
        run(one_based)
    print("TODOS OS CENÁRIOS PASSARAM")


def run(one_based):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(MOCK)
    L.globals().MOCK.oneBasedOps = one_based

    order = {
        "SceneSuite_Conditions": ["fsCommon.lua", "condData.lua", "conditions.lua"],
        "SceneSuite_Auras": ["fsCommon.lua", "auras.lua"],
        "SceneSuite_Reach": ["fsCommon.lua", "reach.lua"],
        "SceneSuite_SpellAreas": ["fsCommon.lua", "spellAreas.lua"],
        "SceneSuite_Weather": ["fsCommon.lua", "weather.lua"],
        "SceneSuite_SpellFX": ["fsCommon.lua", "spellfx.lua"],
        "SceneSuite_HP": ["fsCommon.lua", "hp.lua"],
        "SceneSuite_Combat": ["fsCommon.lua", "combat.lua"],
        "SceneSuite_Light": ["fsCommon.lua", "light.lua"],
        "SceneSuite_Triggers": ["fsCommon.lua", "triggers.lua"],
        "SceneSuite_TokenBar": ["fsCommon.lua", "tokenbar.lua"],
    }
    L.execute("require = function() end")
    for pname, files in order.items():
        for fn in files:
            code = open(os.path.join(P, pname, fn), encoding="utf-8").read()
            L.execute(code)
        for lfm in os.listdir(os.path.join(P, pname)):
            if lfm.endswith(".lfm"):
                name, fcode = lfm_script(os.path.join(P, pname, lfm))
                f = L.eval(fcode)
                L.globals().MOCK.formScripts[name] = f

    L.execute(open(os.path.join(ROOT, "tools", "test_scenarios.lua"), encoding="utf-8").read())
    log = L.globals().MOCK.log
    for i in range(1, len(log) + 1):
        print("  log:", log[i])


if __name__ == "__main__":
    main()
