--[[
  Scene Suite - Luz e Visão (inspirado no módulo "Torch" do Foundry)

  O token do Firecast já tem alcance de luz (intensa/fraca, ângulo) e de
  visão (luz intensa / luz fraca / escuridão), mas em "métrica de mundo".
  Este plugin aplica presets de Pathfinder 1e em pés, convertendo pela
  configuração do tabuleiro (padrão: 1 quadrado = 1,5 m = 5 ft).

  Luz: o primeiro número é o raio de luz normal; o segundo, o raio total
  da penumbra (ex.: tocha 20/40 = luz normal até 20 ft, penumbra até 40 ft).

  A visão só tem efeito com a névoa de guerra (fog of war) ligada.

  Botão rápido "acender/apagar": desliga a luz dos tokens selecionados e
  lembra o valor; apertando de novo, acende com a última luz (ou uma tocha).
]]

require("scene.lua");
require("firecast.lua");
require("log.lua");
require("utils.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local TOOL_CATEGORY = "SSuite_Light";
local MEM_FIELD = "fsLightMem";    -- última luz acesa (para o botão rápido)
local REC_FIELD = "fsLightRec";    -- últimas escolhas do formulário

FSLIGHT = FSLIGHT or {};
local FSLIGHT = FSLIGHT;

-- Fontes de luz de PF1e: {id, nome, luz normal (ft), penumbra total (ft), ângulo}
FSLIGHT.LIGHTS = {
	{"keep", "(não alterar)"},
	{"none", "Apagada", 0, 0, 360},
	{"candle", "Vela (penumbra 5 ft)", 0, 5, 360},
	{"torch", "Tocha (20 / 40 ft)", 20, 40, 360},
	{"lamp", "Lamparina (15 / 30 ft)", 15, 30, 360},
	{"lantern", "Lanterna coberta (30 / 60 ft)", 30, 60, 360},
	{"bullseye", "Lanterna furta-fogo (cone 60 / 120 ft)", 60, 120, 90},
	{"sunrod", "Bastão solar (30 / 60 ft)", 30, 60, 360},
	{"light", "Magia Luz (20 / 40 ft)", 20, 40, 360},
	{"continual", "Chama Contínua (20 / 40 ft)", 20, 40, 360},
	{"daylight", "Luz do Dia (60 / 120 ft)", 60, 120, 360},
	{"custom", "Personalizada"}
};

-- Visão: {id, nome, alcance no escuro (ft) | nil = não muda}
FSLIGHT.VISIONS = {
	{"keep", "(não alterar)"},
	{"normal", "Normal (sem visão no escuro)", 0},
	{"lowlight", "Visão na penumbra", 0},
	{"dark30", "Visão no escuro 30 ft", 30},
	{"dark60", "Visão no escuro 60 ft", 60},
	{"dark90", "Visão no escuro 90 ft", 90},
	{"dark120", "Visão no escuro 120 ft", 120},
	{"blind", "Sem visão (cego)", 0},
	{"custom", "Personalizada"}
};

-- "alcance ilimitado" para luz intensa/fraca (bem maior que qualquer mapa)
local FAR_FT = 2000;

local function find(list, id)
	for _, e in ipairs(list) do
		if e[1] == id then return e; end;
	end;

	return nil;
end;

local function ftToWorld(scene, ft)
	return ft / FSC.feetPerSquare(scene) * FSC.cellSize(scene);
end;

local function worldToFt(scene, w)
	return (tonumber(w) or 0) / FSC.cellSize(scene) * FSC.feetPerSquare(scene);
end;

local function parseFt(scene, txt)
	local _, ft = FSC.parseDistance(txt, scene, "ft");
	return ft;
end;

-- Resolve um registro do formulário em valores (pés). Retorna light, vision
-- (tabelas) ou nil, mensagem de erro.
function FSLIGHT.resolve(scene, r)
	local light, vision = nil, nil;

	if r.light == "custom" then
		local b, d = parseFt(scene, r.bright), parseFt(scene, r.dim);

		if b == nil or d == nil then
			return nil, nil, "Luz personalizada inválida (use 20 ft, 6 m...).";
		end;

		light = {bright = b, dim = math.max(b, d), angle = tonumber(r.angle) or 360};
	elseif r.light ~= "keep" then
		local e = find(FSLIGHT.LIGHTS, r.light);

		if e ~= nil then
			light = {bright = e[3], dim = e[4], angle = e[5]};
		end;
	end;

	if r.vision == "custom" then
		local d = parseFt(scene, r.dark);

		if d == nil then
			return nil, nil, "Visão personalizada inválida.";
		end;

		vision = {dark = d, have = true};
	elseif r.vision == "blind" then
		vision = {dark = 0, have = false};
	elseif r.vision ~= "keep" then
		local e = find(FSLIGHT.VISIONS, r.vision);

		if e ~= nil then
			vision = {dark = e[3], have = true};
		end;
	end;

	return light, vision;
end;

function FSLIGHT.applyLight(scene, token, light)
	token.lightIntenseRange = ftToWorld(scene, light.bright);
	token.lightWeakRange = ftToWorld(scene, light.dim);
	token.lightAngle = light.angle or 360;

	if light.dim > 0 then
		local ud = token.userData;

		if ud ~= nil then
			ud[MEM_FIELD] = FSC.encode({b = light.bright, d = light.dim, a = light.angle or 360});
		end;
	end;
end;

function FSLIGHT.applyVision(scene, token, vision)
	token.visionHaveVision = vision.have;
	token.visionIntenseLightRange = ftToWorld(scene, FAR_FT);
	token.visionWeakLightRange = ftToWorld(scene, FAR_FT);
	token.visionDarknessRange = ftToWorld(scene, vision.dark);
end;

function FSLIGHT.describeToken(scene, token)
	local b = worldToFt(scene, token.lightIntenseRange);
	local d = worldToFt(scene, token.lightWeakRange);
	local dark = worldToFt(scene, token.visionDarknessRange);
	local txt;

	if d <= 0 and b <= 0 then
		txt = "Atual: sem luz";
	else
		txt = "Atual: luz " .. FSC.fmtNum(b) .. " / " .. FSC.fmtNum(d) .. " ft";

		if (tonumber(token.lightAngle) or 360) < 360 then
			txt = txt .. " (cone " .. FSC.fmtNum(token.lightAngle) .. "°)";
		end;
	end;

	if token.visionHaveVision then
		txt = txt .. "; visão no escuro " .. FSC.fmtNum(dark) .. " ft";
	else
		txt = txt .. "; sem visão configurada";
	end;

	return txt;
end;

-- Botão rápido: apaga se acesa; acende com a última luz (ou tocha)
function FSLIGHT.toggle(scene, token)
	local on = (tonumber(token.lightWeakRange) or 0) > 0 or (tonumber(token.lightIntenseRange) or 0) > 0;

	if on then
		local ud = token.userData;

		if ud ~= nil then
			ud[MEM_FIELD] = FSC.encode({b = FSC.fmtNum(worldToFt(scene, token.lightIntenseRange)):gsub(",", "."),
			                            d = FSC.fmtNum(worldToFt(scene, token.lightWeakRange)):gsub(",", "."),
			                            a = tostring(token.lightAngle or 360)});
		end;

		token.lightIntenseRange = 0;
		token.lightWeakRange = 0;
		return false;
	end;

	local mem = FSC.decode(token.userData and token.userData[MEM_FIELD]);
	local b, d, a = tonumber(mem.b), tonumber(mem.d), tonumber(mem.a);

	if d == nil or d <= 0 then
		b, d, a = 20, 40, 360;  -- tocha
	end;

	FSLIGHT.applyLight(scene, token, {bright = b or 0, dim = d, angle = a or 360});
	return true;
end;

----------------------------------------------------------------------
-- Formulário
----------------------------------------------------------------------

local forms = {};

local function columns(list)
	local items, values = {}, {};

	for _, e in ipairs(list) do
		items[#items + 1] = e[2];
		values[#values + 1] = e[1];
	end;

	return items, values;
end;

function FSLIGHT.openFor(scene, tokens)
	local editable = {};

	for _, t in ipairs(tokens) do
		if FSC.canEdit(scene, t) then
			editable[#editable + 1] = t;
		end;
	end;

	if #editable == 0 then
		showMessage("Você só pode mudar luz e visão dos seus próprios tokens.");
		return;
	end;

	local frm = forms[scene.objectID];

	if frm == nil then
		frm = GUI.newForm("frmFSLight");
		forms[scene.objectID] = frm;
	end;

	local first = editable[1];
	local li, lv = columns(FSLIGHT.LIGHTS);
	local vi, vv = columns(FSLIGHT.VISIONS);
	local title = "Luz e visão — " .. ((first.name ~= "" and first.name) or "token");

	if #editable > 1 then
		title = title .. " e mais " .. (#editable - 1);
	end;

	local rec = FSC.decode(first.userData and first.userData[REC_FIELD]);
	rec.light = "keep";
	rec.vision = "keep";

	frm:prepareFor({
		title = title,
		lightItems = li, lightValues = lv, visionItems = vi, visionValues = vv,
		record = rec,
		close = function() scene.viewport:closeForm(frm); end,

		describe = function(r)
			local light, vision, err = FSLIGHT.resolve(scene, r);

			if err ~= nil then
				return err;
			end;

			local parts = {FSLIGHT.describeToken(scene, first)};

			if light ~= nil then
				parts[#parts + 1] = "Nova luz: " .. FSC.fmtNum(light.bright) .. " ft normal, penumbra até " ..
				                    FSC.fmtNum(light.dim) .. " ft" .. ((light.angle < 360) and (", cone " .. light.angle .. "°") or "");
			end;

			if vision ~= nil then
				parts[#parts + 1] = vision.have and ("Nova visão: no escuro " .. FSC.fmtNum(vision.dark) .. " ft")
				                    or "Nova visão: nenhuma";
			end;

			parts[#parts + 1] = "(A visão só vale com a névoa de guerra ligada.)";
			return table.concat(parts, "\n");
		end,

		onApply = function(r)
			local light, vision, err = FSLIGHT.resolve(scene, r);

			if err ~= nil then
				showMessage(err);
				return;
			end;

			for _, t in ipairs(editable) do
				if t.isObjectAlive then
					t:beginUpdate();

					if light ~= nil then FSLIGHT.applyLight(scene, t, light); end;
					if vision ~= nil then FSLIGHT.applyVision(scene, t, vision); end;

					t:endUpdate();
					local ud = t.userData;

					if ud ~= nil then
						ud[REC_FIELD] = FSC.encode({bright = r.bright, dim = r.dim, angle = r.angle, dark = r.dark});
					end;
				end;
			end;
		end
	});

	FSC.showFormFit(scene.viewport, frm, 340, 360, "center");
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local lstMouseDown = nil;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Luz e Visão", 47);

	viewport:addToolButton(TOOL_CATEGORY, "Luz e visão: clique em um token (ou use os selecionados)",
		"/images/tool_light.png", 10, {selectable = true, defaultOfCategory = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel > 0 then
				FSLIGHT.openFor(scene, sel);
			end;

			lstMouseDown = viewport:listen("onMouseDown", function(event)
				if event.button ~= "left" then return; end;
				local tk = FSC.tokenAt(scene, event.x, event.y);

				if tk ~= nil then
					local s = FSC.selectedTokens(scene);
					local inSel = false;

					for _, t in ipairs(s) do
						if t == tk then inSel = true; end;
					end;

					FSLIGHT.openFor(scene, inSel and s or {tk});
				end;
			end);
		end,
		function()
			if lstMouseDown ~= nil then
				viewport:unlisten(lstMouseDown);
				lstMouseDown = nil;
			end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Luz: acender/apagar nos selecionados",
		"/images/tool_torch.png", 11, {dontFocus = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel == 0 then
				showMessage("Selecione os tokens primeiro.");
				return;
			end;

			for _, t in ipairs(sel) do
				if FSC.canEdit(scene, t) then
					FSLIGHT.toggle(scene, t);
				end;
			end;
		end);
end);
