--[[
  Scene Suite - Condições
  Ícones de condições/status sobre os tokens, com duração em rodadas.

  Dados:
    token.userData.fsConditions  -> lista codificada {id, r(rodadas), h(oculto), n(nome), c(cor)}
    scene.userData.fsCondCfg     -> configuração da mesa (posição, tamanho, nomes)
  Desenho:
    operações gráficas no canvas do token com prefixo "fscond_" (persistem e
    aparecem para todos, mesmo para quem não tem o plugin instalado).
]]

require("scene.lua");
require("firecast.lua");
require("log.lua");
require("utils.lua");
require("system.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");
require("condData.lua");

local FSC = FSC;
local PREFIX = "fscond_";
local UD_FIELD = "fsConditions";
local CFG_FIELD = "fsCondCfg";
local TOOL_CATEGORY = "SSuite_Conditions";

FSCOND = FSCOND or {};
local FSCOND = FSCOND;

local byId = {};

for _, c in ipairs(FSCOND_DATA.list) do
	byId[c.id] = c;
end;

----------------------------------------------------------------------
-- Dados
----------------------------------------------------------------------

-- Rodadas por unidade (Pathfinder: 1 minuto = 10 rodadas)
FSCOND.UNIT_ROUNDS = {r = 1, min = 10, h = 600};

-- Converte quantidade + unidade em rodadas.
-- unit: "r" | "min" | "h". Um sufixo digitado no texto ("1min", "2h") tem
-- prioridade sobre a unidade escolhida. "" -> nil (indefinida)
function FSCOND.parseRounds(txt, unit)
	local s = FSC.trim(txt):lower():gsub(",", ".");

	if s == "" or s == "∞" then
		return nil;
	end;

	local n = tonumber(s:match("^([%d%.]+)"));

	if n == nil then
		return nil;
	end;

	local typed = unit;
	local suffix = s:match("^[%d%.]+%s*(%a*)");

	if suffix == "min" or suffix == "m" or suffix == "minuto" or suffix == "minutos" then
		typed = "min";
	elseif suffix == "h" or suffix == "hora" or suffix == "horas" then
		typed = "h";
	elseif suffix == "r" or suffix == "rd" or suffix == "rodada" or suffix == "rodadas" then
		typed = "r";
	end;

	n = n * (FSCOND.UNIT_ROUNDS[typed or "r"] or 1);

	n = math.floor(n + 0.5);

	if n <= 0 then
		return nil;
	end;

	return n;
end;

-- Unidade efetiva de uma entrada (a que o usuário escolheu)
local function entryUnit(e)
	local u = e.u;

	if FSCOND.UNIT_ROUNDS[u] == nil then
		u = "r";
	end;

	return u;
end;

-- Rodadas restantes expressas na unidade escolhida (para o formulário)
function FSCOND.roundsToText(rounds, unit)
	rounds = tonumber(rounds);

	if rounds == nil then
		return "";
	end;

	local v = rounds / (FSCOND.UNIT_ROUNDS[unit] or 1);

	if math.abs(v - math.floor(v + 0.5)) < 0.001 then
		return tostring(math.floor(v + 0.5));
	end;

	return (string.format("%.1f", v));
end;

-- Texto curto do selo no ícone: "3", "2m", "1h"
local function badgeText(e)
	local r = tonumber(e.r);
	local u = entryUnit(e);

	if u == "r" then
		return tostring(r);
	end;

	return tostring(math.ceil(r / FSCOND.UNIT_ROUNDS[u])) .. ((u == "min") and "m" or "h");
end;

-- Texto da duração na lista de nomes: "3 rodadas", "1,9 min", "1 h"
local function durationText(e)
	local r = tonumber(e.r);
	local u = entryUnit(e);

	if u == "r" then
		return r .. ((r == 1) and " rodada" or " rodadas");
	end;

	return (FSCOND.roundsToText(r, u):gsub("%.", ",")) .. ((u == "min") and " min" or " h");
end;

function FSCOND.getList(token)
	local ud = token.userData;

	if ud == nil then
		return {};
	end;

	return FSC.decodeList(ud[UD_FIELD]);
end;

function FSCOND.getCfg(scene)
	local cfg = {pos = "top", size = "0.4", names = "hover"};
	local ud = scene.userData;

	if ud ~= nil then
		local saved = FSC.decode(ud[CFG_FIELD]);

		for k, v in pairs(saved) do
			cfg[k] = v;
		end;
	end;

	cfg.size = tonumber(cfg.size) or 0.4;
	return cfg;
end;

function FSCOND.setCfg(scene, cfg)
	local ud = scene.userData;

	if ud ~= nil then
		ud[CFG_FIELD] = FSC.encode(cfg);
	end;
end;

local function entryName(e)
	if e.id == "custom" then
		return e.n or "?";
	end;

	local d = byId[e.id];
	return (d ~= nil and d.name) or e.id;
end;

local function entryDef(e)
	return byId[e.id] or byId["custom"];
end;

----------------------------------------------------------------------
-- Desenho no token
----------------------------------------------------------------------

local function circlePath()
	local d, bb = FSC.polysToPath({FSC.circlePoly(0, 0, 1, 32)}, true);
	return d;
end;

local CIRCLE = circlePath();

-- Caixa de um ícone mantendo o aspecto do bbox do path
local function fitBox(x, y, s, bbox)
	local bw = math.max(1, bbox[3] - bbox[1]);
	local bh = math.max(1, bbox[4] - bbox[2]);
	local w, h;

	if bw >= bh then
		w, h = s, s * bh / bw;
	else
		w, h = s * bw / bh, s;
	end;

	local left = x + (s - w) / 2;
	local top = y + (s - h) / 2;
	return {left, top, left + w, top + h};
end;

function FSCOND.render(scene, token, list, cfg)
	local canvas = token.canvas;

	if canvas == nil then
		return;
	end;

	list = list or FSCOND.getList(token);
	cfg = cfg or FSCOND.getCfg(scene);

	token:beginUpdate();

	local ok, err = pcall(function()
		FSC.removeOps(canvas, PREFIX);

		if #list == 0 then
			return;
		end;

		local cs = FSC.cellSize(scene);
		local tw = token.width / cs;
		local th = token.height / cs;
		local s = cfg.size;
		local gap = s * 0.1;
		local pos = cfg.pos;
		local horizontal = (pos == "top" or pos == "bottom");
		local span = horizontal and tw or th;
		-- pelo menos 3 ícones por linha (pode passar um pouco da largura do token)
		local perLine = math.max(3, math.floor((span + gap) / (s + gap)));
		local n = #list;
		local lines = math.ceil(n / perLine);
		local xOrigin, yOrigin = 0.5, 0;

		if pos == "bottom" then
			xOrigin, yOrigin = 0.5, 1;
		elseif pos == "right" then
			xOrigin, yOrigin = 1, 0;
		elseif pos == "left" then
			xOrigin, yOrigin = 0, 0;
		end;

		local function badgePos(i)
			local line = math.floor((i - 1) / perLine);
			local idx = (i - 1) % perLine;
			local cnt = math.min(perLine, n - line * perLine);

			if horizontal then
				local rowW = cnt * s + (cnt - 1) * gap;
				local x = -rowW / 2 + idx * (s + gap);
				local y;

				if pos == "top" then
					y = -(line + 1) * (s + gap);
				else
					y = gap + line * (s + gap);
				end;

				return x, y;
			else
				local x;

				if pos == "right" then
					x = gap + line * (s + gap);
				else
					x = -(line + 1) * (s + gap);
				end;

				return x, idx * (s + gap);
			end;
		end;

		local base = {xOrigin = xOrigin, yOrigin = yOrigin, rotMode = "ignoreCanvasRot",
		              outOfOrderMode = "afterOwnerLayer", trigger = {}};

		local function o(extra)
			local t = {};
			for k, v in pairs(base) do t[k] = v; end;
			for k, v in pairs(extra) do t[k] = v; end;
			return t;
		end;

		local publicNames = {};

		for i, e in ipairs(list) do
			local def = entryDef(e);
			local x, y = badgePos(i);
			local vis = FSC.toBool(e.h) and "gmOnly" or "everyone";
			local color = (e.id == "custom" and e.c ~= nil and e.c ~= "") and e.c or def.color;
			local z = 100 + i * 4;

			-- fundo circular
			FSC.addPathOp(canvas, PREFIX .. i .. "_bg", CIRCLE, {x, y, x + s, y + s},
				o({fill = FSC.withAlpha(color, 0.95), stroke = "#000000C0", strokeSize = 1.5, z = z, visibility = vis}));

			-- glifo
			local box = fitBox(x + s * 0.17, y + s * 0.17, s * 0.66, def.bbox);
			FSC.addPathOp(canvas, PREFIX .. i .. "_ic", def.path, box,
				o({fill = "#FFFFFF", z = z + 1, visibility = vis}));

			-- duração
			if e.r ~= nil and e.r ~= "" then
				local txt = badgeText(e);
				local ds = s * 0.5;
				-- "pílula": alarga conforme o número de caracteres
				local dw = ds + math.max(0, #txt - 1) * ds * 0.45;
				local dx, dy = x + s + ds * 0.25 - dw, y + s - ds * 0.75;
				local pill, _ = FSC.polysToPath({FSC.roundRectPoly((dw - ds) / 2, 0, ds / 2, 6)}, true);
				FSC.addPathOp(canvas, PREFIX .. i .. "_db", pill, {dx, dy, dx + dw, dy + ds},
					o({fill = "#000000E0", stroke = "#FFFFFFA0", strokeSize = 1, z = z + 2, visibility = vis}));
				FSC.addTextOp(canvas, PREFIX .. i .. "_dt", txt, dx + dw / 2, dy + ds * 0.1, ds * 0.8,
					o({color = "#FFFFFF", z = z + 3, visibility = vis}));
			end;

			if vis == "everyone" then
				local nm = entryName(e);

				if e.r ~= nil and e.r ~= "" then
					nm = nm .. " (" .. durationText(e) .. ")";
				end;

				publicNames[#publicNames + 1] = nm;
			end;
		end;

		-- nomes (texto) acima/abaixo dos ícones
		if cfg.names ~= "never" and #publicNames > 0 then
			local h = math.max(0.18, s * 0.62);
			local txt = table.concat(publicNames, " · ");
			local trigger = (cfg.names == "always") and {} or {"hover", "selected"};
			local y, tx, txo, tyo = 0, 0, 0.5, yOrigin;

			if pos == "top" then
				y = -lines * (s + gap) - h - gap;
			elseif pos == "bottom" then
				y = gap + lines * (s + gap) + gap;
			else
				-- laterais: nome acima do token
				txo, tyo = 0.5, 0;
				y = -h - gap;
			end;

			local textOpts = o({color = "#FFFFFF", z = 300, trigger = trigger, xOrigin = txo, yOrigin = tyo});
			local _, w = FSC.addTextOp(canvas, PREFIX .. "names", txt, tx, y, h, textOpts);
			local pad = h * 0.25;
			FSC.addPathOp(canvas, PREFIX .. "namesbg", "M0 0H1V1H0Z", {tx - w / 2 - pad, y - pad * 0.3, tx + w / 2 + pad, y + h + pad * 0.3},
				o({fill = "#000000B0", z = 299, trigger = trigger, xOrigin = txo, yOrigin = tyo}));
		end;
	end);

	token:endUpdate();

	if not ok then
		FSC.logError("SceneSuite.Condicoes", err);
	end;
end;

function FSCOND.setList(scene, token, list)
	local ud = token.userData;

	if ud ~= nil then
		ud[UD_FIELD] = FSC.encodeList(list);
	end;

	FSCOND.render(scene, token, list);
end;

----------------------------------------------------------------------
-- Formulário
----------------------------------------------------------------------

local forms = {};

local function getForm(scene)
	local f = forms[scene.objectID];

	if f == nil then
		f = GUI.newForm("frmFSConditions");
		forms[scene.objectID] = f;
	end;

	return f;
end;

local function tokenTitle(tokens)
	local names = {};

	for i = 1, math.min(#tokens, 4) do
		local n = tokens[i].name;

		if n == nil or n == "" then
			n = "token";
		end;

		names[#names + 1] = n;
	end;

	local t = table.concat(names, ", ");

	if #tokens > 4 then
		t = t .. " e mais " .. (#tokens - 4);
	end;

	return "Condições — " .. t;
end;

-- Mantém flags (oculto) de entradas já existentes
local function mergeResult(oldList, result)
	local oldById = {};
	local customs = {};

	for _, e in ipairs(oldList) do
		if e.id == "custom" then
			customs[#customs + 1] = e;
		else
			oldById[e.id] = e;
		end;
	end;

	local list = {};

	for _, r in ipairs(result.list) do
		local rounds = FSCOND.parseRounds(r.r, r.u);
		local old = oldById[r.id];
		local h = result.hidden and "1" or "0";

		if old ~= nil then
			h = old.h or "0";
		end;

		list[#list + 1] = {id = r.id, r = rounds and tostring(rounds) or "", u = r.u or "r", h = h};
	end;

	for _, cu in ipairs(customs) do
		list[#list + 1] = cu;
	end;

	return list;
end;

function FSCOND.openFor(scene, tokens)
	local editable = {};

	for _, t in ipairs(tokens) do
		if FSC.canEdit(scene, t) then
			editable[#editable + 1] = t;
		end;
	end;

	if #editable == 0 then
		showMessage("Você só pode alterar condições dos seus próprios tokens.");
		return;
	end;

	local first = FSCOND.getList(editable[1]);
	local current, customs = {}, {};

	for _, e in ipairs(first) do
		local hasDur = e.r ~= nil and e.r ~= "";

		if e.id == "custom" then
			customs[#customs + 1] = {n = e.n, d = hasDur and durationText(e) or nil};
		else
			current[e.id] = {r = hasDur and FSCOND.roundsToText(e.r, entryUnit(e)) or "", u = entryUnit(e)};
		end;
	end;

	local frm = getForm(scene);

	local function forEach(fn)
		for _, t in ipairs(editable) do
			if t.isObjectAlive then
				fn(t, FSCOND.getList(t));
			end;
		end;
	end;

	frm:prepareFor({
		title = tokenTitle(editable),
		close = function() scene.viewport:closeForm(frm); end,
		current = current,
		customs = customs,

		onApply = function(result)
			forEach(function(t, old)
				FSCOND.setList(scene, t, mergeResult(old, result));
			end);
		end,

		onAddCustom = function(cu, result)
			local rounds = FSCOND.parseRounds(cu.r, cu.u);

			forEach(function(t, old)
				local list = mergeResult(old, result);
				list[#list + 1] = {id = "custom", n = cu.n:gsub("[|;]", " "), r = rounds and tostring(rounds) or "", u = cu.u or "r",
				                   c = cu.c or "#00838F", h = result.hidden and "1" or "0"};
				FSCOND.setList(scene, t, list);
			end);
		end,

		onClearCustoms = function(result)
			forEach(function(t, old)
				local list = mergeResult(old, result);
				local out = {};

				for _, e in ipairs(list) do
					if e.id ~= "custom" then
						out[#out + 1] = e;
					end;
				end;

				FSCOND.setList(scene, t, out);
			end);
		end,

		onClearAll = function()
			forEach(function(t)
				FSCOND.setList(scene, t, {});
			end);
		end
	});

	FSC.showFormFit(scene.viewport, frm, 940, 640, "center", 260, 220);
end;

----------------------------------------------------------------------
-- Rodadas
----------------------------------------------------------------------

local undoSnapshots = {};

function FSCOND.advanceRound(scene)
	local snap = {};
	local changed = 0;

	for _, t in ipairs(FSC.allTokens(scene)) do
		local ud = t.userData;
		local raw = ud and ud[UD_FIELD];

		if raw ~= nil and raw ~= "" then
			local list = FSC.decodeList(raw);
			local out = {};
			local dirty = false;

			for _, e in ipairs(list) do
				local r = tonumber(e.r);

				if r ~= nil then
					r = r - 1;
					dirty = true;

					if r > 0 then
						e.r = tostring(r);
						out[#out + 1] = e;
					end;
				else
					out[#out + 1] = e;
				end;
			end;

			if dirty then
				snap[#snap + 1] = {token = t, raw = raw};
				FSCOND.setList(scene, t, out);
				changed = changed + 1;
			end;
		end;
	end;

	undoSnapshots[scene.objectID] = snap;
end;

function FSCOND.undoRound(scene)
	local snap = undoSnapshots[scene.objectID];

	if snap == nil or #snap == 0 then
		showMessage("Não há avanço de rodada para desfazer.");
		return;
	end;

	for _, s in ipairs(snap) do
		if s.token.isObjectAlive then
			FSCOND.setList(scene, s.token, FSC.decodeList(s.raw));
		end;
	end;

	undoSnapshots[scene.objectID] = nil;
end;

-- Procura uma condição pelo id, nome em português ou nome original (inglês)
function FSCOND.findDef(text)
	local q = FSC.trim(text):lower();

	if q == "" then
		return nil;
	end;

	for _, c in ipairs(FSCOND_DATA.list) do
		if c.group ~= "hidden" and (c.id == q or c.name:lower() == q or (c.en or ""):lower() == q) then
			return c;
		end;
	end;

	return nil;
end;

-- Adiciona (ou atualiza) uma condição num token; usado pelos Gatilhos.
-- Nome desconhecido vira condição personalizada.
function FSCOND.applyByName(scene, token, text, roundsTxt)
	local def = FSCOND.findDef(text);
	local rounds = FSCOND.parseRounds(roundsTxt or "", "r");
	local list = FSCOND.getList(token);
	local entry;

	if def ~= nil then
		for _, e in ipairs(list) do
			if e.id == def.id then entry = e; end;
		end;

		if entry == nil then
			entry = {id = def.id, h = "0", u = "r"};
			list[#list + 1] = entry;
		end;
	else
		entry = {id = "custom", n = FSC.trim(text):gsub("[|;]", " "), c = "#00838F", h = "0", u = "r"};
		list[#list + 1] = entry;
	end;

	entry.r = rounds and tostring(rounds) or "";
	FSCOND.setList(scene, token, list);
end;

function FSCOND.rerenderAll(scene)
	local cfg = FSCOND.getCfg(scene);

	for _, t in ipairs(FSC.allTokens(scene)) do
		local list = FSCOND.getList(t);

		if #list > 0 or FSC.hasOps(t.canvas, PREFIX) then
			FSCOND.render(scene, t, list, cfg);
		end;
	end;
end;

function FSCOND.configure(scene)
	local cfg = FSCOND.getCfg(scene);
	local posVals = {"top", "bottom", "right", "left"};
	local posNames = {"Acima do token", "Abaixo do token", "À direita", "À esquerda"};

	Dialogs.choose("Onde mostrar os ícones de condição?", posNames, function(ok, idx)
		if not ok then return; end;
		cfg.pos = posVals[idx];

		local sizes = {"0.3", "0.4", "0.5", "0.6"};
		local sizeNames = {"Pequeno (30% do quadrado)", "Médio (40%)", "Grande (50%)", "Muito grande (60%)"};

		Dialogs.choose("Tamanho dos ícones:", sizeNames, function(ok2, idx2)
			if not ok2 then return; end;
			cfg.size = sizes[idx2];

			local nVals = {"hover", "always", "never"};
			local nNames = {"Nomes ao passar o mouse / selecionar", "Nomes sempre visíveis", "Nunca mostrar nomes"};

			Dialogs.choose("Nomes das condições:", nNames, function(ok3, idx3)
				if not ok3 then return; end;
				cfg.names = nVals[idx3];
				cfg.size = tostring(cfg.size);
				FSCOND.setCfg(scene, cfg);
				FSCOND.rerenderAll(scene);
			end, 1);
		end, 2);
	end, 1);
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local lstMouseDown = nil;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Condições", 50);

	-- Integração com os Gatilhos: aplicar condição num token (id estável fsUid)
	FSC.keepAlive(scene, "fscond_apply", scene:newBroadcastListener("fscond_apply", function(sender, id, msg)
		if not scene.isGM or type(msg) ~= "table" or type(msg.uid) ~= "string" or type(msg.cond) ~= "string" then
			return;
		end;

		for _, t in ipairs(FSC.allTokens(scene)) do
			local ud = t.userData;

			if ud ~= nil and ud.fsUid == msg.uid then
				FSCOND.applyByName(scene, t, msg.cond, tostring(msg.rounds or ""));
				return;
			end;
		end;
	end));

	-- Integração com o Tracker de Combate: ao fechar cada volta, o tracker
	-- envia "fscond_advance". Só o cliente do mestre aplica, para não
	-- descontar a mesma rodada várias vezes.
	FSC.keepAlive(scene, "fscond_advance", scene:newBroadcastListener("fscond_advance", function(sender, id, msg)
		if scene.isGM then
			FSCOND.advanceRound(scene);
		end;
	end));

	local function openForSelectionOr(token)
		local sel = FSC.selectedTokens(scene);

		if token ~= nil then
			local inSel = false;

			for _, t in ipairs(sel) do
				if t == token then inSel = true; end;
			end;

			if not inSel then
				sel = {token};
			end;
		end;

		if #sel > 0 then
			FSCOND.openFor(scene, sel);
			return true;
		end;

		return false;
	end;

	viewport:addToolButton(TOOL_CATEGORY, "Condições: clique em um token (ou use os selecionados)",
		"/images/tool_cond.png", 10, {selectable = true, defaultOfCategory = true},
		function()
			-- se já há tokens selecionados, abre direto
			openForSelectionOr(nil);

			lstMouseDown = viewport:listen("onMouseDown", function(event)
				if event.button ~= "left" then
					return;
				end;

				local tk = FSC.tokenAt(scene, event.x, event.y);

				if tk ~= nil then
					openForSelectionOr(tk);
				end;
			end);
		end,
		function()
			if lstMouseDown ~= nil then
				viewport:unlisten(lstMouseDown);
				lstMouseDown = nil;
			end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Condições: avançar 1 rodada (reduz durações)",
		"/images/tool_next.png", 11, {dontFocus = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre pode avançar a rodada.");
				return;
			end;

			FSCOND.advanceRound(scene);
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Condições: desfazer último avanço de rodada",
		"/images/tool_undo.png", 12, {dontFocus = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre pode desfazer o avanço de rodada.");
				return;
			end;

			FSCOND.undoRound(scene);
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Condições: remover de todos os selecionados",
		"/images/tool_clear.png", 13, {dontFocus = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel == 0 then
				showMessage("Selecione os tokens primeiro.");
				return;
			end;

			for _, t in ipairs(sel) do
				if FSC.canEdit(scene, t) then
					FSCOND.setList(scene, t, {});
				end;
			end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Condições: configurar exibição (mestre)",
		"/images/tool_cfg.png", 14, {dontFocus = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre pode configurar a exibição.");
				return;
			end;

			FSCOND.configure(scene);
		end);
end);
