--[[
  Scene Suite - Barra de Tokens (inspirado no "Monk's TokenBar")

  - Barra (painel no Scene) com os tokens dos jogadores: retrato, nome, PV
    (barra 1). Clique: centraliza a câmera e seleciona o token.
  - O mestre pede rolagens (salvamentos, perícias, iniciativa...) com CD
    opcional e modo secreto. Cada jogador recebe um popup para o(s) seu(s)
    token(s), confirma o modificador (fica salvo no token) e rola d20.
  - Resultados voltam ao mestre (e a todos, se não for secreta) com
    sucesso/falha contra a CD. "Rolar pendentes": o mestre rola pelos
    ausentes com o modificador salvo.
  - Iniciativa: os resultados também vão para o Tracker de Combate
    (mensagem "fscombat_init").

  Observação: a ficha de cada sistema tem nomes de campos diferentes, então
  o modificador é digitado (e lembrado por token) em vez de lido da ficha.
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
local TOOL_CATEGORY = "SSuite_TokenBar";
local REQ_MESSAGE = "fstb_req";
local RES_MESSAGE = "fstb_res";
local MODS_FIELD = "fsRollMods";
local MAX_TILES = 16;

FSTB = FSTB or {};
local FSTB = FSTB;

local function udOf(item)
	local ok, ud = pcall(function() return item.userData; end);
	return ok and ud or nil;
end;

function FSTB.uidOf(token)
	local ud = udOf(token);

	if ud == nil then return nil; end;

	local u = ud.fsUid;

	if u == nil or u == "" then
		u = string.format("t-%d-%d", math.floor(system.getTickCount()), math.random(1, 999999));
		ud.fsUid = u;
	end;

	return u;
end;

function FSTB.tokenByUid(scene, uid)
	for _, t in ipairs(FSC.allTokens(scene)) do
		local ud = udOf(t);

		if ud ~= nil and ud.fsUid == uid then
			return t;
		end;
	end;

	return nil;
end;

-- Tokens de jogadores: têm dono (ownerUserID) definido
function FSTB.playerTokens(scene)
	local out = {};

	for _, t in ipairs(FSC.allTokens(scene)) do
		if (t.ownerUserID or "") ~= "" and (scene.isGM or t.visible ~= false) then
			out[#out + 1] = t;
		end;
	end;

	table.sort(out, function(a, b) return (a.name or "") < (b.name or ""); end);
	return out;
end;

function FSTB.getMod(token, key)
	local mods = FSC.decode(udOf(token) and udOf(token)[MODS_FIELD]);
	return tonumber(mods[key]) or 0;
end;

function FSTB.setMod(token, key, mod)
	local ud = udOf(token);

	if ud == nil then return; end;

	local mods = FSC.decode(ud[MODS_FIELD]);
	mods[key] = tostring(mod);
	ud[MODS_FIELD] = FSC.encode(mods);
end;

local function signed(n)
	return (n >= 0) and ("+" .. n) or tostring(n);
end;

----------------------------------------------------------------------
-- Estado por scene
----------------------------------------------------------------------

local function newState(scene)
	local st = {
		last = nil,          -- último pedido: {rid, label, key, dc, secret, targets = {{uid, name}}, results = {}}
		lastText = "",
		queue = {},          -- pedidos aguardando o jogador rolar
		rollOpen = false
	};
	return st;
end;

function FSTB.resultsModel(st)
	local r = st.last;

	if r == nil then
		return {title = "Nenhum pedido ainda.", rows = {}};
	end;

	local title = r.label .. ((r.dc ~= nil) and (" — CD " .. r.dc) or "") .. (r.secret and " (secreta)" or "");
	local rows = {};

	for _, tg in ipairs(r.targets) do
		local res = r.results[tg.uid];
		local row = {name = tg.name};

		if res ~= nil then
			row.total = tostring(res.total);

			if r.dc ~= nil then
				local ok = res.total >= r.dc;
				row.status = ok and "sucesso" or "falha";
				row.color = ok and "#69F0AE" or "#FF8A80";
			else
				row.status = "d20 " .. res.d20 .. " " .. signed(res.mod);
				row.color = "#B0BEC5";
			end;
		else
			row.status = "aguardando";
			row.color = "#B0BEC5";
		end;

		rows[#rows + 1] = row;
	end;

	return {title = title, rows = rows};
end;

function FSTB.summary(st)
	local r = st.last;

	if r == nil then return ""; end;

	local parts = {};

	for _, tg in ipairs(r.targets) do
		local res = r.results[tg.uid];

		if res ~= nil then
			local mark = "";

			if r.dc ~= nil then
				mark = (res.total >= r.dc) and " ✓" or " ✗";
			end;

			parts[#parts + 1] = tg.name .. " " .. res.total .. mark;
		end;
	end;

	return r.label .. ((r.dc ~= nil) and (" CD " .. r.dc) or "") .. ": " .. ((#parts > 0) and table.concat(parts, ", ") or "aguardando...");
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local st = FSC.keepAlive(scene, "fstb_state", newState(scene));
	local bar, req, roll = nil, nil, nil;
	local barOpen, reqOpen = false, false;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Barra de Tokens", 45);

	local function refreshAll()
		if barOpen and bar ~= nil then bar:refresh(); end;
		if reqOpen and req ~= nil then req:refresh(); end;
	end;

	local function barModel()
		local tiles = {};
		local selected = {};

		for _, t in ipairs(FSC.selectedTokens(scene)) do
			selected[t] = true;
		end;

		for _, t in ipairs(FSTB.playerTokens(scene)) do
			if #tiles >= MAX_TILES then break; end;

			local img = nil;
			pcall(function() img = t.image and t.image.url; end);
			local v, m = tonumber(t.barValue1), tonumber(t.barMax1);
			local hp = "";

			if v ~= nil then
				hp = "PV " .. FSC.fmtNum(v) .. ((m ~= nil) and ("/" .. FSC.fmtNum(m)) or "");
			end;

			local info = "";
			local ud = udOf(t);

			if ud ~= nil and ud.fsConditions ~= nil and ud.fsConditions ~= "" then
				local n = #FSC.decodeList(ud.fsConditions);
				info = n .. ((n == 1) and " condição" or " condições");
			end;

			tiles[#tiles + 1] = {uid = FSTB.uidOf(t), name = (t.name ~= "" and t.name) or "token", image = img,
			                     hp = hp, info = info, selected = selected[t] == true};
		end;

		return {tiles = tiles, last = st.lastText, isGM = scene.isGM == true};
	end;

	-- centraliza a câmera no token e seleciona
	local function focus(uid)
		local t = FSTB.tokenByUid(scene, uid);

		if t == nil then return; end;

		local cx, cy = t:getCenter(false);
		local s = viewport.scale;

		if s ~= nil and s > 0 then
			viewport.worldX = cx - (viewport.width / s) / 2;
			viewport.worldY = cy - (viewport.height / s) / 2;
		end;

		scene.items:clearSelection();
		t.selected = true;
		refreshAll();
	end;

	----------------------------------------------------------------- rolagem
	local function showNextRoll()
		if st.rollOpen or #st.queue == 0 then return; end;

		local item = table.remove(st.queue, 1);
		local t = FSTB.tokenByUid(scene, item.uid);

		if t == nil then
			showNextRoll();
			return;
		end;

		if roll == nil then
			roll = GUI.newForm("frmFSTBRoll");
		end;

		st.rollOpen = true;
		local r = item.req;

		roll:prepareFor({
			title = r.label .. " — " .. ((t.name ~= "" and t.name) or "token"),
			sub = ((r.dc ~= nil and not r.secret) and ("CD " .. r.dc .. ". ") or "") .. "Pedido pelo mestre.",
			mod = tostring(FSTB.getMod(t, r.key)),
			onRoll = function(mod)
				FSTB.setMod(t, r.key, mod);
				local d20 = math.random(1, 20);
				local total = d20 + mod;
				scene:broadcastMessage(RES_MESSAGE, {rid = r.rid, uid = item.uid, total = total, d20 = d20, mod = mod,
				                                     secret = r.secret}, true);
				local txt = "d20 = " .. d20 .. "  " .. signed(mod) .. "  =  " .. total;

				if d20 == 20 then txt = txt .. "  (20 natural!)"; elseif d20 == 1 then txt = txt .. "  (1 natural)"; end;

				return txt;
			end,
			onClose = function()
				viewport:closeForm(roll);
				st.rollOpen = false;
				showNextRoll();
			end
		});

		FSC.showFormFit(viewport, roll, 320, 200, "center", 220, 160);
	end;

	-- pedido recebido: pergunta ao dono de cada token alvo
	FSC.keepAlive(scene, "fstb_req", scene:newBroadcastListener(REQ_MESSAGE, function(sender, id, r)
		if type(r) ~= "table" or type(r.rid) ~= "string" or type(r.targets) ~= "table" then return; end;

		r.results = r.results or {};

		if not scene.isGM then
			if not r.secret then
				st.last = r;
				st.lastText = FSTB.summary(st);
			end;

			for _, tg in ipairs(r.targets) do
				local t = FSTB.tokenByUid(scene, tg.uid);

				if t ~= nil and t.ownerUserID == scene.currentUserID then
					st.queue[#st.queue + 1] = {uid = tg.uid, req = r};
				end;
			end;

			showNextRoll();
			refreshAll();
		end;
	end));

	-- resultado recebido
	FSC.keepAlive(scene, "fstb_res", scene:newBroadcastListener(RES_MESSAGE, function(sender, id, res)
		if type(res) ~= "table" or st.last == nil or res.rid ~= st.last.rid then return; end;
		if res.secret and not scene.isGM then return; end;

		local total = tonumber(res.total);

		if total == nil then return; end;

		st.last.results[res.uid] = {total = total, d20 = tonumber(res.d20) or 0, mod = tonumber(res.mod) or 0};
		st.lastText = FSTB.summary(st);

		-- iniciativa vai para o Tracker de Combate (o cliente do mestre aplica)
		if scene.isGM and st.last.key == "init" then
			scene:broadcastMessage("fscombat_init", {uid = res.uid, value = total}, true);
		end;

		refreshAll();
	end));

	----------------------------------------------------------------- pedidos (mestre)
	local function sendRequest(o)
		local tokens;

		if o.target == "sel" then
			tokens = FSC.selectedTokens(scene);
		else
			tokens = FSTB.playerTokens(scene);
		end;

		if #tokens == 0 then
			showMessage("Nenhum token para pedir a rolagem.");
			return;
		end;

		local targets = {};

		for _, t in ipairs(tokens) do
			targets[#targets + 1] = {uid = FSTB.uidOf(t), name = (t.name ~= "" and t.name) or "token"};
		end;

		local r = {rid = string.format("r%d-%d", math.floor(system.getTickCount()), math.random(1, 99999)),
		           label = o.label, key = o.key, dc = o.dc, secret = o.secret == true, targets = targets, results = {}};
		st.last = r;
		st.lastText = FSTB.summary(st);
		scene:broadcastMessage(REQ_MESSAGE, r, true);
		refreshAll();
	end;

	local function rollPending()
		local r = st.last;

		if r == nil then return; end;

		for _, tg in ipairs(r.targets) do
			if r.results[tg.uid] == nil then
				local t = FSTB.tokenByUid(scene, tg.uid);
				local mod = (t ~= nil) and FSTB.getMod(t, r.key) or 0;
				local d20 = math.random(1, 20);
				scene:broadcastMessage(RES_MESSAGE, {rid = r.rid, uid = tg.uid, total = d20 + mod, d20 = d20, mod = mod,
				                                     secret = r.secret}, true);
			end;
		end;
	end;

	local function openRequest()
		if not scene.isGM then
			showMessage("Apenas o mestre pede rolagens.");
			return;
		end;

		if req == nil then
			req = GUI.newForm("frmFSTBRequest");
		end;

		req:prepareFor({
			onSend = sendRequest,
			onRollPending = rollPending,
			results = function() return FSTB.resultsModel(st); end,
			close = function() viewport:closeForm(req); reqOpen = false; end
		});

		reqOpen = true;
		FSC.showFormFit(viewport, req, 360, 470, "center");
	end;

	----------------------------------------------------------------- barra
	local function closeBar()
		barOpen = false;

		if bar ~= nil then viewport:closeForm(bar); end;
	end;

	local function openBar()
		if bar == nil then
			bar = GUI.newForm("frmFSTokenBar");
		end;

		bar:prepareFor({
			model = barModel,
			onTile = focus,
			onRequest = openRequest,
			onClose = closeBar
		});

		barOpen = true;
		FSC.showFormFit(viewport, bar, 680, 128, "bottom", 200, 90);
	end;

	-- mantém PV/seleção atualizados enquanto a barra está aberta
	local poll;
	poll = setInterval(function()
		if not scene.isObjectAlive then
			clearInterval(poll);
			return;
		end;

		if barOpen and bar ~= nil then
			bar:refresh();
		end;
	end, 1000);

	scene.items:listen("onItemSelected", function() if barOpen then bar:refresh(); end; end);
	scene.items:listen("onItemDeselected", function() if barOpen then bar:refresh(); end; end);

	viewport:addToolButton(TOOL_CATEGORY, "Barra de tokens: abrir/fechar",
		"/images/tool_bar.png", 10, {defaultOfCategory = true},
		function()
			if barOpen then closeBar(); else openBar(); end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Barra de tokens: pedir rolagem (mestre)",
		"/images/tool_request.png", 11, {dontFocus = true}, openRequest);
end);
