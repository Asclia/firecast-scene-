--[[
  Scene Suite - Gatilhos e Portas (inspirado no "Monk's Active Tiles")

  Gatilho: área retangular (desenho do Scene visível só para o mestre) que
  executa ações quando um token entra e/ou sai dela.
  Porta: retângulo visível a todos que, fechado, é uma parede da névoa de
  guerra (bloqueia visão); aberto, deixa passar.
  Grupo: nome dado a tokens/desenhos para mostrar/esconder em conjunto.

  A detecção roda no computador do MESTRE (é ele quem pode mexer em
  visibilidade, paredes e tokens de todos). Sem mestre conectado, os
  gatilhos não disparam.

  Integração (por mensagens do Scene, plugins opcionais):
    fscond_apply -> Condições;  fsfx_play -> Animações;
    fshp_float   -> números flutuantes do PV Rápido;
    fstrig_msg   -> mensagem exibida por este plugin em todos.

  Dados: userData dos desenhos -> fsTrigger, fsTriggerActions, fsDoor;
         userData de qualquer item -> fsGroup.
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
local TOOL_CATEGORY = "SSuite_Triggers";
local TRIG_FIELD = "fsTrigger";
local ACT_FIELD = "fsTriggerActions";
local DOOR_FIELD = "fsDoor";
local GROUP_FIELD = "fsGroup";
local MSG_MESSAGE = "fstrig_msg";
local PREFIX = "fstrig_";

FSTRIG = FSTRIG or {};
local FSTRIG = FSTRIG;

----------------------------------------------------------------------
-- Consultas
----------------------------------------------------------------------

local function udOf(item)
	local ok, ud = pcall(function() return item.userData; end);
	return ok and ud or nil;
end;

function FSTRIG.isTrigger(item)
	local ud = udOf(item);
	return item.objectType == "userDrawing" and ud ~= nil and ud[TRIG_FIELD] ~= nil and ud[TRIG_FIELD] ~= "";
end;

function FSTRIG.isDoor(item)
	local ud = udOf(item);
	return item.objectType == "userDrawing" and ud ~= nil and ud[DOOR_FIELD] ~= nil and ud[DOOR_FIELD] ~= "";
end;

function FSTRIG.triggers(scene)
	local out = {};

	for i = 1, #scene.items do
		local it = scene.items[i];

		if it ~= nil and FSTRIG.isTrigger(it) then
			out[#out + 1] = it;
		end;
	end;

	return out;
end;

local function lower(s)
	return FSC.trim(s):lower();
end;

function FSTRIG.findByName(scene, kind, name)
	local n = lower(name);

	for i = 1, #scene.items do
		local it = scene.items[i];

		if it ~= nil then
			local ud = udOf(it);
			local field = (kind == "door") and DOOR_FIELD or TRIG_FIELD;

			if ud ~= nil and ud[field] ~= nil and ud[field] ~= "" then
				if lower(FSC.decode(ud[field]).name) == n then
					return it;
				end;
			end;
		end;
	end;

	return nil;
end;

function FSTRIG.groupItems(scene, group)
	local g = lower(group);
	local out = {};

	for i = 1, #scene.items do
		local it = scene.items[i];
		local ud = it and udOf(it);

		if ud ~= nil and ud[GROUP_FIELD] ~= nil and lower(ud[GROUP_FIELD]) == g then
			out[#out + 1] = it;
		end;
	end;

	return out;
end;

local function inside(item, x, y)
	return x >= item.x and x <= item.x + item.width and y >= item.y and y <= item.y + item.height;
end;

----------------------------------------------------------------------
-- Desenho dos gatilhos e portas
----------------------------------------------------------------------

local RECT = "M0 0H1V1H0Z";

function FSTRIG.drawTrigger(item, cfg)
	FSC.removeOps(item.canvas, PREFIX);
	local active = cfg.enabled ~= "0" and cfg.used ~= "1";
	local color = active and "#B388FF" or "#9E9E9E";
	FSC.addPathOp(item.canvas, PREFIX .. "box", RECT, {0, 0, 1, 1},
		{metric = "canvasMetric", xOrigin = 0, yOrigin = 0, fill = FSC.withAlpha(color, 0.12),
		 stroke = FSC.withAlpha(color, 0.9), strokeSize = 2, strokeDash = "dash", visibility = "gmOnly"});
	local label = "Gatilho: " .. ((cfg.name ~= nil and cfg.name ~= "") and cfg.name or "sem nome");

	if not active then
		label = label .. " (inativo)";
	end;

	FSC.addTextOp(item.canvas, PREFIX .. "label", label, 0.1, 0.05, 0.3,
		{xOrigin = 0, yOrigin = 0, color = "#E1BEE7", align = "leading", visibility = "gmOnly", z = 2});
end;

function FSTRIG.drawDoor(item, door)
	FSC.removeOps(item.canvas, PREFIX);
	local open = door.open == "1";
	FSC.addPathOp(item.canvas, PREFIX .. "door", RECT, {0, 0, 1, 1},
		{metric = "canvasMetric", xOrigin = 0, yOrigin = 0,
		 fill = open and "#8D6E6333" or "#6D4C41F0", stroke = open and "#A1887F99" or "#3E2723", strokeSize = 2,
		 strokeDash = open and "dash" or "solid"});
	FSC.addTextOp(item.canvas, PREFIX .. "label", (open and "porta aberta: " or "porta: ") .. (door.name or ""), 0, -0.32, 0.26,
		{xOrigin = 0.5, yOrigin = 0, color = "#D7CCC8", visibility = "gmOnly", z = 2});
end;

local function rectPoly(item)
	local x1, y1 = item.x, item.y;
	local x2, y2 = item.x + item.width, item.y + item.height;
	return {{x = x1, y = y1}, {x = x2, y = y1}, {x = x2, y = y2}, {x = x1, y = y2}};
end;

function FSTRIG.setDoor(scene, item, open)
	local ud = udOf(item);
	local door = FSC.decode(ud and ud[DOOR_FIELD]);
	local fow = scene.fogOfWar;

	if open then
		pcall(function() fow:removeOpaqueArea(rectPoly(item)); end);
	else
		pcall(function() fow:addOpaqueArea(rectPoly(item)); end);
	end;

	door.open = open and "1" or "0";

	if ud ~= nil then
		ud[DOOR_FIELD] = FSC.encode(door);
	end;

	FSTRIG.drawDoor(item, door);
end;

----------------------------------------------------------------------
-- Ações
----------------------------------------------------------------------

-- "2d6+3", "1d8", "10" -> total
function FSTRIG.rollDice(expr)
	local s = FSC.trim(expr):lower():gsub("%s", "");
	local total = 0;
	local any = false;

	for sign, term in s:gmatch("([%+%-]?)([^%+%-]+)") do
		local mult = (sign == "-") and -1 or 1;
		local n, faces = term:match("^(%d*)d(%d+)$");

		if faces ~= nil then
			n = tonumber(n) or 1;
			faces = tonumber(faces);

			for k = 1, math.min(n, 100) do
				total = total + mult * math.random(1, faces);
			end;

			any = true;
		elseif tonumber(term) ~= nil then
			total = total + mult * tonumber(term);
			any = true;
		end;
	end;

	return any and total or nil;
end;

local function uidOf(token)
	local ud = udOf(token);

	if ud == nil then
		return nil;
	end;

	local u = ud.fsUid;

	if u == nil or u == "" then
		u = string.format("t-%d-%d", math.floor(system.getTickCount()), math.random(1, 999999));
		ud.fsUid = u;
	end;

	return u;
end;

-- Executa as ações de um gatilho para um token (pode ser nil no "Testar")
function FSTRIG.run(scene, trigger, actions, token)
	local cs = FSC.cellSize(scene);

	for _, a in ipairs(actions) do
		local ok, err = pcall(function()
			if a.t == "teleport" then
				local dest = FSTRIG.findByName(scene, "trigger", a.a);

				if dest ~= nil and token ~= nil then
					local cx, cy = dest.x + dest.width / 2, dest.y + dest.height / 2;
					token:setCenter(cx, cy, token.snapToGrid);
				end;
			elseif a.t == "show" or a.t == "hide" then
				for _, it in ipairs(FSTRIG.groupItems(scene, a.a)) do
					it.visible = (a.t == "show");
				end;
			elseif a.t == "door_open" or a.t == "door_close" or a.t == "door_toggle" then
				local door = FSTRIG.findByName(scene, "door", a.a);

				if door ~= nil then
					local st = FSC.decode(udOf(door)[DOOR_FIELD]);
					local open = (a.t == "door_open") or (a.t == "door_toggle" and st.open ~= "1");
					FSTRIG.setDoor(scene, door, open);
				end;
			elseif a.t == "condition" then
				if token ~= nil then
					scene:broadcastMessage("fscond_apply", {uid = uidOf(token), cond = a.a, rounds = a.b}, true);
				end;
			elseif a.t == "damage" then
				if token ~= nil then
					local dmg = FSTRIG.rollDice(a.a);
					local bar = tonumber(a.b) or 1;

					if dmg ~= nil and bar >= 1 and bar <= 3 then
						local cur = tonumber(token["barValue" .. bar]);

						if cur ~= nil then
							token["barValue" .. bar] = tostring(cur - dmg);
						end;

						local x, y = token:getCenter(false);
						scene:broadcastMessage("fshp_float", {x = x, y = y - token.height * 0.3, text = "-" .. dmg,
						                                      color = "#FF5252"}, true);
					end;
				end;
			elseif a.t == "fx" then
				local x, y;

				if token ~= nil then
					x, y = token:getCenter(false);
				else
					x, y = trigger.x + trigger.width / 2, trigger.y + trigger.height / 2;
				end;

				local _, ft = FSC.parseDistance(a.b ~= "" and a.b or "10 ft", scene, "ft");
				local r = (ft or 10) / FSC.feetPerSquare(scene) * cs;
				scene:broadcastMessage("fsfx_play", {fx = FSC.trim(a.a), sx = x, sy = y - 4 * cs, tx = x, ty = y, r = r, n = 3}, true);
			elseif a.t == "message" then
				if FSC.trim(a.a) ~= "" then
					scene:broadcastMessage(MSG_MESSAGE, {text = a.a}, true);
				end;
			end;
		end);

		if not ok then
			FSC.logError("SceneSuite.Gatilhos", err);
		end;
	end;
end;

----------------------------------------------------------------------
-- Detecção (só no cliente do mestre)
----------------------------------------------------------------------

local function newDetector(scene)
	local det = {inside = {}};   -- [objectID do token][objectID do gatilho] = true

	function det:check(token)
		if not scene.isGM or token.objectType ~= "token" then
			return;
		end;

		local cx, cy = token:getCenter(false);
		local tid = token.objectID;
		local state = self.inside[tid] or {};
		self.inside[tid] = state;

		for _, trig in ipairs(FSTRIG.triggers(scene)) do
			local ud = udOf(trig);
			local cfg = FSC.decode(ud[TRIG_FIELD]);
			local gid = trig.objectID;
			local now = inside(trig, cx, cy);
			local was = state[gid] == true;
			state[gid] = now or nil;

			if now ~= was and cfg.enabled ~= "0" and cfg.used ~= "1" then
				local fires = (now and (cfg.event == "enter" or cfg.event == "both" or cfg.event == nil))
				              or ((not now) and (cfg.event == "leave" or cfg.event == "both"));
				local whoOk = (cfg.who == "any") or ((token.ownerUserID or "") ~= "");

				if fires and whoOk then
					if cfg.once == "1" then
						cfg.used = "1";
						ud[TRIG_FIELD] = FSC.encode(cfg);
						FSTRIG.drawTrigger(trig, cfg);
					end;

					FSTRIG.run(scene, trig, FSC.decodeList(ud[ACT_FIELD]), token);
					-- após teletransporte, reavalia sem disparar de novo o destino
					local nx, ny = token:getCenter(false);

					if nx ~= cx or ny ~= cy then
						for _, t2 in ipairs(FSTRIG.triggers(scene)) do
							state[t2.objectID] = inside(t2, nx, ny) or nil;
						end;

						return;
					end;
				end;
			end;
		end;
	end;

	return det;
end;

----------------------------------------------------------------------
-- Formulário
----------------------------------------------------------------------

local forms = {};

function FSTRIG.edit(scene, trig)
	local frm = forms[scene.objectID];

	if frm == nil then
		frm = GUI.newForm("frmFSTrigger");
		forms[scene.objectID] = frm;
	end;

	local ud = udOf(trig);

	frm:prepareFor({
		cfg = FSC.decode(ud[TRIG_FIELD]),
		actions = FSC.decodeList(ud[ACT_FIELD]),
		close = function() scene.viewport:closeForm(frm); end,

		onSave = function(cfg, actions)
			local old = FSC.decode(ud[TRIG_FIELD]);
			cfg.used = old.used or "0";
			ud[TRIG_FIELD] = FSC.encode(cfg);
			ud[ACT_FIELD] = FSC.encodeList(actions);
			FSTRIG.drawTrigger(trig, cfg);
		end,

		onTest = function(cfg, actions)
			local sel = FSC.selectedTokens(scene);
			FSTRIG.run(scene, trig, actions, sel[1]);
		end,

		onReset = function()
			local cfg = FSC.decode(ud[TRIG_FIELD]);
			cfg.used = "0";
			ud[TRIG_FIELD] = FSC.encode(cfg);
			FSTRIG.drawTrigger(trig, cfg);
		end,

		onDelete = function()
			trig:delete();
		end
	});

	FSC.showFormFit(scene.viewport, frm, 440, 560, "center");
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local det = FSC.keepAlive(scene, "fstrig_detector", newDetector(scene));
	local listeners = {};
	local drag = nil;   -- {mode, x1, y1, x2, y2} (mundo)

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Gatilhos", 46);

	-- mensagens de gatilho aparecem para todos que têm o plugin
	FSC.keepAlive(scene, "fstrig_msg", scene:newBroadcastListener(MSG_MESSAGE, function(sender, id, msg)
		if type(msg) == "table" and type(msg.text) == "string" then
			showMessage(msg.text);
		end;
	end));

	-- detecção: cada token que se move é verificado (no cliente do mestre)
	FSC.watchTokenBounds(scene, "fstrig", function(token)
		det:check(token);
	end);

	local function clearListeners()
		for _, l in ipairs(listeners) do
			viewport:unlisten(l);
		end;

		listeners = {};
		drag = nil;
		viewport:needRepaint();
	end;

	local function snap(x, y)
		local gx, gy, cs = FSC.gridOrigin(scene);
		return gx + math.floor((x - gx) / cs + 0.5) * cs, gy + math.floor((y - gy) / cs + 0.5) * cs;
	end;

	-- arrastar um retângulo (encaixa no grid; SHIFT = livre)
	local function startRectTool(mode, onDone)
		clearListeners();

		listeners[#listeners + 1] = viewport:listen("onMouseDown", function(event)
			if event.button ~= "left" then
				drag = nil;
				viewport:needRepaint();
				return;
			end;

			local x, y = viewport:screenToWorld(event.x, event.y);

			if not event.shiftKey then x, y = snap(x, y); end;

			drag = {x1 = x, y1 = y, x2 = x, y2 = y};
		end);

		listeners[#listeners + 1] = viewport:listen("onMouseMove", function(event)
			if drag ~= nil then
				local x, y = viewport:screenToWorld(event.x, event.y);

				if not event.shiftKey then x, y = snap(x, y); end;

				drag.x2, drag.y2 = x, y;
				viewport:needRepaint();
			end;
		end);

		listeners[#listeners + 1] = viewport:listen("onMouseUp", function(event)
			if drag == nil then return; end;

			local x1, x2 = math.min(drag.x1, drag.x2), math.max(drag.x1, drag.x2);
			local y1, y2 = math.min(drag.y1, drag.y2), math.max(drag.y1, drag.y2);
			drag = nil;
			viewport:needRepaint();

			local cs = FSC.cellSize(scene);

			if (x2 - x1) < cs * 0.2 or (y2 - y1) < cs * 0.2 then
				return;
			end;

			onDone(x1, y1, x2, y2);
		end);

		listeners[#listeners + 1] = viewport:listen("onAfterDrawLayers", function()
			if drag == nil then return; end;
			local ax, ay = viewport:worldToScreen(math.min(drag.x1, drag.x2), math.min(drag.y1, drag.y2));
			local bx, by = viewport:worldToScreen(math.max(drag.x1, drag.x2), math.max(drag.y1, drag.y2));
			viewport:prepareFill(mode == "door" and "#8D6E63" or "#B388FF");
			viewport:fillRect(ax, ay, bx, by, 0.25);
			viewport:prepareDraw(mode == "door" and "#5D4037" or "#B388FF", 2, "flat", "miter", "dash");
			viewport:drawRect(ax, ay, bx, by, 0.9);
		end);
	end;

	local function newDrawing(x1, y1, x2, y2)
		local ud = scene.items:addUserDrawing("objects");
		ud:markAsMyDrawing();
		ud.x, ud.y = x1, y1;
		ud.width, ud.height = x2 - x1, y2 - y1;
		ud.snapToGrid = false;
		return ud;
	end;

	local function gmTool(title, icon, order, mode, onDone)
		viewport:addToolButton(TOOL_CATEGORY, title, icon, order, {selectable = true, defaultOfCategory = (order == 10)},
			function()
				if not scene.isGM then
					showMessage("Apenas o mestre cria gatilhos e portas.");
					viewport:selectDefaultToolButton();
					return;
				end;

				viewport.cursor = "cross";
				startRectTool(mode, onDone);
			end,
			function()
				viewport.cursor = "default";
				clearListeners();
			end);
	end;

	gmTool("Gatilhos: arraste para criar um gatilho", "/images/tool_trigger.png", 10, "trigger",
		function(x1, y1, x2, y2)
			local d = newDrawing(x1, y1, x2, y2);
			d.visible = false;   -- só o mestre vê
			local n = #FSTRIG.triggers(scene) + 1;
			local cfg = {name = "Gatilho " .. n, event = "enter", who = "players", once = "0", enabled = "1", used = "0"};
			local ud = d.userData;
			ud[TRIG_FIELD] = FSC.encode(cfg);
			ud[ACT_FIELD] = "";
			FSTRIG.drawTrigger(d, cfg);
			FSTRIG.edit(scene, d);
		end);

	gmTool("Portas: arraste para criar uma porta (bloqueia visão quando fechada)", "/images/tool_door.png", 11, "door",
		function(x1, y1, x2, y2)
			Dialogs.inputQuery("Nova porta", "Nome da porta:", "Porta", function(name)
				local d = newDrawing(x1, y1, x2, y2);
				local ud = d.userData;
				ud[DOOR_FIELD] = FSC.encode({name = FSC.trim(name), open = "0"});
				FSTRIG.setDoor(scene, d, false);
			end);
		end);

	-- editar gatilho / alternar porta com um clique
	viewport:addToolButton(TOOL_CATEGORY, "Gatilhos: clique para editar um gatilho ou abrir/fechar uma porta",
		"/images/tool_edit.png", 12, {selectable = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre edita gatilhos e portas.");
				viewport:selectDefaultToolButton();
				return;
			end;

			clearListeners();
			listeners[#listeners + 1] = viewport:listen("onMouseDown", function(event)
				if event.button ~= "left" then return; end;
				local x, y = viewport:screenToWorld(event.x, event.y);
				local list = scene.items:enumAtPoint(x, y);

				for i = #list, 1, -1 do
					local it = list[i];

					if FSTRIG.isDoor(it) then
						local st = FSC.decode(udOf(it)[DOOR_FIELD]);
						FSTRIG.setDoor(scene, it, st.open ~= "1");
						return;
					elseif FSTRIG.isTrigger(it) then
						FSTRIG.edit(scene, it);
						return;
					end;
				end;
			end);
		end,
		function()
			clearListeners();
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Gatilhos: dar nome de grupo aos itens selecionados (para mostrar/esconder)",
		"/images/tool_group.png", 13, {dontFocus = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre define grupos.");
				return;
			end;

			local sel = scene.items.selection or {};

			if #sel == 0 then
				showMessage("Selecione tokens ou desenhos primeiro.");
				return;
			end;

			local cur = udOf(sel[1]) and udOf(sel[1])[GROUP_FIELD] or "";

			Dialogs.inputQuery("Grupo", "Nome do grupo (vazio remove):", cur or "", function(name)
				for _, it in ipairs(sel) do
					local ud = udOf(it);

					if ud ~= nil then
						ud[GROUP_FIELD] = FSC.trim(name);
					end;
				end;
			end);
		end);
end);
