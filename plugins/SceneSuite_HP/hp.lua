--[[
  Scene Suite - PV Rápido (inspirado no módulo "Always HP" do Foundry)

  Painel compacto para aplicar dano/cura nos tokens selecionados, usando as
  barras do próprio token do Firecast (barValue/barMax 1, 2 ou 3).
   - Dano, Dano ½ (resistência / Strong do FFd20), Dano ×1,5 (fraqueza)
   - Cura (não passa do máximo), PV temporário (absorve dano primeiro),
     Definir valor
   - Desfazer a última aplicação
   - Números flutuantes no token (aparecem para quem tem o plugin)

  PV temporário: token.userData.fsTempHP, mostrado como "+N" junto ao token.
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
local TOOL_CATEGORY = "SSuite_HP";
local TEMP_FIELD = "fsTempHP";
local TEMP_PREFIX = "fshp_temp";
local FLOAT_MESSAGE = "fshp_float";
local FLOAT_DURATION = 1.6;

FSHP = FSHP or {};
local FSHP = FSHP;

local function now()
	return system.getTickCount() / 1000;
end;

local function getBar(token, bar)
	return tonumber(token["barValue" .. bar]), tonumber(token["barMax" .. bar]);
end;

local function fmt(n)
	if n == nil then
		return "?";
	end;

	if n == math.floor(n) then
		return tostring(math.floor(n));
	end;

	return (string.format("%.1f", n):gsub("%.", ","));
end;

function FSHP.getTemp(token)
	local ud = token.userData;
	return (ud and tonumber(ud[TEMP_FIELD])) or 0;
end;

-- Mostra "+N" (PV temporário) acima do token; some quando zera
function FSHP.renderTemp(token, temp)
	FSC.removeOps(token.canvas, TEMP_PREFIX);

	if temp ~= nil and temp > 0 then
		local h = 0.3;
		local _, w = FSC.addTextOp(token.canvas, TEMP_PREFIX .. "_t", "+" .. fmt(temp), 0, -h - 0.04, h,
			{xOrigin = 1, yOrigin = 0, color = "#82B1FF", z = 90, outOfOrderMode = "afterOwnerLayer", align = "trailing"});
		FSC.addPathOp(token.canvas, TEMP_PREFIX .. "_bg", "M0 0H1V1H0Z", {-w - 0.06, -h - 0.06, 0.06, -0.02},
			{xOrigin = 1, yOrigin = 0, fill = "#000000B0", z = 89, outOfOrderMode = "afterOwnerLayer"});
	end;
end;

local function setTemp(token, temp)
	local ud = token.userData;

	if ud ~= nil then
		ud[TEMP_FIELD] = (temp > 0) and tostring(temp) or "";
	end;

	FSHP.renderTemp(token, temp);
end;

--[[ Aplica uma operação num token. Retorna {delta, label} para o número
  flutuante, ou nil se o token não tem barra configurada. ]]
function FSHP.applyToToken(token, op, amount, bar)
	local value, maxV = getBar(token, bar);

	if value == nil and op ~= "set" then
		return nil;
	end;

	local temp = FSHP.getTemp(token);
	local newValue, newTemp = value, temp;
	local shown;

	if op == "damage" or op == "half" or op == "weak" then
		local dmg = amount;

		if op == "half" then
			dmg = math.max(1, math.floor(amount / 2));   -- PF/FFd20: metade, mínimo 1
		elseif op == "weak" then
			dmg = math.floor(amount * 1.5);
		end;

		-- PV temporário absorve primeiro
		local absorbed = math.min(temp, dmg);
		newTemp = temp - absorbed;
		newValue = value - (dmg - absorbed);
		shown = {text = "-" .. fmt(dmg), color = "#FF5252"};
	elseif op == "heal" then
		newValue = value + amount;

		if maxV ~= nil then
			newValue = math.min(newValue, math.max(maxV, value));
		end;

		shown = {text = "+" .. fmt(newValue - value), color = "#69F0AE"};
	elseif op == "temp" then
		-- PV temporários não se acumulam: fica o maior
		newTemp = math.max(temp, amount);
		shown = {text = "+" .. fmt(newTemp) .. " temp", color = "#82B1FF"};
	elseif op == "set" then
		newValue = amount;
		shown = {text = "= " .. fmt(amount), color = "#FFFFFF"};
	end;

	local undo = {token = token, bar = bar, value = token["barValue" .. bar], temp = temp};

	if newValue ~= value then
		token["barValue" .. bar] = fmt(newValue):gsub(",", ".");
	end;

	if newTemp ~= temp then
		setTemp(token, newTemp);
	end;

	return shown, undo;
end;

function FSHP.describe(tokens, bar)
	if #tokens == 0 then
		return "Selecione tokens no tabuleiro.";
	end;

	local parts = {};

	for i = 1, math.min(#tokens, 4) do
		local t = tokens[i];
		local v, m = getBar(t, bar);
		local name = (t.name ~= nil and t.name ~= "") and t.name or "token";
		local txt = name .. ": " .. fmt(v) .. ((m ~= nil) and ("/" .. fmt(m)) or "");
		local temp = FSHP.getTemp(t);

		if temp > 0 then
			txt = txt .. " (+" .. fmt(temp) .. ")";
		end;

		if v == nil then
			txt = name .. ": sem barra " .. bar;
		end;

		parts[#parts + 1] = txt;
	end;

	local s = table.concat(parts, " · ");

	if #tokens > 4 then
		s = s .. " e mais " .. (#tokens - 4);
	end;

	return s;
end;

----------------------------------------------------------------------
-- Números flutuantes (desenho local, sincronizado por mensagem)
----------------------------------------------------------------------

local function newFloater(scene)
	local fl = {list = {}, listener = nil, interval = nil};
	local viewport = scene.viewport;

	local function stop()
		if fl.listener ~= nil then
			viewport:unlisten(fl.listener);
			fl.listener = nil;
		end;

		if fl.interval ~= nil then
			clearInterval(fl.interval);
			fl.interval = nil;
		end;

		viewport:needRepaint();
	end;

	local function draw()
		local t = now();
		local keep = {};
		local cs = FSC.cellSize(scene);

		for _, f in ipairs(fl.list) do
			local p = (t - f.t0) / FLOAT_DURATION;

			if p <= 1 then
				keep[#keep + 1] = f;
				local sx, sy = viewport:worldToScreen(f.x, f.y - cs * 0.6 * p);
				local size = math.max(12, math.min(28, cs * viewport.scale * 0.35));
				local a = (p < 0.7) and 1 or (1 - (p - 0.7) / 0.3);
				viewport:prepareFont(size, nil, true);
				local w, h = viewport:textSize(f.text);
				viewport:prepareFill("#000000");
				viewport:fillText(sx - w / 2 + 1.5, sy - h / 2 + 1.5, f.text, a * 0.8);
				viewport:prepareFill(f.color);
				viewport:fillText(sx - w / 2, sy - h / 2, f.text, a);
			end;
		end;

		fl.list = keep;

		if #keep == 0 then
			setTimeout(function()
				if #fl.list == 0 then stop(); end;
			end, 1);
		end;
	end;

	function fl:add(x, y, text, color)
		self.list[#self.list + 1] = {x = x, y = y, text = text, color = color, t0 = now()};

		if self.listener == nil then
			self.listener = viewport:listen("onAfterDrawLayers", draw);
		end;

		if self.interval == nil then
			self.interval = setInterval(function()
				if scene.isObjectAlive then viewport:needRepaint(); end;
			end, 30);
		end;
	end;

	fl.broadcastListener = scene:newBroadcastListener(FLOAT_MESSAGE, function(sender, id, msg)
		if type(msg) == "table" and type(msg.x) == "number" and type(msg.y) == "number" and type(msg.text) == "string" then
			fl:add(msg.x, msg.y, msg.text, type(msg.color) == "string" and msg.color or "#FFFFFF");
		end;
	end);

	return fl;
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local frm = nil;
	local open = false;
	local prefs = {bar = "1", float = true};
	local lastUndo = nil;
	local floater = newFloater(scene);

	FSC.setupCategory(viewport, TOOL_CATEGORY, "PV rápido", 49);

	local function editableSelection()
		local out = {};

		for _, t in ipairs(FSC.selectedTokens(scene)) do
			if FSC.canEdit(scene, t) then
				out[#out + 1] = t;
			end;
		end;

		return out;
	end;

	local function refresh()
		if open and frm ~= nil then
			frm:refresh();
		end;
	end;

	-- atualiza o painel quando a seleção muda
	scene.items:listen("onItemSelected", function() refresh(); end);
	scene.items:listen("onItemDeselected", function() refresh(); end);

	local function close()
		open = false;

		if frm ~= nil then
			viewport:closeForm(frm);
		end;
	end;

	local function openPanel()
		if frm == nil then
			frm = GUI.newForm("frmFSHP");
		end;

		frm:prepareFor({
			bar = prefs.bar,
			float = prefs.float,

			describe = function(bar)
				return FSHP.describe(editableSelection(), bar);
			end,

			onBarChange = function(bar)
				prefs.bar = bar;
			end,

			onOp = function(op, amount, bar, float)
				prefs.bar, prefs.float = bar, float;
				local tokens = editableSelection();

				if #tokens == 0 then
					showMessage("Selecione os tokens (seus, ou qualquer um se for o mestre).");
					return;
				end;

				local undo = {};

				for _, t in ipairs(tokens) do
					local shown, u = FSHP.applyToToken(t, op, amount, bar);

					if u ~= nil then
						undo[#undo + 1] = u;
					end;

					if shown ~= nil and float and t.visible ~= false then
						local x, y = t:getCenter(false);
						scene:broadcastMessage(FLOAT_MESSAGE, {x = x, y = y - t.height * 0.3, text = shown.text,
						                                       color = shown.color}, true);
					end;
				end;

				lastUndo = undo;
			end,

			onUndo = function()
				if lastUndo == nil then
					showMessage("Nada para desfazer.");
					return;
				end;

				for _, u in ipairs(lastUndo) do
					if u.token.isObjectAlive then
						u.token["barValue" .. u.bar] = u.value;
						setTemp(u.token, u.temp);
					end;
				end;

				lastUndo = nil;
			end,

			onClose = close
		});

		open = true;
		FSC.showFormFit(viewport, frm, 300, 236, "topRight", 200, 150);
	end;

	viewport:addToolButton(TOOL_CATEGORY, "PV rápido: abrir/fechar o painel",
		"/images/tool_hp.png", 10, {defaultOfCategory = true},
		function()
			if FSC.isSpectator(scene) then
				return;
			end;

			if open then
				close();
			else
				openPanel();
			end;
		end);
end);
