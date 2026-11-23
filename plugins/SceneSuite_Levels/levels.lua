--[[
  Scene Suite - Andares (inspirado no módulo "Levels", de forma simplificada)

  - O mestre cria andares e atribui itens (fundo do mapa, desenhos, tokens)
    a cada um. Itens sem andar aparecem em todos.
  - Ao ativar um andar, itens de outros andares ficam visíveis só para o
    mestre (item.visible = false) e os do andar ativo voltam a aparecer.
    O plugin só reexibe o que ele mesmo escondeu: o que o mestre escondeu à
    mão continua escondido.
  - Paredes de andar: retângulos que viram paredes da névoa de guerra só
    quando o andar deles está ativo.
  - Cada andar guarda o seu fundo do Scene (imagem, cor, tamanho do mundo)
    e o alinhamento do grid (deslocamento e tamanho da célula), já que mapas
    de andares diferentes raramente são iguais. Ao criar um andar, ele copia o
    fundo atual; troque o mapa nas opções do tabuleiro e use "Usar o fundo
    atual neste andar".
  - Limite: todos veem o mesmo andar ativo (o Firecast não permite que cada
    jogador enxergue um andar diferente ao mesmo tempo).

  Dados: scene.userData.fsLevels (lista de nomes), fsLevelActive;
         item.userData.fsLevel (índice), fsLevelHid (escondido pelo plugin),
         fsLevelWall (índice do andar da parede).
  Mensagens: "fslevel_token" {uid, level, activate} (ação dos Gatilhos).
]]

require("scene.lua");
require("firecast.lua");
require("log.lua");
require("utils.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local TOOL_CATEGORY = "SSuite_Levels";
local LIST_FIELD = "fsLevels";
local ACTIVE_FIELD = "fsLevelActive";
local ITEM_FIELD = "fsLevel";
local HID_FIELD = "fsLevelHid";
local WALL_FIELD = "fsLevelWall";
local PREFIX = "fslevel_";

FSLEVELS = FSLEVELS or {};
local FSLEVELS = FSLEVELS;

local function udOf(item)
	local ok, ud = pcall(function() return item.userData; end);
	return ok and ud or nil;
end;

-- Registros dos andares: {n = nome, has = "1" se guarda fundo, bg = imagem,
-- bgc = cor, ww/wh = tamanho do mundo, gx/gy = deslocamento do grid, cs = célula}
function FSLEVELS.records(scene)
	local ud = scene.userData;
	return FSC.decodeList(ud and ud[LIST_FIELD]);
end;

local function saveRecords(scene, recs)
	scene.userData[LIST_FIELD] = FSC.encodeList(recs);
end;

function FSLEVELS.names(scene)
	local names = {};

	for _, e in ipairs(FSLEVELS.records(scene)) do
		names[#names + 1] = e.n or "?";
	end;

	return names;
end;

-- Copia o fundo e o grid atuais do Scene para dentro de um registro
function FSLEVELS.captureBackground(scene, rec)
	rec.has = "1";
	rec.bg = scene.bkgImageURL or "";
	rec.bgc = tostring(scene.bkgColor or "");
	rec.ww = tostring(scene.worldWidth or "");
	rec.wh = tostring(scene.worldHeight or "");

	local grid = scene.grid;

	if grid ~= nil then
		rec.gx = tostring(grid.offsetX or "");
		rec.gy = tostring(grid.offsetY or "");
		rec.cs = tostring(grid.cellSize or "");
	end;

	return rec;
end;

-- Aplica o fundo guardado no andar (se ele tiver um)
function FSLEVELS.applyBackground(scene, rec)
	if rec == nil or rec.has ~= "1" then
		return;
	end;

	pcall(function()
		scene.bkgImageURL = rec.bg or "";

		if rec.bgc ~= nil and rec.bgc ~= "" then scene.bkgColor = rec.bgc; end;

		local ww, wh = tonumber(rec.ww), tonumber(rec.wh);

		if ww ~= nil and ww > 0 then scene.worldWidth = ww; end;
		if wh ~= nil and wh > 0 then scene.worldHeight = wh; end;

		local grid = scene.grid;
		local cs, gx, gy = tonumber(rec.cs), tonumber(rec.gx), tonumber(rec.gy);

		if grid ~= nil then
			if cs ~= nil and cs > 0 then grid.cellSize = cs; end;
			if gx ~= nil then grid.offsetX = gx; end;
			if gy ~= nil then grid.offsetY = gy; end;
		end;
	end);
end;

-- Troca o andar ativo: fundo do andar + visibilidade dos itens e paredes
function FSLEVELS.activate(scene, idx)
	local recs = FSLEVELS.records(scene);

	if recs[idx] == nil then return; end;

	scene.userData[ACTIVE_FIELD] = tostring(idx);
	FSLEVELS.applyBackground(scene, recs[idx]);
	FSLEVELS.apply(scene);
end;

function FSLEVELS.active(scene)
	local ud = scene.userData;
	return tonumber(ud and ud[ACTIVE_FIELD]) or 1;
end;

function FSLEVELS.levelOf(item)
	local ud = udOf(item);
	return ud and tonumber(ud[ITEM_FIELD]);
end;

function FSLEVELS.allItems(scene)
	local out = {};

	for i = 1, #scene.items do
		local it = scene.items[i];

		if it ~= nil then out[#out + 1] = it; end;
	end;

	return out;
end;

local function wallPoly(item)
	local x1, y1 = item.x, item.y;
	local x2, y2 = item.x + item.width, item.y + item.height;
	return {{x = x1, y = y1}, {x = x2, y = y1}, {x = x2, y = y2}, {x = x1, y = y2}};
end;

-- Aplica a visibilidade de todos os itens conforme o andar ativo (mestre)
function FSLEVELS.apply(scene)
	if not scene.isGM then return; end;

	local active = FSLEVELS.active(scene);
	local fow = scene.fogOfWar;

	for _, it in ipairs(FSLEVELS.allItems(scene)) do
		local ud = udOf(it);

		if ud ~= nil then
			local wall = tonumber(ud[WALL_FIELD]);

			if wall ~= nil then
				-- fsLevelWallOn evita adicionar a mesma parede duas vezes
				local on = ud.fsLevelWallOn == "1";

				if wall == active and not on then
					pcall(function() fow:addOpaqueArea(wallPoly(it)); end);
					ud.fsLevelWallOn = "1";
				elseif wall ~= active and on then
					pcall(function() fow:removeOpaqueArea(wallPoly(it)); end);
					ud.fsLevelWallOn = "";
				end;
			end;

			local lvl = tonumber(ud[ITEM_FIELD]);

			if lvl ~= nil and wall == nil then
				if lvl == active then
					if ud[HID_FIELD] == "1" then
						it.visible = true;
						ud[HID_FIELD] = "";
					end;
				elseif it.visible ~= false then
					it.visible = false;
					ud[HID_FIELD] = "1";
				end;
			end;
		end;
	end;
end;

function FSLEVELS.assign(scene, item, level)
	local ud = udOf(item);

	if ud == nil then return; end;

	if level == nil then
		ud[ITEM_FIELD] = "";

		if ud[HID_FIELD] == "1" then
			item.visible = true;
			ud[HID_FIELD] = "";
		end;
	else
		ud[ITEM_FIELD] = tostring(level);
	end;
end;

function FSLEVELS.counts(scene)
	local c = {};

	for _, it in ipairs(FSLEVELS.allItems(scene)) do
		local ud = udOf(it);
		local l = ud and (tonumber(ud[ITEM_FIELD]) or tonumber(ud[WALL_FIELD]));

		if l ~= nil then c[l] = (c[l] or 0) + 1; end;
	end;

	return c;
end;

-- Remove o andar idx: itens dele passam a valer para todos; índices acima descem
function FSLEVELS.delete(scene, idx)
	local recs = FSLEVELS.records(scene);

	if recs[idx] == nil then return; end;

	table.remove(recs, idx);
	local fow = scene.fogOfWar;

	for _, it in ipairs(FSLEVELS.allItems(scene)) do
		local ud = udOf(it);

		if ud ~= nil then
			local l = tonumber(ud[ITEM_FIELD]);

			if l == idx then
				FSLEVELS.assign(scene, it, nil);
			elseif l ~= nil and l > idx then
				ud[ITEM_FIELD] = tostring(l - 1);
			end;

			local w = tonumber(ud[WALL_FIELD]);

			if w == idx then
				pcall(function() fow:removeOpaqueArea(wallPoly(it)); end);
				it:delete();
			elseif w ~= nil and w > idx then
				ud[WALL_FIELD] = tostring(w - 1);
			end;
		end;
	end;

	saveRecords(scene, recs);
	local active = FSLEVELS.active(scene);

	if active > idx then
		active = active - 1;
	elseif active == idx then
		active = math.max(1, math.min(idx, #recs));
	end;

	if #recs > 0 then
		FSLEVELS.activate(scene, active);
	else
		scene.userData[ACTIVE_FIELD] = "1";
	end;
end;

function FSLEVELS.findLevel(scene, text)
	local n = tonumber(text);
	local names = FSLEVELS.names(scene);

	if n ~= nil and names[n] ~= nil then return n; end;

	local q = FSC.trim(text):lower();

	for i, name in ipairs(names) do
		if name:lower() == q then return i; end;
	end;

	return nil;
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local frm = nil;
	local listeners = {};
	local drag = nil;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Andares", 44);

	-- rótulo discreto com o andar ativo (canto superior esquerdo)
	local lastLabel = nil;
	FSC.keepAlive(scene, "fslevel_label", viewport:listen("onAfterDrawLayers", function()
		local names = FSLEVELS.names(scene);

		if #names == 0 then return; end;

		local name = names[FSLEVELS.active(scene)] or names[1];
		local txt = "Andar: " .. name;
		viewport:prepareFont(12, nil, true);
		local w, h = viewport:textSize(txt);
		viewport:prepareFill("#000000");
		viewport:fillRect(6, 6, 6 + w + 12, 6 + h + 6, 0.55);
		viewport:prepareFill("#FFCC66");
		viewport:fillText(12, 9, txt, 1);
	end));

	-- repinta quando outro usuário troca o andar
	local poll;
	poll = setInterval(function()
		if not scene.isObjectAlive then clearInterval(poll); return; end;
		local ud = scene.userData;
		local key = ud and ((ud[LIST_FIELD] or "") .. "#" .. (ud[ACTIVE_FIELD] or "")) or "";

		if key ~= lastLabel then
			lastLabel = key;
			viewport:needRepaint();
		end;
	end, 1000);

	-- ação dos Gatilhos: levar token para um andar
	FSC.keepAlive(scene, "fslevel_token", scene:newBroadcastListener("fslevel_token", function(sender, id, msg)
		if not scene.isGM or type(msg) ~= "table" then return; end;

		local lvl = FSLEVELS.findLevel(scene, tostring(msg.level or ""));

		if lvl == nil then return; end;

		for _, t in ipairs(FSC.allTokens(scene)) do
			local ud = udOf(t);

			if ud ~= nil and ud.fsUid == msg.uid then
				FSLEVELS.assign(scene, t, lvl);
			end;
		end;

		if msg.activate then
			FSLEVELS.activate(scene, lvl);
		else
			FSLEVELS.apply(scene);
		end;
	end));

	local function model()
		local recs = FSLEVELS.records(scene);
		local names, hasBg = {}, {};

		for i, r in ipairs(recs) do
			names[i] = r.n or "?";
			hasBg[i] = r.has == "1";
		end;

		return {names = names, hasBg = hasBg, active = FSLEVELS.active(scene), counts = FSLEVELS.counts(scene)};
	end;

	local function act(name, idx, text)
		local recs = FSLEVELS.records(scene);
		local names = FSLEVELS.names(scene);

		if name == "add" then
			local n = FSC.trim(text);

			if n == "" then
				n = (#recs == 0) and "Térreo" or ("Andar " .. (#recs + 1));
			end;

			-- o andar novo começa com o fundo atual (assim, voltar a ele
			-- sempre restaura este mapa)
			recs[#recs + 1] = FSLEVELS.captureBackground(scene, {n = n});
			saveRecords(scene, recs);

			if #recs == 1 then
				scene.userData[ACTIVE_FIELD] = "1";
			end;

			return;
		end;

		if idx == nil or recs[idx] == nil then
			showMessage("Crie um andar primeiro.");
			return;
		end;

		if name == "activate" then
			FSLEVELS.activate(scene, idx);
			viewport:needRepaint();
		elseif name == "captureBg" then
			FSLEVELS.captureBackground(scene, recs[idx]);
			saveRecords(scene, recs);
		elseif name == "clearBg" then
			recs[idx].has = "";
			saveRecords(scene, recs);
		elseif name == "rename" then
			local n = FSC.trim(text);

			if n ~= "" then
				recs[idx].n = n;
				saveRecords(scene, recs);
			end;
		elseif name == "delete" then
			Dialogs.confirmYesNo("Excluir o andar \"" .. names[idx] .. "\"? Os itens dele passam a aparecer em todos os andares.",
				function(yes)
					if yes then
						FSLEVELS.delete(scene, idx);
						if frm ~= nil then frm:refresh(nil); end;
					end;
				end);
		elseif name == "assign" or name == "unassign" then
			local sel = scene.items.selection or {};

			if #sel == 0 then
				showMessage("Selecione itens no tabuleiro (fundo, desenhos ou tokens).");
				return;
			end;

			for _, it in ipairs(sel) do
				FSLEVELS.assign(scene, it, (name == "assign") and idx or nil);
			end;

			FSLEVELS.apply(scene);
		elseif name == "select" then
			scene.items:clearSelection();

			for _, it in ipairs(FSLEVELS.allItems(scene)) do
				if FSLEVELS.levelOf(it) == idx then
					it.selected = true;
				end;
			end;
		end;
	end;

	viewport:addToolButton(TOOL_CATEGORY, "Andares: gerenciar (mestre)",
		"/images/tool_levels.png", 10, {defaultOfCategory = true},
		function()
			if not scene.isGM then
				local names = FSLEVELS.names(scene);
				showMessage((#names > 0) and ("Andar atual: " .. (names[FSLEVELS.active(scene)] or "?")) or "Sem andares neste mapa.");
				return;
			end;

			if frm == nil then
				frm = GUI.newForm("frmFSLevels");
			end;

			frm:prepareFor({model = model, act = act, close = function() viewport:closeForm(frm); end});
			FSC.showFormFit(viewport, frm, 320, 400, "topLeft", 220, 180);
		end);

	-- parede de andar: arraste um retângulo; vale só quando o andar está ativo
	local function clear()
		for _, l in ipairs(listeners) do viewport:unlisten(l); end;
		listeners = {};
		drag = nil;
		viewport:needRepaint();
	end;

	viewport:addToolButton(TOOL_CATEGORY, "Andares: arraste para criar uma parede do andar ativo",
		"/images/tool_wall.png", 11, {selectable = true},
		function()
			if not scene.isGM or #FSLEVELS.names(scene) == 0 then
				showMessage("Apenas o mestre, e depois de criar um andar.");
				viewport:selectDefaultToolButton();
				return;
			end;

			viewport.cursor = "cross";
			listeners[#listeners + 1] = viewport:listen("onMouseDown", function(e)
				if e.button ~= "left" then return; end;
				local x, y = viewport:screenToWorld(e.x, e.y);
				drag = {x, y, x, y};
			end);
			listeners[#listeners + 1] = viewport:listen("onMouseMove", function(e)
				if drag == nil then return; end;
				drag[3], drag[4] = viewport:screenToWorld(e.x, e.y);
				viewport:needRepaint();
			end);
			listeners[#listeners + 1] = viewport:listen("onMouseUp", function(e)
				if drag == nil then return; end;
				local x1, x2 = math.min(drag[1], drag[3]), math.max(drag[1], drag[3]);
				local y1, y2 = math.min(drag[2], drag[4]), math.max(drag[2], drag[4]);
				drag = nil;
				viewport:needRepaint();

				if (x2 - x1) <= 0.01 or (y2 - y1) <= 0.01 then return; end;

				local d = scene.items:addUserDrawing("objects");
				d:markAsMyDrawing();
				d.x, d.y, d.width, d.height = x1, y1, x2 - x1, y2 - y1;
				d.snapToGrid = false;
				d.visible = false;
				local active = FSLEVELS.active(scene);
				d.userData[WALL_FIELD] = tostring(active);
				FSC.addPathOp(d.canvas, PREFIX .. "wall", "M0 0H1V1H0Z", {0, 0, 1, 1},
					{metric = "canvasMetric", xOrigin = 0, yOrigin = 0, fill = "#FF6E4033", stroke = "#FF6E40",
					 strokeSize = 2, visibility = "gmOnly"});
				FSC.addTextOp(d.canvas, PREFIX .. "label", "parede: " .. (FSLEVELS.names(scene)[active] or ""), 0, -0.3, 0.24,
					{xOrigin = 0.5, yOrigin = 0, color = "#FFAB91", visibility = "gmOnly"});
				pcall(function() scene.fogOfWar:addOpaqueArea(wallPoly(d)); end);
				d.userData.fsLevelWallOn = "1";
			end);
			listeners[#listeners + 1] = viewport:listen("onAfterDrawLayers", function()
				if drag == nil then return; end;
				local ax, ay = viewport:worldToScreen(math.min(drag[1], drag[3]), math.min(drag[2], drag[4]));
				local bx, by = viewport:worldToScreen(math.max(drag[1], drag[3]), math.max(drag[2], drag[4]));
				viewport:prepareFill("#FF6E40");
				viewport:fillRect(ax, ay, bx, by, 0.3);
			end);
		end,
		function()
			viewport.cursor = "default";
			clear();
		end);
end);
