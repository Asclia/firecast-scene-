--[[
  Scene Suite - Animações de Magia

  Animações pré-prontas das magias mais usadas de Pathfinder 1e (que também
  servem para os equivalentes do FFd20: Fire/Fira, Blizzard, Thunder, Cure...).

  Como funciona:
   - Quem dispara a animação envia uma mensagem ("fsfx_play") pelo scene;
     cada pessoa com o plugin instalado desenha a animação localmente na tela
     (onAfterDrawLayers). Nada é salvo no tabuleiro e nada captura cliques.
   - O plugin "Áreas de Magia" também envia essa mensagem quando a opção
     "Tocar animação" está marcada.

  Uso da ferramenta:
   - Projéteis/raios/cones/linhas: selecione o token conjurador antes (ou
     clique primeiro na origem) e clique no alvo.
   - Áreas: clique no centro.  Efeitos em si mesmo: clique no token.
   - Relâmpago em cadeia: clique nos alvos em sequência; botão direito (ou
     ENTER) dispara.
]]

require("scene.lua");
require("firecast.lua");
require("log.lua");
require("utils.lua");
require("system.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local FX_MESSAGE = "fsfx_play";
local TOOL_CATEGORY = "SSuite_SpellFX";
local FRAME_MS = 25;

local rnd = math.random;
local sin, cos, pi, floor, max, min, abs, sqrt = math.sin, math.cos, math.pi, math.floor, math.max, math.min, math.abs, math.sqrt;

local function rr(a, b) return a + (b - a) * rnd(); end;
local function clamp01(x) return max(0, min(1, x)); end;
local function lerp(a, b, t) return a + (b - a) * t; end;
local function easeOut(t) t = clamp01(t); return 1 - (1 - t) * (1 - t); end;
local function easeIn(t) t = clamp01(t); return t * t; end;
local function now() return system.getTickCount() / 1000; end;

-- fase local de t dentro de [t0, t1] -> 0..1 (nil se fora)
local function phase(t, t0, t1)
	if t < t0 or t > t1 then
		return nil;
	end;

	return (t - t0) / (t1 - t0);
end;

-- "sobe e desce": 0 -> 1 -> 0
local function bell(p)
	return sin(clamp01(p) * pi);
end;

----------------------------------------------------------------------
-- Renderizador (coordenadas de mundo -> tela)
----------------------------------------------------------------------

local R = {};

function R.begin(vp, scene)
	R.vp = vp;
	R.s = vp.scale;              -- pixels por unidade de mundo
	R.cs = FSC.cellSize(scene);  -- tamanho de um quadrado no mundo
	R.W, R.H = vp.width, vp.height;
end;

function R.p(x, y)
	return R.vp:worldToScreen(x, y);
end;

-- raio/espessura em quadrados -> pixels
function R.px(sq)
	return sq * R.cs * R.s;
end;

function R.disc(x, y, rSq, color, a)
	if a <= 0.004 or rSq <= 0 then return; end;
	local sx, sy = R.p(x, y);
	local r = R.px(rSq);
	R.vp:prepareFill(color);
	R.vp:fillEllipse(sx - r, sy - r, sx + r, sy + r, min(1, a));
end;

function R.glow(x, y, rSq, color, a)
	R.disc(x, y, rSq * 2.2, color, a * 0.12);
	R.disc(x, y, rSq * 1.5, color, a * 0.25);
	R.disc(x, y, rSq, color, a);
end;

function R.ring(x, y, rSq, thickPx, color, a)
	if a <= 0.004 or rSq <= 0 then return; end;
	local sx, sy = R.p(x, y);
	local r = R.px(rSq);
	R.vp:prepareDraw(color, max(0.5, thickPx));
	R.vp:drawEllipse(sx - r, sy - r, sx + r, sy + r, min(1, a));
end;

function R.line(x1, y1, x2, y2, thickPx, color, a)
	if a <= 0.004 then return; end;
	local ax, ay = R.p(x1, y1);
	local bx, by = R.p(x2, y2);
	R.vp:prepareDraw(color, max(0.5, thickPx), "round", "round");
	R.vp:drawLine(ax, ay, bx, by, min(1, a));
end;

-- feixe com brilho: largura em quadrados
function R.beam(x1, y1, x2, y2, wSq, color, core, a)
	local w = R.px(wSq);
	R.line(x1, y1, x2, y2, w * 3, color, a * 0.18);
	R.line(x1, y1, x2, y2, w * 1.6, color, a * 0.45);
	R.line(x1, y1, x2, y2, w * 0.6, core or "#FFFFFF", a);
end;

function R.poly(pts, color, a)
	if a <= 0.004 then return; end;
	local sp = {};

	for i, p in ipairs(pts) do
		local sx, sy = R.p(p[1], p[2]);
		sp[i] = {x = sx, y = sy};
	end;

	R.vp:prepareFill(color);
	R.vp:fillPolygon(sp, min(1, a));
end;

function R.flash(color, a)
	if a <= 0.004 then return; end;
	R.vp:prepareFill(color);
	R.vp:fillRect(0, 0, R.W, R.H, min(1, a));
end;

-- relâmpago serrilhado entre dois pontos (seed muda a forma)
function R.bolt(x1, y1, x2, y2, seed, jag, thickPx, color, a, branches)
	local dx, dy = x2 - x1, y2 - y1;
	local len = sqrt(dx * dx + dy * dy);

	if len <= 0 then return; end;

	local nx, ny = -dy / len, dx / len;
	local segs = max(4, floor(len / R.cs * 1.5));
	local pts = {{x1, y1}};
	local st = seed;

	local function nextRnd()
		st = (st * 1103515245 + 12345) % 2147483648;
		return (st % 10000) / 10000;
	end;

	for i = 1, segs - 1 do
		local t = i / segs;
		local off = (nextRnd() - 0.5) * jag * R.cs;
		pts[#pts + 1] = {x1 + dx * t + nx * off, y1 + dy * t + ny * off};
	end;

	pts[#pts + 1] = {x2, y2};

	for pass = 1, 3 do
		local th = (pass == 1) and thickPx * 4 or ((pass == 2) and thickPx * 2 or thickPx);
		local col = (pass == 3) and "#FFFFFF" or color;
		local al = (pass == 1) and a * 0.15 or ((pass == 2) and a * 0.5 or a);

		for i = 1, #pts - 1 do
			R.line(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], th, col, al);
		end;
	end;

	if branches then
		for b = 1, 2 do
			local i = 2 + floor(nextRnd() * (#pts - 3));
			local p = pts[i];

			if p ~= nil then
				local bl = len * 0.2;
				local ang = (nextRnd() - 0.5) * 1.6;
				local ex = p[1] + (dx / len * cos(ang) - dy / len * sin(ang)) * bl;
				local ey = p[2] + (dy / len * cos(ang) + dx / len * sin(ang)) * bl;
				R.line(p[1], p[2], ex, ey, thickPx * 0.8, color, a * 0.7);
			end;
		end;
	end;
end;

----------------------------------------------------------------------
-- Sistemas de partículas
----------------------------------------------------------------------

--[[ Cria partículas a partir de (x, y).
  o.n, o.angle (graus, direção central), o.spread (graus de abertura, 360 = todas),
  o.speed {min,max} (quadrados/s), o.life {min,max} (s), o.size {min,max} (quadrados),
  o.colors (lista), o.delay {min,max}, o.drag (0..1), o.gravity (quadrados/s²),
  o.startR (raio inicial de espalhamento, em quadrados) ]]
local function burstParticles(x, y, o)
	local list = {};

	for i = 1, o.n or 20 do
		local a = (o.angle or 0) + ((o.spread or 360) * (rnd() - 0.5));
		local dx, dy = FSC.dirVector(a);
		local sr = rr(0, o.startR or 0);
		local sp = o.speed or {1, 3};
		local lf = o.life or {0.5, 1};
		local sz = o.size or {0.05, 0.12};
		local dl = o.delay or {0, 0};
		local colors = o.colors or {"#FFFFFF"};
		list[i] = {
			x = x + dx * sr, y = y + dy * sr, dx = dx, dy = dy,
			sp = rr(sp[1], sp[2]), life = rr(lf[1], lf[2]), size = rr(sz[1], sz[2]),
			delay = rr(dl[1], dl[2]), color = colors[rnd(1, #colors)]
		};
	end;

	return {list = list, drag = o.drag or 0, gravity = o.gravity or 0, glow = o.glow, grow = o.grow or 0,
	        fadeIn = o.fadeIn or 0};
end;

local function drawParticles(ps, t, alphaMul)
	local cs = R.cs;

	for _, p in ipairs(ps.list) do
		local tt = t - p.delay;

		if tt >= 0 and tt <= p.life then
			local f = tt / p.life;
			-- distância com arrasto
			local dist = p.sp * tt * (1 - ps.drag * f * 0.5);
			local x = p.x + p.dx * dist * cs;
			local y = p.y + p.dy * dist * cs + 0.5 * ps.gravity * tt * tt * cs;
			local a = (1 - f) * (alphaMul or 1);

			if ps.fadeIn > 0 and f < ps.fadeIn then
				a = a * (f / ps.fadeIn);
			end;

			local size = p.size * (1 + ps.grow * f);

			if ps.glow then
				R.glow(x, y, size, p.color, a);
			else
				R.disc(x, y, size, p.color, a);
			end;
		end;
	end;
end;

-- Explosão completa (clarão, bola, anel, brasas e fumaça)
local function newExplosion(x, y, rSq, colors, t0)
	local ex = {x = x, y = y, r = rSq, t0 = t0, colors = colors};
	ex.embers = burstParticles(x, y, {n = 26 + floor(rSq * 6), speed = {rSq * 0.8, rSq * 2.2}, life = {0.5, 1.1},
	                                  size = {0.06, 0.16}, colors = colors.embers, drag = 0.8, glow = true});
	ex.smoke = burstParticles(x, y, {n = colors.noSmoke and 0 or (10 + floor(rSq * 3)), speed = {rSq * 0.2, rSq * 0.6}, life = {1.0, 1.8},
	                                 size = {rSq * 0.2, rSq * 0.35}, colors = {"#424242", "#616161", "#757575"},
	                                 drag = 0.6, grow = 1.2, delay = {0.15, 0.4}, startR = rSq * 0.4, fadeIn = 0.2});
	return ex;
end;

local function drawExplosion(ex, t)
	local lt = t - ex.t0;

	if lt < 0 then return; end;

	local r = ex.r;
	-- fumaça por baixo
	drawParticles(ex.smoke, lt, 0.5);

	-- bola de fogo
	local p = phase(lt, 0, 0.7);

	if p ~= nil then
		local rad = r * easeOut(p * 1.4);
		local a = 1 - easeIn(p);
		R.disc(ex.x, ex.y, rad, ex.colors.outer, a * 0.55);
		R.disc(ex.x, ex.y, rad * 0.75, ex.colors.mid, a * 0.7);
		R.disc(ex.x, ex.y, rad * 0.45, ex.colors.core, a * 0.9);
	end;

	-- clarão inicial
	local pf = phase(lt, 0, 0.18);

	if pf ~= nil then
		R.glow(ex.x, ex.y, r * 0.5 * easeOut(pf), "#FFFFFF", 1 - pf);
		R.flash(ex.colors.flash or "#FFFFFF", 0.12 * (1 - pf));
	end;

	-- onda de choque
	local pr = phase(lt, 0.05, 0.6);

	if pr ~= nil then
		R.ring(ex.x, ex.y, r * (0.3 + 0.8 * easeOut(pr)), R.px(0.12) * (1 - pr) + 1, ex.colors.ring or "#FFFFFF", (1 - pr) * 0.8);
	end;

	drawParticles(ex.embers, lt, 1);
end;

local FIRE = {core = "#FFF59D", mid = "#FFB300", outer = "#E64A19", ring = "#FFE0B2", flash = "#FFCC80",
              embers = {"#FFCA28", "#FF7043", "#FFAB40", "#FFF176"}};
local ICE = {noSmoke = true, core = "#FFFFFF", mid = "#B3E5FC", outer = "#4FC3F7", ring = "#E1F5FE", flash = "#E1F5FE",
             embers = {"#E1F5FE", "#B3E5FC", "#FFFFFF", "#81D4FA"}};
local HOLY = {noSmoke = true, core = "#FFFFFF", mid = "#FFF9C4", outer = "#FFD54F", ring = "#FFFDE7", flash = "#FFFDE7",
              embers = {"#FFFFFF", "#FFF59D", "#FFE082"}};
local ACID = {core = "#F4FF81", mid = "#C6FF00", outer = "#64DD17", ring = "#CCFF90", flash = "#CCFF90",
              embers = {"#C6FF00", "#76FF03", "#B2FF59"}};

-- Projétil com rastro
local function drawProjectile(x1, y1, x2, y2, p, sizeSq, color, core, trailN)
	local x, y = lerp(x1, x2, p), lerp(y1, y2, p);

	for i = trailN or 6, 1, -1 do
		local q = max(0, p - i * 0.025);
		R.disc(lerp(x1, x2, q), lerp(y1, y2, q), sizeSq * (1 - i * 0.1), color, 0.5 * (1 - i / ((trailN or 6) + 1)));
	end;

	R.glow(x, y, sizeSq, color, 1);
	R.disc(x, y, sizeSq * 0.5, core or "#FFFFFF", 1);
	return x, y;
end;

local function dist(x1, y1, x2, y2)
	return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2);
end;

local function angleBetween(x1, y1, x2, y2)
	return FSC.angleOf(x2 - x1, y2 - y1);
end;

----------------------------------------------------------------------
-- Catálogo de efeitos
-- kind: "target" (origem -> alvo), "area" (centro), "self" (no token),
--       "cone", "line" (origem + direção), "chain" (vários alvos)
-- size: tamanho padrão (raio/comprimento) em ft
-- build(m, cs) -> {dur = segundos, draw = function(t)}
--   m = mensagem: sx, sy, tx, ty (mundo), r (mundo), angle, n, targets
----------------------------------------------------------------------

local FX = {};
local FX_ORDER = {};

local function def(id, name, kind, size, build, opts)
	FX[id] = {id = id, name = name, kind = kind, size = size, build = build, count = opts and opts.count};
	FX_ORDER[#FX_ORDER + 1] = id;
end;

-- raio em quadrados a partir da mensagem
local function rsq(m, cs, defaultSq)
	if type(m.r) == "number" and m.r > 0 then
		return m.r / cs;
	end;

	return defaultSq;
end;

-- Bola de Fogo
def("fireball", "Bola de Fogo (projétil + explosão)", "target", "20 ft", function(m, cs)
	local fly = max(0.25, min(0.7, dist(m.sx, m.sy, m.tx, m.ty) / cs * 0.05));
	local ex = newExplosion(m.tx, m.ty, rsq(m, cs, 4), FIRE, fly);

	return {dur = fly + 2.2, draw = function(t)
		local p = phase(t, 0, fly);

		if p ~= nil then
			drawProjectile(m.sx, m.sy, m.tx, m.ty, easeIn(p), 0.18, "#FF8F00", "#FFF59D", 8);
		end;

		drawExplosion(ex, t);
	end};
end);

-- Relâmpago (linha)
def("lightning_bolt", "Relâmpago (linha)", "line", "120 ft", function(m, cs)
	local len = rsq(m, cs, 24) * cs;
	local dx, dy = FSC.dirVector(m.angle or angleBetween(m.sx, m.sy, m.tx, m.ty));
	local ex, ey = m.sx + dx * len, m.sy + dy * len;
	local sparks = burstParticles(ex, ey, {n = 18, speed = {1, 4}, life = {0.2, 0.6}, size = {0.03, 0.07},
	                                       colors = {"#FFFFFF", "#80D8FF"}, glow = true, drag = 0.7});
	local seed = rnd(1, 99999);

	return {dur = 1.2, draw = function(t)
		local p = phase(t, 0, 0.75);

		if p ~= nil then
			local grow = easeOut(min(1, p * 4));
			local flick = (floor(t * 30) % 3 == 0) and 0.55 or 1;
			R.bolt(m.sx, m.sy, m.sx + dx * len * grow, m.sy + dy * len * grow, seed + floor(t * 20), 0.6,
			       R.px(0.05) + 1, "#40C4FF", flick * (1 - easeIn(p)), true);
			R.flash("#E1F5FE", 0.08 * (1 - p));
		end;

		drawParticles(sparks, t - 0.1, 1);
	end};
end);

-- Mísseis Mágicos
def("magic_missile", "Mísseis Mágicos", "target", "", function(m, cs)
	local n = max(1, min(10, m.n or 3));
	local missiles = {};
	local d = dist(m.sx, m.sy, m.tx, m.ty);
	local nx, ny = 0, 0;

	if d > 0 then
		nx, ny = -(m.ty - m.sy) / d, (m.tx - m.sx) / d;
	end;

	for i = 1, n do
		local bend = (i - (n + 1) / 2) * 0.9 + rr(-0.6, 0.6);
		missiles[i] = {delay = (i - 1) * 0.12, bend = bend * cs,
		               hit = burstParticles(m.tx, m.ty, {n = 10, speed = {0.5, 2}, life = {0.2, 0.5}, size = {0.03, 0.06},
		                                                 colors = {"#E1BEE7", "#B388FF", "#FFFFFF"}, glow = true})};
	end;

	local fly = max(0.35, min(0.8, d / cs * 0.04));

	return {dur = fly + n * 0.12 + 0.6, draw = function(t)
		for _, ms in ipairs(missiles) do
			local p = phase(t, ms.delay, ms.delay + fly);

			-- curva quadrática (Bézier) para cada míssil
			local function at(q)
				local mx = (m.sx + m.tx) / 2 + nx * ms.bend;
				local my = (m.sy + m.ty) / 2 + ny * ms.bend;
				local a = (1 - q) * (1 - q);
				local b = 2 * (1 - q) * q;
				local c = q * q;
				return a * m.sx + b * mx + c * m.tx, a * m.sy + b * my + c * m.ty;
			end;

			if p ~= nil then
				for k = 5, 1, -1 do
					local q = max(0, p - k * 0.03);
					local x, y = at(q);
					R.disc(x, y, 0.07 * (1 - k * 0.12), "#B388FF", 0.5 * (1 - k / 6));
				end;

				local x, y = at(p);
				R.glow(x, y, 0.1, "#7C4DFF", 1);
				R.disc(x, y, 0.05, "#FFFFFF", 1);
			end;

			drawParticles(ms.hit, t - ms.delay - fly, 1);
		end;
	end};
end, {count = true});

-- Raio Ardente
def("scorching_ray", "Raio Ardente", "target", "", function(m, cs)
	local n = max(1, min(6, m.n or 1));
	local rays = {};

	for i = 1, n do
		local t0 = (i - 1) * 0.3;
		rays[i] = {t0 = t0, ex = newExplosion(m.tx + rr(-0.2, 0.2) * cs, m.ty + rr(-0.2, 0.2) * cs, 0.6, FIRE, t0 + 0.15)};
	end;

	return {dur = n * 0.3 + 1.0, draw = function(t)
		for _, ray in ipairs(rays) do
			local p = phase(t, ray.t0, ray.t0 + 0.4);

			if p ~= nil then
				local grow = easeOut(min(1, p * 3));
				local w = 0.09 * (1 + 0.25 * sin(t * 60));
				R.beam(m.sx, m.sy, lerp(m.sx, ray.ex.x, grow), lerp(m.sy, ray.ex.y, grow), w, "#FF6D00", "#FFF59D", 1 - easeIn(p));
			end;

			drawExplosion(ray.ex, t);
		end;
	end};
end, {count = true});

-- Raio de Gelo
def("ray_of_frost", "Raio de Gelo", "target", "", function(m, cs)
	local ex = newExplosion(m.tx, m.ty, 0.8, ICE, 0.25);
	local flakes = burstParticles(m.tx, m.ty, {n = 22, speed = {0.3, 1.5}, life = {0.6, 1.3}, size = {0.04, 0.09},
	                                           colors = {"#FFFFFF", "#E1F5FE"}, drag = 0.9, delay = {0.2, 0.4}, glow = true});

	return {dur = 1.6, draw = function(t)
		local p = phase(t, 0, 0.8);

		if p ~= nil then
			local grow = easeOut(min(1, p * 3));
			local ex2, ey2 = lerp(m.sx, m.tx, grow), lerp(m.sy, m.ty, grow);
			R.beam(m.sx, m.sy, ex2, ey2, 0.07, "#4FC3F7", "#FFFFFF", 1 - easeIn(p));

			-- cristais ao longo do raio
			for k = 1, 6 do
				local q = k / 7;

				if q < grow then
					local x, y = lerp(m.sx, m.tx, q), lerp(m.sy, m.ty, q);
					R.disc(x + sin(t * 20 + k) * 0.05 * cs, y + cos(t * 17 + k) * 0.05 * cs, 0.05, "#FFFFFF", 0.8 * (1 - p));
				end;
			end;
		end;

		drawExplosion(ex, t);
		drawParticles(flakes, t, 1);
	end};
end);

-- Projéteis de gelo (Ice Spears / estilhaços)
def("ice_shards", "Projéteis de Gelo", "target", "", function(m, cs)
	local n = max(1, min(8, m.n or 4));
	local shards = {};

	for i = 1, n do
		local ox, oy = rr(-0.4, 0.4) * cs, rr(-0.4, 0.4) * cs;
		shards[i] = {t0 = (i - 1) * 0.1, ox = ox, oy = oy,
		             hit = burstParticles(m.tx + ox * 0.5, m.ty + oy * 0.5, {n = 12, speed = {0.5, 2.5}, life = {0.3, 0.7},
		                                  size = {0.03, 0.07}, colors = {"#FFFFFF", "#B3E5FC", "#81D4FA"}, gravity = 2})};
	end;

	local fly = max(0.3, min(0.6, dist(m.sx, m.sy, m.tx, m.ty) / cs * 0.035));

	return {dur = fly + n * 0.1 + 0.8, draw = function(t)
		local ang = angleBetween(m.sx, m.sy, m.tx, m.ty);
		local dx, dy = FSC.dirVector(ang);
		local px, py = -dy, dx;

		for _, s in ipairs(shards) do
			local p = phase(t, s.t0, s.t0 + fly);

			if p ~= nil then
				local q = easeIn(p);
				local x = lerp(m.sx + s.ox * 0.3, m.tx + s.ox * 0.5, q);
				local y = lerp(m.sy + s.oy * 0.3, m.ty + s.oy * 0.5, q);
				local L, Wd = 0.35 * cs, 0.07 * cs;
				local shard = {{x + dx * L, y + dy * L}, {x + px * Wd, y + py * Wd}, {x - dx * L * 0.6, y - dy * L * 0.6},
				               {x - px * Wd, y - py * Wd}};
				R.poly(shard, "#B3E5FC", 0.95);
				R.disc(x, y, 0.12, "#E1F5FE", 0.3);
			end;

			drawParticles(s.hit, t - s.t0 - fly, 1);
		end;
	end};
end, {count = true});

-- Cone de partículas (genérico)
local function coneEffect(m, cs, lenSq, colors, opts)
	local ang = m.angle or angleBetween(m.sx, m.sy, m.tx, m.ty);
	local stream = burstParticles(m.sx, m.sy, {n = opts.n or 90, angle = ang, spread = 80, speed = {lenSq * 0.9, lenSq * 1.4},
	                                           life = {0.6, 0.95}, size = opts.size or {0.12, 0.3}, colors = colors,
	                                           delay = {0, 0.45}, drag = 0.4, grow = opts.grow or 1.5, glow = opts.glow});

	return {dur = 1.7, draw = function(t)
		local p = phase(t, 0, 1.2);

		if p ~= nil then
			R.poly(FSC.conePoly(m.sx, m.sy, ang, lenSq * cs * easeOut(min(1, p * 2.5)), 90, 20), colors[1], 0.18 * bell(p));
		end;

		drawParticles(stream, t, 0.9);
	end};
end;

def("burning_hands", "Mãos Flamejantes (cone)", "cone", "15 ft", function(m, cs)
	return coneEffect(m, cs, rsq(m, cs, 3), {"#FF6D00", "#FFAB00", "#FFD54F", "#FF3D00"}, {n = 70, glow = true});
end);

def("cone_of_cold", "Cone de Frio (cone)", "cone", "60 ft", function(m, cs)
	return coneEffect(m, cs, rsq(m, cs, 12), {"#B3E5FC", "#FFFFFF", "#81D4FA", "#E1F5FE"}, {n = 140, size = {0.15, 0.4}});
end);

-- Spray de Cores
def("color_spray", "Spray de Cores (cone)", "cone", "15 ft", function(m, cs)
	local lenSq = rsq(m, cs, 3);
	local ang = m.angle or angleBetween(m.sx, m.sy, m.tx, m.ty);
	local colors = {"#FF1744", "#FF9100", "#FFEA00", "#00E676", "#2979FF", "#D500F9"};
	local sparkles = burstParticles(m.sx, m.sy, {n = 60, angle = ang, spread = 85, speed = {lenSq * 0.8, lenSq * 1.3},
	                                             life = {0.5, 0.9}, size = {0.05, 0.1}, colors = colors, glow = true,
	                                             delay = {0, 0.3}});

	return {dur = 1.4, draw = function(t)
		local p = phase(t, 0, 1.0);

		if p ~= nil then
			for i, c in ipairs(colors) do
				local q = clamp01(p * 1.6 - (i - 1) * 0.08);

				if q > 0 then
					local L = lenSq * cs * easeOut(q);
					R.poly(FSC.conePoly(m.sx, m.sy, ang - 45 + (i - 1) * 15, L, 15, 6), c, 0.4 * bell(p));
				end;
			end;
		end;

		drawParticles(sparkles, t, 1);
	end};
end);

-- Flecha Ácida
def("acid_arrow", "Flecha Ácida", "target", "", function(m, cs)
	local fly = max(0.3, min(0.6, dist(m.sx, m.sy, m.tx, m.ty) / cs * 0.035));
	local splash = burstParticles(m.tx, m.ty, {n = 24, speed = {0.5, 2.5}, life = {0.4, 0.9}, size = {0.04, 0.1},
	                                           colors = ACID.embers, gravity = 2.5, drag = 0.5});

	return {dur = fly + 1.2, draw = function(t)
		local p = phase(t, 0, fly);

		if p ~= nil then
			local ang = angleBetween(m.sx, m.sy, m.tx, m.ty);
			local dx, dy = FSC.dirVector(ang);
			local x, y = lerp(m.sx, m.tx, p), lerp(m.sy, m.ty, p);
			R.line(x - dx * 0.5 * cs, y - dy * 0.5 * cs, x, y, R.px(0.04) + 1, "#33691E", 1);
			R.glow(x, y, 0.08, "#C6FF00", 1);

			for k = 1, 4 do
				local q = max(0, p - k * 0.06);
				R.disc(lerp(m.sx, m.tx, q), lerp(m.sy, m.ty, q) + k * 0.03 * cs, 0.04, "#76FF03", 0.5 - k * 0.1);
			end;
		end;

		local ph = phase(t, fly, fly + 1.1);

		if ph ~= nil then
			R.disc(m.tx, m.ty, 0.5 * easeOut(ph * 2), "#64DD17", 0.45 * (1 - ph));
		end;

		drawParticles(splash, t - fly, 1);
	end};
end);

-- Toque Chocante
def("shocking_grasp", "Toque Chocante", "self", "", function(m, cs)
	local seed = rnd(1, 99999);

	return {dur = 0.9, draw = function(t)
		local a = 1 - easeIn(t / 0.9);

		for k = 1, 5 do
			local ang = (k * 72 + t * 400) % 360;
			local dx, dy = FSC.dirVector(ang);
			R.bolt(m.tx, m.ty, m.tx + dx * 0.7 * cs, m.ty + dy * 0.7 * cs, seed + k * 31 + floor(t * 25), 0.25,
			       R.px(0.025) + 1, "#40C4FF", a, false);
		end;

		R.glow(m.tx, m.ty, 0.3, "#80D8FF", a * 0.6);
	end};
end);

-- Curar Ferimentos
def("cure", "Curar Ferimentos", "self", "", function(m, cs)
	local sparkles = burstParticles(m.tx, m.ty + 0.3 * cs, {n = 36, angle = 0, spread = 50, speed = {0.4, 1.0},
	                                                        life = {0.8, 1.4}, size = {0.04, 0.08},
	                                                        colors = {"#B9F6CA", "#FFF59D", "#FFFFFF", "#69F0AE"},
	                                                        delay = {0, 0.7}, startR = 0.4, glow = true});

	return {dur = 2.0, draw = function(t)
		local p = phase(t, 0, 1.8);

		if p ~= nil then
			R.glow(m.tx, m.ty, 0.45 + 0.1 * sin(t * 6), "#69F0AE", 0.35 * bell(p));
			R.ring(m.tx, m.ty, 0.3 + 0.5 * easeOut(p), R.px(0.04) + 1, "#B9F6CA", 0.8 * (1 - p));

			-- cruzes subindo
			for k = 1, 3 do
				local q = clamp01(p * 1.5 - k * 0.15);

				if q > 0 and q < 1 then
					local x = m.tx + (k - 2) * 0.35 * cs;
					local y = m.ty - q * 0.9 * cs;
					local s = 0.09 * cs;
					local a = bell(q);
					R.line(x - s, y, x + s, y, R.px(0.05) + 1, "#00E676", a);
					R.line(x, y - s, x, y + s, R.px(0.05) + 1, "#00E676", a);
				end;
			end;
		end;

		drawParticles(sparkles, t, 1);
	end};
end);

-- Canalizar energia (positiva/negativa)
local function channelEffect(m, cs, rS, ringColor, fillColor, partColors)
	local parts = burstParticles(m.tx, m.ty, {n = 40 + floor(rS * 4), speed = {rS * 0.6, rS * 1.1}, life = {0.8, 1.2},
	                                          size = {0.05, 0.1}, colors = partColors, glow = true, delay = {0, 0.2}});

	return {dur = 1.9, draw = function(t)
		local p = phase(t, 0, 1.3);

		if p ~= nil then
			local rad = rS * easeOut(p);
			R.disc(m.tx, m.ty, rad, fillColor, 0.18 * (1 - p));
			R.ring(m.tx, m.ty, rad, R.px(0.15) * (1 - p) + 2, ringColor, 0.9 * (1 - easeIn(p)));
			R.ring(m.tx, m.ty, rad * 0.8, R.px(0.05) + 1, ringColor, 0.4 * (1 - p));
		end;

		R.glow(m.tx, m.ty, 0.5, ringColor, 0.6 * (1 - clamp01(t / 0.6)));
		drawParticles(parts, t, 1);
	end};
end;

def("channel_positive", "Canalizar Energia Positiva", "area", "30 ft", function(m, cs)
	return channelEffect(m, cs, rsq(m, cs, 6), "#FFE082", "#FFF8E1", {"#FFFFFF", "#FFE082", "#FFF59D"});
end);

def("channel_negative", "Canalizar Energia Negativa", "area", "30 ft", function(m, cs)
	return channelEffect(m, cs, rsq(m, cs, 6), "#7E57C2", "#1A0033", {"#4A148C", "#7E57C2", "#212121"});
end);

-- Luz Cauterizante
def("searing_light", "Luz Cauterizante (raio de luz)", "target", "", function(m, cs)
	local ex = newExplosion(m.tx, m.ty, 1.0, HOLY, 0.2);

	return {dur = 1.4, draw = function(t)
		local p = phase(t, 0, 0.8);

		if p ~= nil then
			local grow = easeOut(min(1, p * 4));
			R.beam(m.sx, m.sy, lerp(m.sx, m.tx, grow), lerp(m.sy, m.ty, grow), 0.16 * (1 - p * 0.5), "#FFD54F", "#FFFFFF",
			       1 - easeIn(p));
		end;

		drawExplosion(ex, t);
	end};
end);

-- Explosão de luz (Explosão Solar / Holy)
def("holy_burst", "Explosão de Luz", "area", "20 ft", function(m, cs)
	local rS = rsq(m, cs, 4);
	local sparks = burstParticles(m.tx, m.ty, {n = 40 + floor(rS * 3), speed = {rS * 0.5, rS * 1.2}, life = {0.6, 1.2},
	                                           size = {0.05, 0.12}, colors = HOLY.embers, glow = true});

	return {dur = 1.8, draw = function(t)
		local p = phase(t, 0, 1.4);

		if p ~= nil then
			R.flash("#FFFDE7", 0.35 * (1 - clamp01(p * 3)));
			local rot = t * 40;

			for k = 0, 11 do
				local a = rot + k * 30;
				local L = rS * cs * easeOut(min(1, p * 2));
				local w = (k % 2 == 0) and 9 or 5;
				local pts = FSC.conePoly(m.tx, m.ty, a, L, w, 2);
				R.poly(pts, "#FFF59D", 0.35 * (1 - p));
			end;

			R.disc(m.tx, m.ty, rS * easeOut(p), "#FFFDE7", 0.25 * (1 - p));
			R.ring(m.tx, m.ty, rS * easeOut(p), R.px(0.1) + 2, "#FFFFFF", 0.9 * (1 - p));
			R.glow(m.tx, m.ty, 0.6 * (1 - p), "#FFFFFF", 1 - p);
		end;

		drawParticles(sparks, t, 1);
	end};
end);

-- Coluna de Chamas
def("flame_strike", "Coluna de Chamas", "area", "10 ft", function(m, cs)
	local rS = rsq(m, cs, 2);
	local ex = newExplosion(m.tx, m.ty, rS, FIRE, 0.35);
	local rising = burstParticles(m.tx, m.ty, {n = 40, angle = 0, spread = 30, speed = {1, 3}, life = {0.5, 1.0},
	                                           size = {0.08, 0.2}, colors = FIRE.embers, delay = {0.35, 0.8},
	                                           startR = rS * 0.8, glow = true});

	return {dur = 2.4, draw = function(t)
		local p = phase(t, 0, 0.35);

		local pcol = phase(t, 0, 0.9);

		if pcol ~= nil then
			-- coluna de fogo descendo do alto da tela
			local scrX = (R.p(m.tx, m.ty));
			local _, topY = R.vp:screenToWorld(scrX, 0);
			local y = lerp(topY, m.ty, easeIn(min(1, pcol / 0.4)));
			local a = 1 - easeIn(clamp01((pcol - 0.4) / 0.6));
			local hw = rS * cs * 0.55;
			R.poly({{m.tx - hw, topY}, {m.tx + hw, topY}, {m.tx + hw, y}, {m.tx - hw, y}}, "#FF6D00", 0.35 * a);
			R.poly({{m.tx - hw * 0.55, topY}, {m.tx + hw * 0.55, topY}, {m.tx + hw * 0.55, y}, {m.tx - hw * 0.55, y}}, "#FFB300", 0.55 * a);
			R.poly({{m.tx - hw * 0.2, topY}, {m.tx + hw * 0.2, topY}, {m.tx + hw * 0.2, y}, {m.tx - hw * 0.2, y}}, "#FFF59D", 0.8 * a);
		end;

		local pc = phase(t, 0.35, 1.4);

		if pc ~= nil then
			R.disc(m.tx, m.ty, rS, "#FF6D00", 0.35 * (1 - pc));
		end;

		drawExplosion(ex, t);
		drawParticles(rising, t, 1);
	end};
end);

-- Convocar Relâmpagos (do céu)
def("call_lightning", "Convocar Relâmpagos (do céu)", "area", "5 ft", function(m, cs)
	local ex = newExplosion(m.tx, m.ty, max(1, rsq(m, cs, 1)), {noSmoke = true, core = "#FFFFFF", mid = "#B3E5FC", outer = "#40C4FF",
	                        ring = "#E1F5FE", flash = "#E1F5FE", embers = {"#FFFFFF", "#80D8FF"}}, 0.12);
	local seed = rnd(1, 99999);

	return {dur = 1.4, draw = function(t)
		local p = phase(t, 0, 0.5);

		if p ~= nil then
			local scrX = (R.p(m.tx, m.ty));
			local tx, ty = R.vp:screenToWorld(scrX + 40, 0);
			local flick = (floor(t * 30) % 2 == 0) and 1 or 0.5;
			R.bolt(tx, ty, m.tx, m.ty, seed + floor(t * 15), 1.2, R.px(0.06) + 1.5, "#40C4FF", flick * (1 - p), true);
			R.flash("#E1F5FE", 0.25 * (1 - p));
		end;

		drawExplosion(ex, t);
	end};
end);

-- Relâmpago em Cadeia
def("chain_lightning", "Relâmpago em Cadeia", "chain", "", function(m, cs)
	local pts = {{m.sx, m.sy}};

	for _, tg in ipairs(m.targets or {{x = m.tx, y = m.ty}}) do
		pts[#pts + 1] = {tg.x, tg.y};
	end;

	local seed = rnd(1, 99999);
	local hits = {};

	for i = 2, #pts do
		hits[i] = burstParticles(pts[i][1], pts[i][2], {n = 12, speed = {0.5, 2.5}, life = {0.2, 0.5}, size = {0.03, 0.06},
		                                                colors = {"#FFFFFF", "#80D8FF"}, glow = true});
	end;

	return {dur = 0.15 * #pts + 1.0, draw = function(t)
		for i = 2, #pts do
			local t0 = (i - 2) * 0.15;
			local p = phase(t, t0, t0 + 0.8);

			if p ~= nil then
				local flick = (floor(t * 30 + i) % 3 == 0) and 0.5 or 1;
				R.bolt(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], seed + i * 77 + floor(t * 20), 0.5,
				       R.px(0.04) + 1, "#40C4FF", flick * (1 - easeIn(p)), false);
				R.glow(pts[i][1], pts[i][2], 0.25, "#80D8FF", 1 - p);
			end;

			drawParticles(hits[i], t - t0, 1);
		end;
	end};
end);

-- Desintegrar
def("disintegrate", "Desintegrar", "target", "", function(m, cs)
	local dust = burstParticles(m.tx, m.ty, {n = 40, angle = 0, spread = 140, speed = {0.3, 1.2}, life = {0.8, 1.6},
	                                         size = {0.03, 0.08}, colors = {"#76FF03", "#9E9E9E", "#CCFF90", "#616161"},
	                                         delay = {0.3, 0.9}, startR = 0.4, gravity = -0.3});

	return {dur = 2.2, draw = function(t)
		local p = phase(t, 0, 0.9);

		if p ~= nil then
			local grow = easeOut(min(1, p * 4));
			R.beam(m.sx, m.sy, lerp(m.sx, m.tx, grow), lerp(m.sy, m.ty, grow), 0.04, "#64DD17", "#F4FF81", 1 - easeIn(p));
			R.glow(m.tx, m.ty, 0.35, "#76FF03", 0.5 * bell(p));
		end;

		drawParticles(dust, t, 1);
	end};
end);

-- Encantamento (Imobilizar Pessoa / Enfeitiçar)
def("enchant", "Encantamento (Imobilizar / Enfeitiçar)", "target", "", function(m, cs)
	return {dur = 1.8, draw = function(t)
		local p = phase(t, 0, 0.5);

		if p ~= nil then
			local x, y = lerp(m.sx, m.tx, easeOut(p)), lerp(m.sy, m.ty, easeOut(p));
			R.glow(x, y, 0.12, "#EA80FC", 1);
		end;

		local pr = phase(t, 0.4, 1.8);

		if pr ~= nil then
			for k = 0, 3 do
				local q = (pr * 1.5 + k * 0.25) % 1;
				local rad = 1.2 * (1 - q);
				R.ring(m.tx, m.ty, rad, R.px(0.04) + 1, (k % 2 == 0) and "#EA80FC" or "#B388FF", bell(q) * (1 - pr));
			end;

			-- espiral
			for k = 0, 10 do
				local a = k * 50 + t * 300;
				local rad = 0.15 + k * 0.06;
				local dx, dy = FSC.dirVector(a);
				R.disc(m.tx + dx * rad * cs, m.ty + dy * rad * cs, 0.04, "#F8BBD0", (1 - pr) * 0.9);
			end;
		end;
	end};
end);

-- Teleporte (Porta Dimensional)
def("teleport", "Porta Dimensional (teleporte)", "target", "", function(m, cs)
	local puff1 = burstParticles(m.sx, m.sy, {n = 30, speed = {0.5, 1.8}, life = {0.4, 0.9}, size = {0.06, 0.14},
	                                          colors = {"#7C4DFF", "#B388FF", "#FFFFFF"}, glow = true, drag = 0.8});
	local puff2 = burstParticles(m.tx, m.ty, {n = 30, speed = {0.5, 1.8}, life = {0.4, 0.9}, size = {0.06, 0.14},
	                                          colors = {"#7C4DFF", "#B388FF", "#FFFFFF"}, glow = true, drag = 0.8});

	return {dur = 1.6, draw = function(t)
		local p1 = phase(t, 0, 0.5);

		if p1 ~= nil then
			R.ring(m.sx, m.sy, 0.7 * (1 - p1), R.px(0.06) + 1, "#B388FF", 1 - p1);
			R.glow(m.sx, m.sy, 0.4 * (1 - p1), "#7C4DFF", 1 - p1);
		end;

		local p2 = phase(t, 0.45, 1.0);

		if p2 ~= nil then
			R.ring(m.tx, m.ty, 0.7 * p2, R.px(0.06) + 1, "#B388FF", 1 - p2);
			R.glow(m.tx, m.ty, 0.4 * (1 - p2), "#7C4DFF", 1 - p2);
		end;

		drawParticles(puff1, t, 1);
		drawParticles(puff2, t - 0.45, 1);
	end};
end);

-- Explosão Sonora / trovão
def("sound_burst", "Explosão Sonora (ondas)", "area", "10 ft", function(m, cs)
	local rS = rsq(m, cs, 2);

	return {dur = 1.2, draw = function(t)
		for k = 0, 2 do
			local p = phase(t, k * 0.15, k * 0.15 + 0.8);

			if p ~= nil then
				R.ring(m.tx, m.ty, rS * easeOut(p), R.px(0.1) * (1 - p) + 1.5, "#ECEFF1", 0.9 * (1 - p));
			end;
		end;

		R.glow(m.tx, m.ty, 0.3, "#FFFFFF", 0.7 * (1 - clamp01(t / 0.4)));
	end};
end);

-- Chuva de Meteoros
def("meteor_swarm", "Chuva de Meteoros", "area", "40 ft", function(m, cs)
	local rS = rsq(m, cs, 8);
	local meteors = {};

	for i = 1, 4 do
		local a = (i - 1) * 90 + rr(-30, 30);
		local d = rS * rr(0.2, 0.55);
		local dx, dy = FSC.dirVector(a);
		local x, y = m.tx + dx * d * cs, m.ty + dy * d * cs;
		local t0 = (i - 1) * 0.25;
		meteors[i] = {x = x, y = y, t0 = t0, ex = newExplosion(x, y, max(1.5, rS * 0.45), FIRE, t0 + 0.45)};
	end;

	return {dur = 3.4, draw = function(t)
		for _, mt in ipairs(meteors) do
			local p = phase(t, mt.t0, mt.t0 + 0.45);

			if p ~= nil then
				local sx = mt.x - 6 * cs;
				local sy = mt.y - 9 * cs;
				drawProjectile(sx, sy, mt.x, mt.y, easeIn(p), 0.35, "#FF3D00", "#FFF59D", 10);
			end;

			drawExplosion(mt.ex, t);
		end;
	end};
end);

-- Tempestade de Gelo
def("ice_storm", "Tempestade de Gelo (granizo)", "area", "20 ft", function(m, cs)
	local rS = rsq(m, cs, 4);
	local hail = {};

	for i = 1, 60 do
		local a, d = rr(0, 360), rS * sqrt(rnd());
		local dx, dy = FSC.dirVector(a);
		hail[i] = {x = m.tx + dx * d * cs, y = m.ty + dy * d * cs, t0 = rr(0, 1.2)};
	end;

	return {dur = 2.3, draw = function(t)
		local pa = phase(t, 0, 2.0);

		if pa ~= nil then
			R.disc(m.tx, m.ty, rS, "#B3E5FC", 0.18 * bell(pa));
			R.ring(m.tx, m.ty, rS, 2, "#E1F5FE", 0.7 * bell(pa));
		end;

		for _, h in ipairs(hail) do
			local p = phase(t, h.t0, h.t0 + 0.3);

			if p ~= nil then
				local y0 = h.y - 1.5 * cs;
				local y = lerp(y0, h.y, easeIn(p));
				R.line(h.x - 0.2 * cs * (1 - p), y - 0.3 * cs, h.x, y, R.px(0.04) + 1, "#FFFFFF", 0.9);
			end;

			local pi2 = phase(t, h.t0 + 0.3, h.t0 + 0.6);

			if pi2 ~= nil then
				R.ring(h.x, h.y, 0.15 * pi2 + 0.03, 1, "#FFFFFF", 1 - pi2);
			end;
		end;
	end};
end);

-- Pó Reluzente
def("glitterdust", "Pó Reluzente", "area", "10 ft", function(m, cs)
	local rS = rsq(m, cs, 2);
	local motes = {};

	for i = 1, 80 do
		local a, d = rr(0, 360), rS * sqrt(rnd());
		local dx, dy = FSC.dirVector(a);
		motes[i] = {x = m.tx + dx * d * cs, y = m.ty + dy * d * cs, p = rr(0, 2 * pi), t0 = rr(0, 0.5)};
	end;

	return {dur = 2.6, draw = function(t)
		local fade = 1 - clamp01((t - 1.8) / 0.8);

		for _, mo in ipairs(motes) do
			if t > mo.t0 then
				local tw = 0.5 + 0.5 * sin(t * 9 + mo.p);
				R.disc(mo.x, mo.y + (t - mo.t0) * 0.15 * cs, 0.035 + 0.03 * tw, "#FFD740", (0.4 + 0.6 * tw) * fade);
			end;
		end;
	end};
end);

-- Nuvem venenosa (Nuvem Fétida / Névoa Mortal)
def("poison_cloud", "Nuvem Venenosa", "area", "20 ft", function(m, cs)
	local rS = rsq(m, cs, 4);
	local puffs = burstParticles(m.tx, m.ty, {n = 26, speed = {rS * 0.2, rS * 0.6}, life = {1.8, 2.6},
	                                          size = {rS * 0.2, rS * 0.35}, colors = {"#9CCC65", "#7CB342", "#C5E1A5", "#AED581"},
	                                          grow = 0.8, drag = 0.9, fadeIn = 0.25, startR = rS * 0.3, delay = {0, 0.4}});

	return {dur = 3.0, draw = function(t)
		drawParticles(puffs, t, 0.35);
	end};
end);

-- Escuridão
def("darkness", "Escuridão", "area", "20 ft", function(m, cs)
	local rS = rsq(m, cs, 4);
	local wisps = burstParticles(m.tx, m.ty, {n = 30, speed = {0.2, 0.6}, life = {1.5, 2.5}, size = {0.3, 0.6},
	                                          colors = {"#000000", "#1A1A2E", "#212121"}, startR = rS * 0.9, grow = 0.5,
	                                          fadeIn = 0.3});

	return {dur = 3.0, draw = function(t)
		local grow = easeOut(clamp01(t / 0.8));
		local fade = 1 - clamp01((t - 2.2) / 0.8);

		for k = 1, 4 do
			R.disc(m.tx, m.ty, rS * grow * (1.05 - k * 0.1), "#05050F", 0.22 * fade);
		end;

		drawParticles(wisps, t, 0.6 * fade);
	end};
end);

-- Golpe (corte) genérico
def("slash", "Golpe / Corte", "self", "", function(m, cs)
	local ang = rr(0, 360);

	return {dur = 0.5, draw = function(t)
		local p = clamp01(t / 0.35);
		local a = 1 - easeIn(clamp01(t / 0.5));
		local pts = {};

		for k = 0, 10 do
			local q = k / 10 * p;
			local aa = ang - 60 + 120 * q;
			local dx, dy = FSC.dirVector(aa);
			pts[#pts + 1] = {m.tx + dx * 0.55 * cs, m.ty + dy * 0.55 * cs};
		end;

		for k = 1, #pts - 1 do
			local w = R.px(0.08) * (k / #pts) + 1;
			R.line(pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2], w, "#FFFFFF", a);
		end;
	end};
end);

-- Flecha
def("arrow", "Flecha / projétil físico", "target", "", function(m, cs)
	local fly = max(0.2, min(0.5, dist(m.sx, m.sy, m.tx, m.ty) / cs * 0.02));

	return {dur = fly + 0.3, draw = function(t)
		local p = phase(t, 0, fly);
		local ang = angleBetween(m.sx, m.sy, m.tx, m.ty);
		local dx, dy = FSC.dirVector(ang);

		if p ~= nil then
			local x, y = lerp(m.sx, m.tx, p), lerp(m.sy, m.ty, p);
			R.line(x - dx * 0.5 * cs, y - dy * 0.5 * cs, x, y, R.px(0.03) + 1, "#8D6E63", 1);
			R.line(x - dx * 0.5 * cs, y - dy * 0.5 * cs, x - dx * 0.35 * cs, y - dy * 0.35 * cs, R.px(0.07) + 1, "#ECEFF1", 0.9);
		end;

		local ph = phase(t, fly, fly + 0.3);

		if ph ~= nil then
			R.ring(m.tx, m.ty, 0.1 + 0.25 * ph, 1.5, "#FFFFFF", 1 - ph);
		end;
	end};
end);

-- Bênção / Proteção (anéis subindo)
def("buff", "Bênção / Proteção", "self", "", function(m, cs)
	local motes = burstParticles(m.tx, m.ty + 0.3 * cs, {n = 24, angle = 0, spread = 30, speed = {0.4, 0.9}, life = {0.8, 1.2},
	                                                     size = {0.03, 0.06}, colors = {"#82B1FF", "#FFFFFF", "#FFE57F"},
	                                                     delay = {0, 0.6}, startR = 0.4, glow = true});

	return {dur = 1.8, draw = function(t)
		for k = 0, 2 do
			local p = phase(t, k * 0.25, k * 0.25 + 1.0);

			if p ~= nil then
				local sx, sy = R.p(m.tx, m.ty - p * 0.6 * cs);
				local rx, ry = R.px(0.55), R.px(0.18);
				R.vp:prepareDraw((k % 2 == 0) and "#82B1FF" or "#FFE57F", 2);
				R.vp:drawEllipse(sx - rx, sy - ry, sx + rx, sy + ry, bell(p));
			end;
		end;

		drawParticles(motes, t, 1);
	end};
end);

-- Energia negativa (Infligir / Raio de Enfraquecimento)
def("negative_ray", "Energia Negativa (raio)", "target", "", function(m, cs)
	local wisps = burstParticles(m.tx, m.ty, {n = 26, angle = 0, spread = 360, speed = {0.2, 0.8}, life = {0.6, 1.2},
	                                          size = {0.06, 0.14}, colors = {"#4A148C", "#000000", "#7B1FA2"},
	                                          delay = {0.25, 0.6}, grow = 1});

	return {dur = 1.8, draw = function(t)
		local p = phase(t, 0, 0.8);

		if p ~= nil then
			local grow = easeOut(min(1, p * 4));
			R.beam(m.sx, m.sy, lerp(m.sx, m.tx, grow), lerp(m.sy, m.ty, grow), 0.07, "#4A148C", "#CE93D8", 1 - easeIn(p));
		end;

		drawParticles(wisps, t, 0.9);
	end};
end);

----------------------------------------------------------------------
-- Motor por scene
----------------------------------------------------------------------

local function newEngine(scene)
	local eng = {active = {}, listener = nil, interval = nil};
	local viewport = scene.viewport;

	local function stop()
		if eng.listener ~= nil then
			viewport:unlisten(eng.listener);
			eng.listener = nil;
		end;

		if eng.interval ~= nil then
			clearInterval(eng.interval);
			eng.interval = nil;
		end;

		viewport:needRepaint();
	end;

	local function draw()
		local tn = now();
		R.begin(viewport, scene);
		local keep = {};

		for _, e in ipairs(eng.active) do
			local t = tn - e.t0;

			if t <= e.dur then
				local ok, err = pcall(e.draw, t);

				if ok then
					keep[#keep + 1] = e;
				else
					FSC.logError("SceneSuite.Animacoes", err);
				end;
			end;
		end;

		eng.active = keep;

		if #keep == 0 then
			-- encerra no próximo ciclo (não dá para remover o listener durante o próprio evento)
			setTimeout(function()
				if #eng.active == 0 then
					stop();
				end;
			end, 1);
		end;
	end;

	function eng:play(m)
		local d = FX[m.fx];

		if d == nil then
			return;
		end;

		local cs = FSC.cellSize(scene);
		local ok, e = pcall(d.build, m, cs);

		if not ok or e == nil then
			FSC.logError("SceneSuite.Animacoes", tostring(m.fx) .. ": " .. tostring(e));
			return;
		end;

		e.t0 = now();
		self.active[#self.active + 1] = e;

		if self.listener == nil then
			self.listener = viewport:listen("onAfterDrawLayers", draw);
		end;

		if self.interval == nil then
			self.interval = setInterval(function()
				if scene.isObjectAlive then
					viewport:needRepaint();
				end;
			end, FRAME_MS);
		end;
	end;

	function eng:stopAll()
		self.active = {};
		stop();
	end;

	-- recebe animações (inclusive as próprias, via loopBack)
	eng.broadcastListener = scene:newBroadcastListener(FX_MESSAGE, function(sender, messageId, message)
		if type(message) == "table" and type(message.fx) == "string" and type(message.sx) == "number"
		   and type(message.sy) == "number" then
			message.tx = tonumber(message.tx) or message.sx;
			message.ty = tonumber(message.ty) or message.sy;
			eng:play(message);
		end;
	end);

	return eng;
end;

----------------------------------------------------------------------
-- Ferramenta
----------------------------------------------------------------------

local KIND_HINT = {
	target = "Selecione o conjurador (ou clique na origem) e clique no alvo.",
	cone = "Selecione o conjurador (ou clique na origem) e clique na direção do cone.",
	line = "Selecione o conjurador (ou clique na origem) e clique na direção da linha.",
	area = "Clique no centro da área.",
	self = "Clique no token (ou ponto) que recebe o efeito.",
	chain = "Selecione o conjurador (ou clique na origem), clique nos alvos e use o botão direito / ENTER para disparar."
};

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local eng = newEngine(scene);
	local frm = nil;
	local cfg = nil;
	local listeners = {};
	local pending = nil;   -- {sx, sy, targets = {...}}

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Animações de Magia", 55);

	local function sizeSq(d)
		local txt = (cfg and cfg.size ~= "" and cfg.size) or d.size;

		if txt == nil or txt == "" then
			return nil;
		end;

		return FSC.parseDistance(txt, scene, "ft");
	end;

	local function send(d, sx, sy, tx, ty, targets)
		local cs = FSC.cellSize(scene);
		local sq = sizeSq(d);
		local msg = {fx = d.id, sx = sx, sy = sy, tx = tx, ty = ty,
		             n = tonumber(cfg and cfg.count) or 3,
		             angle = angleBetween(sx, sy, tx, ty)};

		if sq ~= nil then
			msg.r = sq * cs;
		end;

		if targets ~= nil then
			msg.targets = targets;
		end;

		scene:broadcastMessage(FX_MESSAGE, msg, true);
	end;

	-- ponto clicado: centro do token sob o mouse, se houver
	local function pickPoint(event)
		local tk, wx, wy = FSC.tokenAt(scene, event.x, event.y);

		if tk ~= nil then
			return tk:getCenter(false);
		end;

		return wx, wy;
	end;

	local function casterPoint()
		local sel = FSC.selectedTokens(scene);

		if #sel > 0 then
			return sel[1]:getCenter(false);
		end;

		return nil;
	end;

	local function fireChain(d)
		if pending ~= nil and #pending.targets > 0 then
			local last = pending.targets[#pending.targets];
			send(d, pending.sx, pending.sy, last.x, last.y, pending.targets);
		end;

		pending = nil;
		viewport:needRepaint();
	end;

	local function onMouseDown(event)
		if cfg == nil then return; end;
		local d = FX[cfg.fx];
		if d == nil then return; end;

		if event.button == "right" then
			if d.kind == "chain" then
				fireChain(d);
			else
				pending = nil;
				viewport:needRepaint();
			end;

			return;
		end;

		if event.button ~= "left" then return; end;

		local px, py = pickPoint(event);

		if d.kind == "area" or d.kind == "self" then
			send(d, px, py, px, py);
			return;
		end;

		if pending == nil then
			local cx, cy = casterPoint();

			if cx ~= nil and (abs(cx - px) > 0.01 or abs(cy - py) > 0.01) then
				pending = {sx = cx, sy = cy, targets = {}};
			else
				pending = {sx = px, sy = py, targets = {}};
				viewport:needRepaint();
				return;
			end;
		end;

		if d.kind == "chain" then
			pending.targets[#pending.targets + 1] = {x = px, y = py};

			if #pending.targets >= 8 then
				fireChain(d);
			end;

			viewport:needRepaint();
			return;
		end;

		send(d, pending.sx, pending.sy, px, py);
		pending = nil;
		viewport:needRepaint();
	end;

	local function onKeyDown(event)
		if event.keyCode == 13 and cfg ~= nil and FX[cfg.fx] ~= nil and FX[cfg.fx].kind == "chain" then
			fireChain(FX[cfg.fx]);
			event.keyCode = 0;
		elseif event.keyCode == 27 and pending ~= nil then
			pending = nil;
			viewport:needRepaint();
			event.keyCode = 0;
		end;
	end;

	-- marcador local da origem/alvos pendentes
	local function drawPending()
		if pending == nil then return; end;

		local sx, sy = viewport:worldToScreen(pending.sx, pending.sy);
		viewport:prepareDraw("#FFCC66", 2);
		viewport:drawEllipse(sx - 8, sy - 8, sx + 8, sy + 8, 1);

		local lx, ly = sx, sy;

		for _, tg in ipairs(pending.targets) do
			local tx, ty = viewport:worldToScreen(tg.x, tg.y);
			viewport:prepareDraw("#80D8FF", 1.5, "round", "round", "dash");
			viewport:drawLine(lx, ly, tx, ty, 0.8);
			viewport:prepareDraw("#80D8FF", 2);
			viewport:drawEllipse(tx - 6, ty - 6, tx + 6, ty + 6, 1);
			lx, ly = tx, ty;
		end;
	end;

	local items, values = {}, {};

	for _, id in ipairs(FX_ORDER) do
		items[#items + 1] = FX[id].name;
		values[#values + 1] = id;
	end;

	viewport:addToolButton(TOOL_CATEGORY, "Animações de magia",
		"/images/tool_fx.png", 60, {selectable = true, defaultOfCategory = true},
		function()
			if FSC.isSpectator(scene) then
				return;
			end;

			if frm == nil then
				frm = GUI.newForm("frmFSSpellFX");
			end;

			frm:prepareFor({
				items = items,
				values = values,
				defaultSize = function(id)
					return FX[id] and FX[id].size or "";
				end,
				onChange = function(c)
					cfg = c;
					pending = nil;
					local d = FX[c.fx];

					if d == nil then
						return "", false;
					end;

					local hint = KIND_HINT[d.kind] or "";
					local sq, feet = nil, nil;

					if c.size ~= "" then
						sq, feet = FSC.parseDistance(c.size, scene, "ft");
					end;

					if sq ~= nil then
						hint = hint .. "\nTamanho: " .. FSC.formatFeet(feet) .. " = " .. FSC.fmtNum(sq) .. " quadrado(s).";
					end;

					return hint, d.count == true;
				end,
				onClose = function()
					viewport:selectDefaultToolButton();
				end
			});

			viewport:showForm(frm, {placement = "topLeft"});
			listeners[#listeners + 1] = viewport:listen("onMouseDown", onMouseDown);
			listeners[#listeners + 1] = viewport:listen("onKeyDown", onKeyDown);
			listeners[#listeners + 1] = viewport:listen("onAfterDrawLayers", drawPending);
			viewport.cursor = "cross";
		end,
		function()
			for _, l in ipairs(listeners) do
				viewport:unlisten(l);
			end;

			listeners = {};
			pending = nil;
			viewport.cursor = "default";

			if frm ~= nil then
				viewport:closeForm(frm);
			end;

			viewport:needRepaint();
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Animações: parar todas (só para mim)",
		"/images/tool_stop.png", 61, {dontFocus = true},
		function()
			eng:stopAll();
		end);
end);
