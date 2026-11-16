--[[
  Scene Suite - Clima
  Efeitos visuais sobre o Scene: chuva, tempestade, neve, nevasca, névoa,
  vendaval, tempestade de areia, cinzas/brasas, folhas, noite, submerso e
  vaga-lumes.

  - O mestre escolhe o efeito; a escolha fica em scene.userData.fsWeather e
    todos que têm o plugin veem o mesmo clima.
  - O desenho é feito na tela (evento onAfterDrawLayers do viewport): não é
    um objeto do tabuleiro, então NÃO captura cliques nem atrapalha a seleção
    de tokens.
  - Cada usuário pode desligar o efeito só para si (desempenho/preferência).
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
local UD_FIELD = "fsWeather";
local TOOL_CATEGORY = "SSuite_Weather";
local FRAME_MS = 40;

local rnd = math.random;
local sin, cos, pi, floor, max, min = math.sin, math.cos, math.pi, math.floor, math.max, math.min;

local function rr(a, b)
	return a + (b - a) * rnd();
end;

local function now()
	return system.getTickCount() / 1000;
end;

----------------------------------------------------------------------
-- Definição dos efeitos
-- Cada efeito: init(st) cria partículas; draw(st, vp, W, H, dt, k) desenha.
-- Coordenadas das partículas normalizadas (0..1) na tela.
-- k = alpha global (opacidade escolhida)
----------------------------------------------------------------------

local EFFECTS = {};

local function overlay(vp, W, H, color, alpha)
	if alpha > 0.003 then
		vp:prepareFill(color);
		vp:fillRect(0, 0, W, H, min(1, alpha));
	end;
end;

-- vinheta (bordas mais escuras)
local function vignette(vp, W, H, color, alpha)
	vp:prepareFill(color);
	local steps = 16;

	-- faixas cada vez mais estreitas e leves; somadas formam um degradê suave
	for i = 0, steps - 1 do
		local f = i / steps;
		local bw = W * 0.22 * (1 - f) ^ 1.5;
		local bh = H * 0.22 * (1 - f) ^ 1.5;
		local a = alpha * 0.07;
		vp:fillRect(0, 0, W, bh, a);
		vp:fillRect(0, H - bh, W, H, a);
		vp:fillRect(0, bh, bw, H - bh, a);
		vp:fillRect(W - bw, bh, W, H - bh, a);
	end;
end;

-- Partículas de queda (chuva/neve) reaproveitáveis
local function spawnFall(n, speedMin, speedMax, sizeMin, sizeMax)
	local list = {};

	for i = 1, n do
		list[i] = {x = rnd(), y = rnd(), v = rr(speedMin, speedMax), s = rr(sizeMin, sizeMax), p = rr(0, 2 * pi)};
	end;

	return list;
end;

local function stepFall(list, dt, wind, sway, t)
	for _, d in ipairs(list) do
		d.y = d.y + d.v * dt;
		d.x = d.x + (wind * d.v + (sway > 0 and sin(t * 1.5 + d.p) * sway or 0)) * dt;

		if d.y > 1.05 then
			d.y = -0.05;
			d.x = rnd();
		end;

		if d.x > 1.05 then
			d.x = d.x - 1.1;
		elseif d.x < -0.05 then
			d.x = d.x + 1.1;
		end;
	end;
end;

-- Chuva
local function drawRain(st, vp, W, H, k, color, thick, lenF, alpha)
	vp:prepareDraw(color, thick, "round");

	for _, d in ipairs(st.drops) do
		local x, y = d.x * W, d.y * H;
		local len = d.s * H * lenF;
		local wx = st.wind;
		vp:drawLine(x, y, x - wx * len, y - len, alpha * k);
	end;
end;

EFFECTS.rain = {
	init = function(st)
		st.drops = spawnFall(70 * st.intensity, 1.3, 1.9, 0.025, 0.045);
	end,
	draw = function(st, vp, W, H, dt, k, t)
		stepFall(st.drops, dt, st.wind, 0, t);
		overlay(vp, W, H, "#1C2833", 0.06 * st.intensity * k);
		drawRain(st, vp, W, H, k, "#B3CDE0", 1.2, 1, 0.55);
	end
};

EFFECTS.storm = {
	init = function(st)
		st.drops = spawnFall(110 * st.intensity, 1.8, 2.6, 0.03, 0.06);
		st.nextBolt = now() + rr(3, 7);
		st.flash = 0;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		stepFall(st.drops, dt, st.wind * 1.4, 0, t);
		overlay(vp, W, H, "#0B1320", (0.12 + 0.06 * st.intensity) * k);
		drawRain(st, vp, W, H, k, "#C9D6DF", 1.3, 1.1, 0.6);

		local tn = now();

		if tn >= st.nextBolt then
			st.flash = 1;
			st.boltX = rr(0.1, 0.9);
			st.boltSeed = rnd(1, 100000);
			st.nextBolt = tn + rr(4, 11) / st.intensity;
		end;

		if st.flash > 0 then
			-- clarão duplo
			local f = st.flash;
			local a = (f > 0.75 and 0.55 or (f > 0.55 and 0.15 or (f > 0.4 and 0.4 or 0.4 * f / 0.4)));
			overlay(vp, W, H, "#E8F1FF", a * k);

			if f > 0.45 then
				local x, y = st.boltX * W, 0;
				local seed = st.boltSeed;
				vp:prepareDraw("#FFFFFF", 2.5, "round", "round");

				for i = 1, 9 do
					seed = (seed * 1103515245 + 12345) % 2147483648;
					local nx = x + ((seed % 1000) / 1000 - 0.5) * W * 0.08;
					local ny = y + H * 0.07;
					vp:drawLine(x, y, nx, ny, k);
					x, y = nx, ny;
				end;
			end;

			st.flash = st.flash - dt * 2.2;
		end;
	end
};

local function drawFlakes(st, vp, W, H, k, color, alpha)
	vp:prepareFill(color);

	for _, d in ipairs(st.flakes) do
		local x, y = d.x * W, d.y * H;
		local r = d.s;
		vp:fillEllipse(x - r, y - r, x + r, y + r, alpha * k);
	end;
end;

EFFECTS.snow = {
	init = function(st)
		st.flakes = spawnFall(60 * st.intensity, 0.06, 0.16, 1.2, 3.5);
	end,
	draw = function(st, vp, W, H, dt, k, t)
		stepFall(st.flakes, dt, st.wind * 0.6, 0.03, t);
		overlay(vp, W, H, "#DDE6EE", 0.04 * st.intensity * k);
		drawFlakes(st, vp, W, H, k, "#FFFFFF", 0.85);
	end
};

EFFECTS.blizzard = {
	init = function(st)
		st.flakes = spawnFall(160 * st.intensity, 0.35, 0.7, 1, 3);
		st.streaks = spawnFall(20 * st.intensity, 0.4, 0.8, 0.05, 0.12);
	end,
	draw = function(st, vp, W, H, dt, k, t)
		local wind = (st.wind ~= 0) and st.wind * 3 or 1.5;
		stepFall(st.flakes, dt, wind, 0.05, t);
		stepFall(st.streaks, dt, wind, 0, t);
		overlay(vp, W, H, "#EEF3F7", (0.12 + 0.07 * st.intensity) * k);
		drawFlakes(st, vp, W, H, k, "#FFFFFF", 0.9);
		vp:prepareDraw("#FFFFFF", 1, "round");

		for _, d in ipairs(st.streaks) do
			local x, y = d.x * W, d.y * H;
			local len = d.s * W;
			local dir = wind > 0 and 1 or -1;
			vp:drawLine(x, y, x - dir * len, y - len * 0.25, 0.35 * k);
		end;
	end
};

EFFECTS.fog = {
	init = function(st)
		st.blobs = {};

		for i = 1, 7 + 3 * st.intensity do
			st.blobs[i] = {x = rr(-0.2, 1.2), y = rr(-0.1, 1.1), r = rr(0.18, 0.4), v = rr(0.004, 0.015),
			               a = rr(0.05, 0.1), p = rr(0, 2 * pi)};
		end;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		local wind = (st.wind ~= 0) and st.wind or 0.1;
		overlay(vp, W, H, "#C7D0D8", (0.04 + 0.04 * st.intensity) * k);
		vp:prepareFill("#E3E9EE");
		local M = max(W, H);

		for _, b in ipairs(st.blobs) do
			b.x = b.x + wind * b.v * dt * 4;

			if b.x > 1.4 then
				b.x = -0.4;
			elseif b.x < -0.4 then
				b.x = 1.4;
			end;

			local cx = b.x * W;
			local cy = (b.y + sin(t * 0.15 + b.p) * 0.02) * H;
			local pulse = 1 + 0.06 * sin(t * 0.3 + b.p);

			-- bordas suaves: 3 elipses concêntricas
			for layer = 1, 3 do
				local r = b.r * M * pulse * (1.25 - layer * 0.2);
				vp:fillEllipse(cx - r * 1.6, cy - r * 0.8, cx + r * 1.6, cy + r * 0.8, b.a * k * (0.3 + 0.15 * layer) * (st.intensity / 2.5));
			end;
		end;
	end
};

EFFECTS.wind = {
	init = function(st)
		st.lines = {};

		for i = 1, 25 * st.intensity do
			st.lines[i] = {x = rnd(), y = rnd(), v = rr(0.6, 1.4), len = rr(0.06, 0.2), p = rr(0, 2 * pi)};
		end;

		st.debris = {};

		for i = 1, 6 + 5 * st.intensity do
			st.debris[i] = {x = rnd(), y = rnd(), v = rr(0.3, 0.7), s = rr(3, 6), rot = rr(0, 2 * pi),
			                c = (rnd() < 0.5) and "#8D6E63" or "#7CB342", p = rr(0, 2 * pi)};
		end;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		local dir = (st.wind < 0) and -1 or 1;
		local strength = max(0.5, math.abs(st.wind) * 2);
		vp:prepareDraw("#FFFFFF", 1.3, "round");

		for _, l in ipairs(st.lines) do
			l.x = l.x + dir * l.v * strength * dt;

			if l.x > 1.25 then
				l.x = -0.25; l.y = rnd();
			elseif l.x < -0.25 then
				l.x = 1.25; l.y = rnd();
			end;

			local x = l.x * W;
			local y = (l.y + sin(t * 2 + l.p + l.x * 6) * 0.01) * H;
			local len = l.len * W;
			local seg = 4;
			local px, py = x, y;

			for s = 1, seg do
				local nx = x - dir * len * s / seg;
				local ny = y + sin(t * 3 + l.p + s) * 2;
				vp:drawLine(px, py, nx, ny, 0.45 * k * (1 - s / (seg + 1)));
				px, py = nx, ny;
			end;
		end;

		for _, d in ipairs(st.debris) do
			d.x = d.x + dir * d.v * strength * dt;
			d.y = d.y + sin(t * 2 + d.p) * 0.08 * dt;
			d.rot = d.rot + dt * 6;

			if d.x > 1.05 then
				d.x = -0.05; d.y = rnd();
			elseif d.x < -0.05 then
				d.x = 1.05; d.y = rnd();
			end;

			local cx, cy = d.x * W, d.y * H;
			local s = d.s;
			local c, sn = cos(d.rot), sin(d.rot);
			vp:prepareFill(d.c);
			vp:fillPolygon({{x = cx + c * s, y = cy + sn * s}, {x = cx - sn * s * 0.45, y = cy + c * s * 0.45},
			                {x = cx - c * s, y = cy - sn * s}, {x = cx + sn * s * 0.45, y = cy - c * s * 0.45}}, 0.85 * k);
		end;
	end
};

EFFECTS.sand = {
	init = function(st)
		st.grains = {};

		for i = 1, 110 * st.intensity do
			st.grains[i] = {x = rnd(), y = rnd(), v = rr(0.4, 1.1), s = rr(0.8, 2.2)};
		end;

		st.streaks = spawnFall(15 * st.intensity, 0.5, 1, 0.08, 0.2);
	end,
	draw = function(st, vp, W, H, dt, k, t)
		local dir = (st.wind < 0) and -1 or 1;
		overlay(vp, W, H, "#C49A5A", (0.14 + 0.08 * st.intensity) * k);
		vp:prepareFill("#E0B97A");

		for _, g in ipairs(st.grains) do
			g.x = g.x + dir * g.v * dt;
			g.y = g.y + sin(t * 3 + g.x * 10) * 0.02 * dt;

			if g.x > 1.02 then g.x = -0.02; g.y = rnd(); elseif g.x < -0.02 then g.x = 1.02; g.y = rnd(); end;

			local x, y = g.x * W, g.y * H;
			vp:fillEllipse(x - g.s, y - g.s, x + g.s, y + g.s, 0.7 * k);
		end;

		vp:prepareDraw("#F1D3A1", 1.5, "round");

		for _, d in ipairs(st.streaks) do
			d.x = d.x + dir * d.v * dt;

			if d.x > 1.2 then d.x = -0.2; d.y = rnd(); elseif d.x < -0.2 then d.x = 1.2; d.y = rnd(); end;

			local x, y = d.x * W, d.y * H;
			vp:drawLine(x, y, x - dir * d.s * W, y, 0.3 * k);
		end;
	end
};

EFFECTS.embers = {
	init = function(st)
		st.embers = {};

		for i = 1, 35 * st.intensity do
			st.embers[i] = {x = rnd(), y = rnd(), v = rr(0.04, 0.12), s = rr(1.2, 2.8), p = rr(0, 2 * pi),
			                c = (rnd() < 0.6) and "#FF8F00" or "#FF3D00"};
		end;

		st.ash = spawnFall(30 * st.intensity, 0.02, 0.06, 1, 2.5);
	end,
	draw = function(st, vp, W, H, dt, k, t)
		overlay(vp, W, H, "#3E1F0E", 0.06 * st.intensity * k);
		stepFall(st.ash, dt, st.wind * 0.5, 0.02, t);
		drawFlakes({flakes = st.ash}, vp, W, H, k, "#9E9E9E", 0.6);

		for _, e in ipairs(st.embers) do
			e.y = e.y - e.v * dt;
			e.x = e.x + (sin(t * 1.3 + e.p) * 0.02 + st.wind * 0.05) * dt;

			if e.y < -0.03 then e.y = 1.03; e.x = rnd(); end;

			local x, y = e.x * W, e.y * H;
			local flick = 0.55 + 0.45 * sin(t * 7 + e.p * 3);
			vp:prepareFill(e.c);
			vp:fillEllipse(x - e.s * 2.2, y - e.s * 2.2, x + e.s * 2.2, y + e.s * 2.2, 0.15 * flick * k);
			vp:fillEllipse(x - e.s, y - e.s, x + e.s, y + e.s, 0.9 * flick * k);
		end;
	end
};

EFFECTS.leaves = {
	init = function(st)
		local colors = {"#E65100", "#F9A825", "#8D6E63", "#C62828", "#7CB342"};
		st.leaves = {};

		for i = 1, 12 * st.intensity do
			st.leaves[i] = {x = rnd(), y = rnd(), v = rr(0.05, 0.12), s = rr(4, 7), rot = rr(0, 2 * pi),
			                vr = rr(-3, 3), p = rr(0, 2 * pi), c = colors[rnd(1, #colors)]};
		end;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		for _, l in ipairs(st.leaves) do
			l.y = l.y + l.v * dt;
			l.x = l.x + (sin(t + l.p) * 0.05 + st.wind * 0.15) * dt;
			l.rot = l.rot + l.vr * dt;

			if l.y > 1.05 then l.y = -0.05; l.x = rnd(); end;
			if l.x > 1.05 then l.x = -0.05; elseif l.x < -0.05 then l.x = 1.05; end;

			local cx, cy, s = l.x * W, l.y * H, l.s;
			local c, sn = cos(l.rot), sin(l.rot);
			vp:prepareFill(l.c);
			vp:fillPolygon({{x = cx + c * s, y = cy + sn * s}, {x = cx - sn * s * 0.4, y = cy + c * s * 0.4},
			                {x = cx - c * s, y = cy - sn * s}, {x = cx + sn * s * 0.4, y = cy - c * s * 0.4}}, 0.9 * k);
		end;
	end
};

EFFECTS.night = {
	init = function(st) end,
	draw = function(st, vp, W, H, dt, k, t)
		overlay(vp, W, H, "#0A1030", (0.18 + 0.12 * st.intensity) * k);
		vignette(vp, W, H, "#000010", (0.5 + 0.2 * st.intensity) * k);
	end
};

EFFECTS.underwater = {
	init = function(st)
		st.bubbles = {};

		for i = 1, 18 * st.intensity do
			st.bubbles[i] = {x = rnd(), y = rnd(), v = rr(0.05, 0.15), s = rr(2, 6), p = rr(0, 2 * pi)};
		end;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		overlay(vp, W, H, "#0E6B7A", (0.14 + 0.06 * st.intensity) * k);

		-- faixas de luz ondulando
		vp:prepareFill("#BFF6FF");

		for i = 0, 4 do
			local x = (i / 4 + sin(t * 0.2 + i) * 0.05) * W;
			vp:fillPolygon({{x = x - W * 0.03, y = 0}, {x = x + W * 0.03, y = 0},
			                {x = x + W * 0.12, y = H}, {x = x - W * 0.02, y = H}}, 0.035 * k);
		end;

		vp:prepareDraw("#E0FFFF", 1.2);

		for _, b in ipairs(st.bubbles) do
			b.y = b.y - b.v * dt;
			b.x = b.x + sin(t * 2 + b.p) * 0.01 * dt;

			if b.y < -0.03 then b.y = 1.03; b.x = rnd(); end;

			local x, y = b.x * W, b.y * H;
			vp:drawEllipse(x - b.s, y - b.s, x + b.s, y + b.s, 0.6 * k);
		end;
	end
};

EFFECTS.fireflies = {
	init = function(st)
		st.flies = {};

		for i = 1, 14 * st.intensity do
			st.flies[i] = {x = rnd(), y = rnd(), vx = rr(-0.02, 0.02), vy = rr(-0.02, 0.02), p = rr(0, 2 * pi),
			               s = rr(1.5, 2.5)};
		end;
	end,
	draw = function(st, vp, W, H, dt, k, t)
		overlay(vp, W, H, "#06140A", 0.12 * st.intensity * k);
		vp:prepareFill("#E6FF8A");

		for _, f in ipairs(st.flies) do
			f.vx = max(-0.03, min(0.03, f.vx + rr(-0.02, 0.02) * dt));
			f.vy = max(-0.03, min(0.03, f.vy + rr(-0.02, 0.02) * dt));
			f.x = (f.x + f.vx * dt) % 1;
			f.y = (f.y + f.vy * dt) % 1;
			local glow = max(0, sin(t * 1.7 + f.p));
			local x, y = f.x * W, f.y * H;
			vp:fillEllipse(x - f.s * 4, y - f.s * 4, x + f.s * 4, y + f.s * 4, 0.12 * glow * k);
			vp:fillEllipse(x - f.s, y - f.s, x + f.s, y + f.s, 0.95 * glow * k);
		end;
	end
};

----------------------------------------------------------------------
-- Motor por scene
----------------------------------------------------------------------

local function readConfig(scene)
	local ud = scene.userData;
	local raw = ud and ud[UD_FIELD] or "";
	return FSC.decode(raw), raw;
end;

local function newEngine(scene)
	local eng = {raw = nil, st = nil, listener = nil, interval = nil, poll = nil,
	             localOff = false, last = nil};
	local viewport = scene.viewport;

	local function stopDrawing()
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
		local st = eng.st;

		if st == nil then
			return;
		end;

		local t = now();
		local dt = (eng.last ~= nil) and (t - eng.last) or (FRAME_MS / 1000);
		eng.last = t;
		dt = max(0, min(dt, 0.1));

		local W, H = viewport.width, viewport.height;
		local ok, err = pcall(st.def.draw, st, viewport, W, H, dt, st.opacity, t);

		if not ok then
			stopDrawing();
			FSC.logError("SceneSuite.Clima", err);
		end;
	end;

	function eng:apply(cfg)
		local def = EFFECTS[cfg.fx or "none"];

		if def == nil or self.localOff then
			self.st = nil;
			stopDrawing();
			return;
		end;

		local st = {
			def = def,
			intensity = max(1, min(3, tonumber(cfg.intensity) or 2)),
			wind = tonumber(cfg.wind) or 0,
			opacity = max(0.05, min(1, tonumber(cfg.opacity) or 0.8))
		};

		def.init(st);
		self.st = st;
		self.last = nil;

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

	function eng:refresh(force)
		local cfg, raw = readConfig(scene);

		if force or raw ~= self.raw then
			self.raw = raw;
			self:apply(cfg);
		end;
	end;

	function eng:toggleLocal()
		self.localOff = not self.localOff;
		self:refresh(true);
		return self.localOff;
	end;

	-- Verifica a cada segundo se o mestre mudou o clima
	eng.poll = setInterval(function()
		if not scene.isObjectAlive then
			clearInterval(eng.poll);
			stopDrawing();
			return;
		end;

		eng:refresh(false);
	end, 1000);

	eng:refresh(true);
	return eng;
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local eng = newEngine(scene);
	local frm = nil;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Clima", 54);

	viewport:addToolButton(TOOL_CATEGORY, "Clima: escolher efeito (mestre)",
		"/images/tool_weather.png", 50, {defaultOfCategory = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre muda o clima. Use o outro botão para ligar/desligar só para você.");
				return;
			end;

			if frm == nil then
				frm = GUI.newForm("frmFSWeather");
			end;

			local cfg = readConfig(scene);

			frm:prepareFor({
				config = cfg,
				close = function() viewport:closeForm(frm); end,
				onApply = function(c)
					local ud = scene.userData;

					if ud ~= nil then
						ud[UD_FIELD] = FSC.encode(c);
					end;

					eng:refresh(true);
				end
			});

			viewport:showForm(frm, {placement = "center"});
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Clima: ligar/desligar só para mim",
		"/images/tool_local.png", 51, {dontFocus = true},
		function()
			eng:toggleLocal();
		end);
end);
