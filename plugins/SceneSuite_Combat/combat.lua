--[[
  Scene Suite - Tracker de Combate (inspirado no "Combat Tracker Dock")

  Dados (scene.userData, sincronizados para todos com o Scene aberto):
    fsCombat      -> {active, round, turn}
    fsCombatList  -> lista de {u = id do token, n = nome, i = iniciativa,
                     m = modificador, h = oculto p/ jogadores ("1")}
  Cada token recebe um id estável em token.userData.fsUid (o objectID do
  Scene é local de cada computador e não serve para sincronizar).

  Visões: janela acoplável da mesa (frmFSCombatDock) e painel dentro do
  Scene (frmFSCombatPanel). Ambas são geradas do mesmo template e se
  registram aqui para serem atualizadas.

  Fim de cada volta: envia "fscond_advance" pelo Scene para o plugin de
  Condições (se instalado) avançar as durações.
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
local TOOL_CATEGORY = "SSuite_Combat";
local STATE_FIELD = "fsCombat";
local LIST_FIELD = "fsCombatList";
local UID_FIELD = "fsUid";
local TURN_PREFIX = "fscombat_turn";
local ADVANCE_MESSAGE = "fscond_advance";
local MAX_ROWS = 40;

FSCOMBAT = FSCOMBAT or {};
local FSCOMBAT = FSCOMBAT;
FSCOMBAT.MAX_ROWS = MAX_ROWS;
FSCOMBAT.scenes = FSCOMBAT.scenes or {};   -- scenes abertos (objectID -> scene)
FSCOMBAT.views = FSCOMBAT.views or {};     -- formulários registrados

local uidCounter = 0;

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

function FSCOMBAT.getState(scene)
	local ud = scene.userData;
	local st = FSC.decode(ud and ud[STATE_FIELD]);
	st.active = st.active == "1";
	st.round = tonumber(st.round) or 1;
	st.turn = tonumber(st.turn) or 1;
	local list = FSC.decodeList(ud and ud[LIST_FIELD]);

	for _, e in ipairs(list) do
		e.i = tonumber(e.i);
		e.m = tonumber(e.m) or 0;
	end;

	return st, list;
end;

function FSCOMBAT.save(scene, st, list)
	local ud = scene.userData;

	if ud == nil then
		return;
	end;

	if #list == 0 then
		st.turn = 1;
	elseif st.turn > #list then
		st.turn = #list;
	end;

	local rows = {};

	for _, e in ipairs(list) do
		rows[#rows + 1] = {u = e.u, n = e.n, i = e.i ~= nil and tostring(e.i) or "", m = tostring(e.m or 0),
		                   h = e.h or "0"};
	end;

	ud[STATE_FIELD] = FSC.encode({active = st.active and "1" or "0", round = tostring(st.round), turn = tostring(st.turn)});
	ud[LIST_FIELD] = FSC.encodeList(rows);
	FSCOMBAT.highlight(scene, st, list);
	FSCOMBAT.notify(scene);
end;

-- id estável do token (cria se ainda não tiver)
function FSCOMBAT.uidOf(token)
	local ud = token.userData;

	if ud == nil then
		return nil;
	end;

	local u = ud[UID_FIELD];

	if u == nil or u == "" then
		uidCounter = uidCounter + 1;
		u = string.format("%s-%d-%d-%d", tostring(token.scene and token.scene.currentUserID or "u"),
		                  math.floor(system.getTickCount()), uidCounter, math.random(1, 999999));
		ud[UID_FIELD] = u;
	end;

	return u;
end;

function FSCOMBAT.tokenMap(scene)
	local map = {};

	for _, t in ipairs(FSC.allTokens(scene)) do
		local ud = t.userData;
		local u = ud and ud[UID_FIELD];

		if u ~= nil and u ~= "" then
			map[u] = t;
		end;
	end;

	return map;
end;

function FSCOMBAT.canControl(scene)
	return scene.isGM == true;
end;

-- Pode editar a iniciativa desta entrada? (mestre ou dono do token)
function FSCOMBAT.canEditEntry(scene, e, map)
	if scene.isGM then
		return true;
	end;

	local t = (map or FSCOMBAT.tokenMap(scene))[e.u];
	return t ~= nil and FSC.canEdit(scene, t);
end;

----------------------------------------------------------------------
-- Ações
----------------------------------------------------------------------

function FSCOMBAT.addTokens(scene, tokens, hidden)
	local st, list = FSCOMBAT.getState(scene);
	local present = {};

	for _, e in ipairs(list) do
		present[e.u] = true;
	end;

	local added = 0;

	for _, t in ipairs(tokens) do
		local u = FSCOMBAT.uidOf(t);

		if u ~= nil and not present[u] and #list < MAX_ROWS then
			local name = (t.name ~= nil and t.name ~= "") and t.name or "Token";
			list[#list + 1] = {u = u, n = name, i = nil, m = 0, h = hidden and "1" or "0"};
			present[u] = true;
			added = added + 1;
		end;
	end;

	st.active = true;
	FSCOMBAT.save(scene, st, list);
	return added;
end;

function FSCOMBAT.addCustom(scene, name)
	local st, list = FSCOMBAT.getState(scene);

	if #list >= MAX_ROWS then
		return;
	end;

	uidCounter = uidCounter + 1;
	list[#list + 1] = {u = "x-" .. math.floor(system.getTickCount()) .. "-" .. uidCounter, n = name, i = nil, m = 0, h = "0"};
	st.active = true;
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.removeAt(scene, idx)
	local st, list = FSCOMBAT.getState(scene);

	if list[idx] == nil then
		return;
	end;

	table.remove(list, idx);

	if idx < st.turn then
		st.turn = st.turn - 1;
	end;

	FSCOMBAT.save(scene, st, list);
end;

-- Ordena por iniciativa (maior primeiro); empate pelo modificador.
-- Mantém o turno apontando para a mesma criatura.
local function sortList(st, list)
	local current = list[st.turn];

	for k, e in ipairs(list) do
		e._k = k;
	end;

	table.sort(list, function(a, b)
		local ia, ib = a.i or -math.huge, b.i or -math.huge;

		if ia ~= ib then return ia > ib; end;
		if (a.m or 0) ~= (b.m or 0) then return (a.m or 0) > (b.m or 0); end;
		return a._k < b._k;
	end);

	for k, e in ipairs(list) do
		e._k = nil;

		if e == current then
			st.turn = k;
		end;
	end;
end;

function FSCOMBAT.setInit(scene, idx, value)
	local st, list = FSCOMBAT.getState(scene);

	if list[idx] == nil then
		return;
	end;

	list[idx].i = tonumber(value);
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.setMod(scene, idx, value)
	local st, list = FSCOMBAT.getState(scene);

	if list[idx] == nil then
		return;
	end;

	list[idx].m = tonumber(value) or 0;
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.toggleHidden(scene, idx)
	local st, list = FSCOMBAT.getState(scene);

	if list[idx] == nil then
		return;
	end;

	list[idx].h = (list[idx].h == "1") and "0" or "1";
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.move(scene, idx, delta)
	local st, list = FSCOMBAT.getState(scene);
	local j = idx + delta;

	if list[idx] == nil or list[j] == nil then
		return;
	end;

	local current = list[st.turn];
	list[idx], list[j] = list[j], list[idx];

	for k, e in ipairs(list) do
		if e == current then st.turn = k; end;
	end;

	FSCOMBAT.save(scene, st, list);
end;

-- Rola d20 + modificador. onlyMissing: só quem ainda não tem iniciativa.
-- onlyHidden: só os ocultos (monstros do mestre).
function FSCOMBAT.roll(scene, onlyMissing, onlyHidden)
	local st, list = FSCOMBAT.getState(scene);

	for _, e in ipairs(list) do
		if (not onlyMissing or e.i == nil) and (not onlyHidden or e.h == "1") then
			e.i = math.random(1, 20) + (e.m or 0);
		end;
	end;

	sortList(st, list);
	st.turn = 1;
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.sort(scene)
	local st, list = FSCOMBAT.getState(scene);
	sortList(st, list);
	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.next(scene)
	local st, list = FSCOMBAT.getState(scene);

	if #list == 0 then
		return;
	end;

	st.active = true;
	st.turn = st.turn + 1;

	if st.turn > #list then
		st.turn = 1;
		st.round = st.round + 1;
		-- fim da volta: o plugin de Condições (se instalado) avança as durações
		scene:broadcastMessage(ADVANCE_MESSAGE, {round = st.round}, true);
	end;

	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.prev(scene)
	local st, list = FSCOMBAT.getState(scene);

	if #list == 0 then
		return;
	end;

	st.turn = st.turn - 1;

	if st.turn < 1 then
		if st.round > 1 then
			st.round = st.round - 1;
			st.turn = #list;
		else
			st.turn = 1;
		end;
	end;

	FSCOMBAT.save(scene, st, list);
end;

function FSCOMBAT.endCombat(scene)
	FSCOMBAT.save(scene, {active = false, round = 1, turn = 1}, {});
end;

function FSCOMBAT.resetRounds(scene)
	local st, list = FSCOMBAT.getState(scene);
	st.round = 1;
	st.turn = 1;
	FSCOMBAT.save(scene, st, list);
end;

----------------------------------------------------------------------
-- Anel no token da vez (persistido: todos veem, mesmo sem o plugin)
----------------------------------------------------------------------

local RING = nil;

function FSCOMBAT.highlight(scene, st, list)
	if RING == nil then
		RING = FSC.polysToPath({FSC.circlePoly(0, 0, 1, 40)}, true);
	end;

	local current = st.active and list[st.turn] or nil;
	local map = FSCOMBAT.tokenMap(scene);

	for u, t in pairs(map) do
		local isCurrent = current ~= nil and current.u == u;
		local has = FSC.hasOps(t.canvas, TURN_PREFIX);

		if has and not isCurrent then
			FSC.removeOps(t.canvas, TURN_PREFIX);
		elseif isCurrent and FSC.canEdit(scene, t) then
			FSC.removeOps(t.canvas, TURN_PREFIX);
			FSC.addPathOp(t.canvas, TURN_PREFIX, RING, {-0.09, -0.09, 1.09, 1.09},
				{metric = "canvasMetric", xOrigin = 0, yOrigin = 0, fill = "#FFD54F26", stroke = "#FFD54FF0",
				 strokeSize = 3, outOfOrderMode = "beforeOwnerLayer", z = -5,
				 visibility = (current.h == "1") and "gmOnly" or "everyone"});
		end;
	end;
end;

----------------------------------------------------------------------
-- Visões (dock / painel)
----------------------------------------------------------------------

function FSCOMBAT.registerView(view)
	FSCOMBAT.views[view] = true;
end;

function FSCOMBAT.unregisterView(view)
	FSCOMBAT.views[view] = nil;
end;

function FSCOMBAT.notify(scene)
	for view in pairs(FSCOMBAT.views) do
		pcall(function()
			if view.refreshFromScene ~= nil then
				view:refreshFromScene();
			end;
		end);
	end;
end;

-- Scene aberto da mesa (para a janela acoplável)
function FSCOMBAT.sceneForMesa(mesa)
	local fallback = nil;

	for id, sc in pairs(FSCOMBAT.scenes) do
		if not sc.isObjectAlive then
			FSCOMBAT.scenes[id] = nil;
		else
			local ok, m = pcall(Firecast.getMesaDe, sc);

			if ok and m ~= nil and mesa ~= nil and (m == mesa or m.codigoInterno == mesa.codigoInterno) then
				return sc;
			end;

			fallback = fallback or sc;
		end;
	end;

	if mesa == nil then
		return fallback;
	end;

	return nil;
end;

-- Dados prontos para desenhar a lista (filtra ocultos para jogadores)
function FSCOMBAT.viewModel(scene)
	local st, list = FSCOMBAT.getState(scene);
	local map = FSCOMBAT.tokenMap(scene);
	local rows = {};

	for idx, e in ipairs(list) do
		if scene.isGM or e.h ~= "1" then
			local t = map[e.u];
			local img = nil;

			if t ~= nil then
				pcall(function()
					local im = t.image;
					img = im and im.url;
				end);
			end;

			rows[#rows + 1] = {idx = idx, name = e.n, init = e.i, mod = e.m, hidden = e.h == "1",
			                   current = st.active and idx == st.turn, image = img,
			                   canEdit = FSCOMBAT.canEditEntry(scene, e, map), token = t};
		end;
	end;

	return {active = st.active, round = st.round, rows = rows, isGM = scene.isGM == true, count = #list};
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local panel = nil;
	local panelOpen = false;
	local lastRaw = nil;

	FSCOMBAT.scenes[scene.objectID] = scene;
	FSC.setupCategory(viewport, TOOL_CATEGORY, "Combate", 48);

	-- atualiza as visões quando outro usuário muda o combate
	local poll;
	poll = setInterval(function()
		if not scene.isObjectAlive then
			clearInterval(poll);
			FSCOMBAT.scenes[scene.objectID] = nil;
			return;
		end;

		local ud = scene.userData;
		local raw = ud and ((ud[STATE_FIELD] or "") .. "#" .. (ud[LIST_FIELD] or "")) or "";

		if raw ~= lastRaw then
			lastRaw = raw;
			FSCOMBAT.notify(scene);
		end;
	end, 700);

	local function gmOnly(fn)
		return function()
			if not FSCOMBAT.canControl(scene) then
				showMessage("Apenas o mestre controla o combate.");
				return;
			end;

			fn();
		end;
	end;

	viewport:addToolButton(TOOL_CATEGORY, "Combate: abrir/fechar o tracker no Scene",
		"/images/tool_combat.png", 10, {defaultOfCategory = true},
		function()
			if panelOpen and panel ~= nil then
				viewport:closeForm(panel);
				panelOpen = false;
				return;
			end;

			if panel == nil then
				panel = GUI.newForm("frmFSCombatPanel");
			end;

			panel:bindScene(scene, function()
				viewport:closeForm(panel);
				panelOpen = false;
			end);

			panelOpen = true;
			FSC.showFormFit(viewport, panel, 300, 420, "right", 200, 160);
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Combate: próximo turno",
		"/images/tool_next.png", 11, {dontFocus = true}, gmOnly(function() FSCOMBAT.next(scene); end));

	viewport:addToolButton(TOOL_CATEGORY, "Combate: turno anterior",
		"/images/tool_prev.png", 12, {dontFocus = true}, gmOnly(function() FSCOMBAT.prev(scene); end));

	viewport:addToolButton(TOOL_CATEGORY, "Combate: adicionar os tokens selecionados",
		"/images/tool_add.png", 13, {dontFocus = true}, gmOnly(function()
			local sel = FSC.selectedTokens(scene);

			if #sel == 0 then
				showMessage("Selecione os tokens primeiro.");
				return;
			end;

			FSCOMBAT.addTokens(scene, sel, false);
		end));

	viewport:addToolButton(TOOL_CATEGORY, "Combate: rolar iniciativa de quem ainda não tem",
		"/images/tool_roll.png", 14, {dontFocus = true}, gmOnly(function() FSCOMBAT.roll(scene, true, false); end));

	viewport:addToolButton(TOOL_CATEGORY, "Combate: encerrar o combate",
		"/images/tool_end.png", 15, {dontFocus = true}, gmOnly(function()
			Dialogs.confirmYesNo("Encerrar o combate e limpar a lista?", function(yes)
				if yes then FSCOMBAT.endCombat(scene); end;
			end);
		end));

	-- iniciativa vinda da Barra de Tokens (pedido de rolagem "Iniciativa")
	FSC.keepAlive(scene, "fscombat_init", scene:newBroadcastListener("fscombat_init", function(sender, id, msg)
		if not scene.isGM or type(msg) ~= "table" or type(msg.uid) ~= "string" then return; end;

		local st, list = FSCOMBAT.getState(scene);

		for idx, e in ipairs(list) do
			if e.u == msg.uid then
				FSCOMBAT.setInit(scene, idx, tonumber(msg.value));
				return;
			end;
		end;
	end));

	-- tokens apagados somem da lista no próximo salvamento; tokens renomeados
	-- atualizam o nome exibido
	scene.items:listen("onItemRemoved", function()
		FSC.debounce("fscombat_rm" .. scene.objectID, 500, function()
			if scene.isObjectAlive then
				FSCOMBAT.notify(scene);
			end;
		end);
	end);
end);
