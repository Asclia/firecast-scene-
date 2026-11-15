--[[
  Scene Suite - Áreas de Magia
  Cria áreas de efeito digitando o tamanho em pés, metros ou quadrados.
  O plugin converte usando a configuração do tabuleiro (tamanho da célula e
  unidade do mundo; padrão 1 quadrado = 1,5 m = 5 ft) e marca os quadrados
  afetados pela regra do Pathfinder (origem numa interseção do grid,
  diagonais 5-10-5, cone de 90°).

  Uso: selecione a ferramenta, escolha a magia/forma no painel e
   - explosão / emanação / cilindro: clique no ponto de origem;
   - cone / linha / quadrado: clique na origem, mire com o mouse e clique de novo.
   Botão direito ou ESC cancela. SHIFT = origem livre (sem encaixar no grid).
   CTRL + clique sobre uma área criada por este plugin a remove.

  As áreas são "desenhos" (userDrawings) normais do Scene: aparecem para
  todos e podem ser selecionadas/apagadas como qualquer desenho.
]]

require("scene.lua");
require("firecast.lua");
require("utils.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local PREFIX = "fssa_";
local TOOL_CATEGORY = "SceneSuite";
local FX_MESSAGE = "fsfx_play";

FSSA = FSSA or {};
local FSSA = FSSA;

-- Magias mais usadas de Pathfinder 1e (CRB/APG) com suas áreas
FSSA.PRESETS = {
	{label = "Bola de Fogo (20 ft)", name = "Bola de Fogo", shape = "burst", size = "20 ft", color = "#FF6D00", fx = "fireball"},
	{label = "Mãos Flamejantes (cone 15 ft)", name = "Mãos Flamejantes", shape = "cone", size = "15 ft", color = "#FF7043", fx = "burning_hands"},
	{label = "Relâmpago (linha 120 ft)", name = "Relâmpago", shape = "line", size = "120 ft", width = "5 ft", color = "#40C4FF", fx = "lightning_bolt"},
	{label = "Cone de Frio (cone 60 ft)", name = "Cone de Frio", shape = "cone", size = "60 ft", color = "#80D8FF", fx = "cone_of_cold"},
	{label = "Spray de Cores (cone 15 ft)", name = "Spray de Cores", shape = "cone", size = "15 ft", color = "#E040FB", fx = "color_spray"},
	{label = "Coluna de Chamas (cilindro 10 ft)", name = "Coluna de Chamas", shape = "cylinder", size = "10 ft", color = "#FFAB00", fx = "flame_strike"},
	{label = "Tempestade de Gelo (cilindro 20 ft)", name = "Tempestade de Gelo", shape = "cylinder", size = "20 ft", color = "#B3E5FC", fx = "ice_storm"},
	{label = "Canalizar Energia (30 ft)", name = "Canalizar Energia", shape = "emanation", size = "30 ft", color = "#FFD54F", fx = "channel_positive"},
	{label = "Canalizar Energia Negativa (30 ft)", name = "Canalizar Energia Negativa", shape = "emanation", size = "30 ft", color = "#7E57C2", fx = "channel_negative"},
	{label = "Explosão Sonora (10 ft)", name = "Explosão Sonora", shape = "burst", size = "10 ft", color = "#B0BEC5", fx = "sound_burst"},
	{label = "Pó Reluzente (10 ft)", name = "Pó Reluzente", shape = "burst", size = "10 ft", color = "#FFD740", fx = "glitterdust"},
	{label = "Nuvem Fétida (20 ft)", name = "Nuvem Fétida", shape = "burst", size = "20 ft", color = "#9CCC65", fx = "poison_cloud"},
	{label = "Névoa Mortal (20 ft)", name = "Névoa Mortal", shape = "burst", size = "20 ft", color = "#689F38", fx = "poison_cloud"},
	{label = "Escuridão (20 ft)", name = "Escuridão", shape = "emanation", size = "20 ft", color = "#37474F", fx = "darkness"},
	{label = "Explosão Solar (80 ft)", name = "Explosão Solar", shape = "burst", size = "80 ft", color = "#FFF59D", fx = "holy_burst"},
	{label = "Chuva de Meteoros (40 ft)", name = "Chuva de Meteoros", shape = "burst", size = "40 ft", color = "#FF3D00", fx = "meteor_swarm"},
	{label = "Teia (20 ft)", name = "Teia", shape = "burst", size = "20 ft", color = "#ECEFF1"},
	{label = "Graxa (quadrado 10 ft)", name = "Graxa", shape = "square", size = "10 ft", color = "#8D6E63"},
	{label = "Tentáculos Negros (20 ft)", name = "Tentáculos Negros", shape = "burst", size = "20 ft", color = "#4A148C"},
	{label = "Sono (10 ft)", name = "Sono", shape = "burst", size = "10 ft", color = "#9FA8DA"},
	{label = "Silêncio (20 ft)", name = "Silêncio", shape = "emanation", size = "20 ft", color = "#90A4AE"},
	{label = "Névoa Obscurecente (20 ft)", name = "Névoa Obscurecente", shape = "emanation", size = "20 ft", color = "#CFD8DC"},
	{label = "Constrição (40 ft)", name = "Constrição", shape = "burst", size = "40 ft", color = "#558B2F"},
	{label = "Bafo de Dragão (cone 30 ft)", name = "Sopro", shape = "cone", size = "30 ft", color = "#FF5722", fx = "burning_hands"},
	{label = "Bafo de Dragão (linha 60 ft)", name = "Sopro", shape = "line", size = "60 ft", width = "5 ft", color = "#40C4FF", fx = "lightning_bolt"},
};

local NEEDS_AIM = {cone = true, line = true, square = true};

----------------------------------------------------------------------
-- Geometria (coordenadas de célula absolutas)
----------------------------------------------------------------------

-- Retorna {set=..} (modo grid) ou {polys=..} (suave) e o bbox
function FSSA.compute(scene, cfg, ox, oy, angle)
	local sq = FSC.parseDistance(cfg.size, scene, "ft");

	if sq == nil or sq <= 0 then
		return nil;
	end;

	local wsq = FSC.parseDistance(cfg.width ~= "" and cfg.width or "5 ft", scene, "ft") or 1;
	local mode = cfg.mode;

	if not FSC.isSquareGrid(scene) then
		mode = "smooth";
	end;

	local shape = cfg.shape;
	local diag = FSC.diagMode(scene, cfg.diag);

	if mode == "grid" then
		local set;
		local io, jo = math.floor(ox + 0.5), math.floor(oy + 0.5);

		if shape == "cone" then
			set = FSC.shiftCells(FSC.cellsCone(0, 0, {maxR = sq, mode = diag, angle = angle}), io, jo);
		elseif shape == "line" then
			set = FSC.cellsLine(ox, oy, angle, sq, math.max(1, wsq));
		elseif shape == "square" then
			set = FSC.cellsSquare(io, jo, angle, sq);
		else
			set = FSC.shiftCells(FSC.cellsInRange(0, 0, {maxR = sq, mode = diag}), io, jo);
		end;

		if #set.list == 0 then
			return nil;
		end;

		return {set = set, bbox = FSC.cellsBBox(set), sq = sq};
	else
		local poly;

		if shape == "cone" then
			poly = FSC.conePoly(ox, oy, angle, sq, 90, 32);
		elseif shape == "line" then
			poly = FSC.linePoly(ox, oy, angle, sq, math.max(0.2, wsq));
		elseif shape == "square" then
			poly = FSC.squarePoly(ox, oy, angle, sq);
		else
			poly = FSC.circlePoly(ox, oy, sq, 64);
		end;

		local _, bbox = FSC.polysToPath({poly}, true);
		return {polys = {poly}, bbox = bbox, sq = sq};
	end;
end;

----------------------------------------------------------------------
-- Criação do desenho persistente
----------------------------------------------------------------------

function FSSA.create(scene, cfg, geo, ox, oy, angle)
	local gx, gy, cs = FSC.gridOrigin(scene);
	local bb = geo.bbox;
	local layer = scene.isGM and "objects" or scene.workingLayer;
	local fillA = tonumber(cfg.fill) or 0.3;
	local vis = cfg.gm and "gmOnly" or "everyone";

	local ud = scene.items:addUserDrawing(layer);
	ud:markAsMyDrawing();
	ud:beginUpdate();

	local base = {metric = "canvasMetric", xOrigin = 0, yOrigin = 0, visibility = vis};

	local function o(extra)
		local t = {};
		for k, v in pairs(base) do t[k] = v; end;
		for k, v in pairs(extra) do t[k] = v; end;
		return t;
	end;

	if geo.set ~= nil then
		local fill, outline = FSC.cellsToPaths(geo.set, 0, 0);
		FSC.addPathOp(ud.canvas, PREFIX .. "fill", fill, {0, 0, 1, 1},
			o({fill = FSC.withAlpha(cfg.color, fillA), z = 0}));
		FSC.addPathOp(ud.canvas, PREFIX .. "line", outline, {0, 0, 1, 1},
			o({stroke = FSC.withAlpha(cfg.color, 0.95), strokeSize = 2.5, strokeCap = "round", z = 1}));
	else
		local data = FSC.polysToPath(geo.polys, true);
		FSC.addPathOp(ud.canvas, PREFIX .. "fill", data, {0, 0, 1, 1},
			o({fill = FSC.withAlpha(cfg.color, fillA), stroke = FSC.withAlpha(cfg.color, 0.95), strokeSize = 2.5, z = 0}));
	end;

	-- rótulo: "Bola de Fogo · 20 ft"
	local _, feet = FSC.parseDistance(cfg.size, scene, "ft");
	local label = FSC.trim(cfg.name);
	local sizeTxt = FSC.fmtNum(feet) .. " ft";

	if label ~= "" then
		label = label .. " · " .. sizeTxt;
	else
		label = sizeTxt;
	end;

	FSC.addTextOp(ud.canvas, PREFIX .. "label", label, 0, -0.42, 0.36,
		{metric = "cellMetric", xOrigin = 0.5, yOrigin = 0, visibility = vis, color = "#FFFFFF", z = 3,
		 outOfOrderMode = "afterOwnerLayer"});

	ud.x = gx + bb[1] * cs;
	ud.y = gy + bb[2] * cs;
	ud.width = math.max((bb[3] - bb[1]) * cs, 0.01);
	ud.height = math.max((bb[4] - bb[2]) * cs, 0.01);
	ud.snapToGrid = false;
	ud:endUpdate();

	return ud;
end;

-- Avisa o plugin de Animações (se instalado) para tocar a animação
function FSSA.sendFX(scene, cfg, ox, oy, angle, sq)
	local p = FSSA.PRESETS[tonumber(cfg.preset) or 0];

	if not cfg.fx or p == nil or p.fx == nil then
		return;
	end;

	local gx, gy, cs = FSC.gridOrigin(scene);
	local wx, wy = gx + ox * cs, gy + oy * cs;
	local dx, dy = FSC.dirVector(angle);
	local len = sq * cs;
	local msg = {fx = p.fx, r = len, angle = angle, n = 3};

	if NEEDS_AIM[cfg.shape] then
		-- cone / linha: da origem na direção mirada
		msg.sx, msg.sy = wx, wy;
		msg.tx, msg.ty = wx + dx * len, wy + dy * len;
	else
		-- áreas: efeito centrado na origem; projéteis (bola de fogo) saem
		-- do token selecionado, se houver
		msg.sx, msg.sy = wx, wy;
		msg.tx, msg.ty = wx, wy;
		local sel = FSC.selectedTokens(scene);

		if #sel > 0 then
			msg.sx, msg.sy = sel[1]:getCenter(false);
		end;
	end;

	scene:broadcastMessage(FX_MESSAGE, msg, true);
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local listeners = {};
	local frm = nil;
	local cfg = nil;

	-- estado da interação
	local origin = nil;       -- {x, y} em coordenadas de célula (quando mirando)
	local mouseCell = nil;    -- posição atual do mouse (coord. de célula)
	local freeOrigin = false;

	viewport:setupToolCategory(TOOL_CATEGORY, "Scene Suite", 50);

	local function snapPoint(cx, cy, free)
		if free then
			return cx, cy;
		end;

		return math.floor(cx + 0.5), math.floor(cy + 0.5);
	end;

	local function currentGeometry()
		if cfg == nil or mouseCell == nil then
			return nil;
		end;

		local ox, oy, angle;

		if origin ~= nil then
			ox, oy = origin[1], origin[2];
			angle = FSC.angleOf(mouseCell[1] - ox, mouseCell[2] - oy);
		else
			ox, oy = snapPoint(mouseCell[1], mouseCell[2], freeOrigin);
			angle = 90;
		end;

		local geo = FSSA.compute(scene, cfg, ox, oy, angle);
		return geo, ox, oy, angle;
	end;

	-- Pré-visualização local (não é compartilhada)
	local function drawPreview()
		local geo, ox, oy = currentGeometry();

		if geo == nil then
			return;
		end;

		local gx, gy, cs = FSC.gridOrigin(scene);
		local color = cfg.color or "#FF6D00";

		local function toScreen(a, b)
			return viewport:worldToScreen(gx + a * cs, gy + b * cs);
		end;

		if geo.set ~= nil then
			viewport:prepareFill(color);

			for _, c in ipairs(geo.set.list) do
				viewport:fillACell(c[2], c[1], 0.35);
			end;

			viewport:prepareDraw(color, 2);
			local map = geo.set.map;

			for _, c in ipairs(geo.set.list) do
				local a, b = c[1], c[2];
				local x1, y1 = toScreen(a, b);
				local x2, y2 = toScreen(a + 1, b + 1);

				if not map[a .. "," .. (b - 1)] then viewport:drawLine(x1, y1, x2, y1, 0.9); end;
				if not map[a .. "," .. (b + 1)] then viewport:drawLine(x1, y2, x2, y2, 0.9); end;
				if not map[(a - 1) .. "," .. b] then viewport:drawLine(x1, y1, x1, y2, 0.9); end;
				if not map[(a + 1) .. "," .. b] then viewport:drawLine(x2, y1, x2, y2, 0.9); end;
			end;
		else
			local pts = {};

			for _, p in ipairs(geo.polys[1]) do
				local sx, sy = toScreen(p[1], p[2]);
				pts[#pts + 1] = {x = sx, y = sy};
			end;

			viewport:prepareFill(color);
			viewport:fillPolygon(pts, 0.3);
			viewport:prepareDraw(color, 2);

			for i = 1, #pts do
				local p, q = pts[i], pts[(i % #pts) + 1];
				viewport:drawLine(p.x, p.y, q.x, q.y, 0.9);
			end;
		end;

		-- ponto de origem
		local sx, sy = toScreen(ox, oy);
		viewport:prepareFill("#FFFFFF");
		viewport:fillEllipse(sx - 4, sy - 4, sx + 4, sy + 4, 1);
		viewport:prepareDraw("#000000", 1.5);
		viewport:drawEllipse(sx - 4, sy - 4, sx + 4, sy + 4, 1);
	end;

	local function cancelAim()
		origin = nil;
		viewport:needRepaint();
	end;

	local function describe(c)
		local sq, feet = FSC.parseDistance(c.size, scene, "ft");

		if sq == nil then
			return "Tamanho inválido. Use 20 ft, 6 m ou 4 q.";
		end;

		local txt = FSC.formatFeet(feet) .. " = " .. FSC.fmtNum(sq) .. " quadrado(s).";

		if NEEDS_AIM[c.shape] then
			txt = txt .. "\nClique na origem, mire e clique de novo.";
		else
			txt = txt .. "\nClique na interseção de origem.";
		end;

		return txt .. " Dir./ESC cancela. CTRL+clique remove uma área.";
	end;

	local function removeAreaAt(event)
		local wx, wy = viewport:screenToWorld(event.x, event.y);
		local list = scene.items:enumAtPoint(wx, wy);

		for i = #list, 1, -1 do
			local it = list[i];

			if it.objectType == "userDrawing" and it.canvas:findByName(PREFIX .. "fill") ~= nil then
				if scene.isGM or it.isMine then
					it:delete();
					return true;
				end;
			end;
		end;

		return false;
	end;

	local function onMouseDown(event)
		if event.button == "right" then
			cancelAim();
			return;
		end;

		if event.button ~= "left" or cfg == nil then
			return;
		end;

		if event.ctrlOrCmdKey then
			removeAreaAt(event);
			return;
		end;

		local wx, wy = viewport:screenToWorld(event.x, event.y);
		local cx, cy = FSC.worldToCellCoords(scene, wx, wy);
		mouseCell = {cx, cy};
		freeOrigin = event.shiftKey == true;

		if NEEDS_AIM[cfg.shape] and origin == nil then
			local ox, oy = snapPoint(cx, cy, freeOrigin);
			origin = {ox, oy};
			viewport:needRepaint();
			return;
		end;

		local geo, ox, oy, angle = currentGeometry();

		if geo == nil then
			showMessage("Tamanho inválido. Use algo como 20 ft, 6 m ou 4 q.");
			return;
		end;

		local ok, err = pcall(FSSA.create, scene, cfg, geo, ox, oy, angle);

		if not ok then
			FSC.chatLocal(scene, "[Áreas de Magia] erro: " .. tostring(err));
		else
			FSSA.sendFX(scene, cfg, ox, oy, angle, geo.sq);
		end;

		origin = nil;
		viewport:needRepaint();
	end;

	local function onMouseMove(event)
		local wx, wy = viewport:screenToWorld(event.x, event.y);
		local cx, cy = FSC.worldToCellCoords(scene, wx, wy);
		mouseCell = {cx, cy};
		freeOrigin = event.shiftKey == true;
		viewport:needRepaint();
	end;

	local function onKeyDown(event)
		if event.keyCode == 27 and origin ~= nil then
			cancelAim();
			event.keyCode = 0;
		end;
	end;

	local toolId;

	local function deactivate()
		for _, l in ipairs(listeners) do
			viewport:unlisten(l);
		end;

		listeners = {};
		origin = nil;
		mouseCell = nil;

		if frm ~= nil then
			viewport:closeForm(frm);
		end;

		viewport:needRepaint();
	end;

	toolId = viewport:addToolButton(TOOL_CATEGORY, "Área de magia (tamanho em ft / m)",
		"/images/tool_area.png", 40, {selectable = true},
		function()
			if FSC.isSpectator(scene) then
				return;
			end;

			if frm == nil then
				frm = GUI.newForm("frmFSSpellArea");
			end;

			frm:prepareFor({
				presets = FSSA.PRESETS,
				onChange = function(c)
					cfg = c;
					origin = nil;
					viewport:needRepaint();
					return describe(c);
				end,
				onClose = function()
					viewport:selectDefaultToolButton();
				end
			});

			viewport:showForm(frm, {placement = "topLeft"});

			listeners[#listeners + 1] = viewport:listen("onMouseDown", onMouseDown);
			listeners[#listeners + 1] = viewport:listen("onMouseMove", onMouseMove);
			listeners[#listeners + 1] = viewport:listen("onKeyDown", onKeyDown);
			listeners[#listeners + 1] = viewport:listen("onAfterDrawLayers", drawPreview);
			viewport.cursor = "cross";
		end,
		function()
			viewport.cursor = "default";
			deactivate();
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Áreas de magia: remover todas (as suas; o mestre remove todas)",
		"/images/tool_clear.png", 41, {dontFocus = true},
		function()
			Dialogs.confirmYesNo("Remover as áreas de magia criadas por este plugin?", function(yes)
				if not yes then return; end;

				local doomed = {};
				local items = scene.items;

				for i = 1, #items do
					local it = items[i];

					if it ~= nil and it.objectType == "userDrawing" and it.canvas:findByName(PREFIX .. "fill") ~= nil then
						if scene.isGM or it.isMine then
							doomed[#doomed + 1] = it;
						end;
					end;
				end;

				for _, it in ipairs(doomed) do
					it:delete();
				end;

				FSC.chatLocal(scene, "[Áreas de Magia] " .. #doomed .. " área(s) removida(s).");
			end);
		end);
end);
