--[[
  Scene Suite - Alcance (reach)
  Mostra os quadrados que uma criatura ameaça em corpo a corpo:
   - alcance natural digitado (ft, m ou quadrados);
   - arma de haste: dobra o alcance e deixa de ameaçar os quadrados até o
     alcance natural (opcionalmente continua ameaçando adjacentes);
   - exceção de 10 ft: alcança 2 quadrados na diagonal.

  Para não poluir o tabuleiro, o alcance é desenhado bem translúcido, com
  contorno tracejado, e por padrão só aparece ao passar o mouse ou selecionar
  o token. O mestre pode trocar para "sempre" ou "ocultar todos".

  Dados: token.userData.fsReach (registro), scene.userData.fsReachView
  Desenho: canvas do token, prefixo "fsreach_"
]]

require("scene.lua");
require("firecast.lua");
require("log.lua");
require("utils.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local PREFIX = "fsreach_";
local UD_FIELD = "fsReach";
local SIG_FIELD = "fsReachSig";
local VIEW_FIELD = "fsReachView";
local TOOL_CATEGORY = "SSuite_Reach";

FSREACH = FSREACH or {};
local FSREACH = FSREACH;

function FSREACH.getRecord(token)
	local ud = token.userData;

	if ud == nil or ud[UD_FIELD] == nil or ud[UD_FIELD] == "" then
		return nil;
	end;

	return FSC.decode(ud[UD_FIELD]);
end;

function FSREACH.getView(scene)
	local ud = scene.userData;
	local v = ud and ud[VIEW_FIELD];

	if v ~= "always" and v ~= "hidden" then
		v = "hover";
	end;

	return v;
end;

-- Calcula alcance mínimo e máximo (em quadrados) e um texto explicativo
function FSREACH.compute(scene, token, r)
	local fps = FSC.feetPerSquare(scene);
	local _, naturalFt = FSC.parseDistance(r.natural, scene, "ft");

	if naturalFt == nil then
		return nil, "Alcance inválido.";
	end;

	local maxFt, minFt = naturalFt, 0;

	if r.weapon == "1" then
		maxFt = naturalFt * 2;

		if r.adjacent ~= "1" then
			minFt = naturalFt;
		end;
	end;

	local txt;

	if r.weapon == "1" then
		txt = "Natural " .. FSC.fmtNum(naturalFt) .. " ft; com arma de haste ameaça até " .. FSC.formatFeet(maxFt);

		if minFt > 0 then
			txt = txt .. ", mas não até " .. FSC.fmtNum(minFt) .. " ft";
		end;
	else
		txt = "Ameaça até " .. FSC.formatFeet(maxFt);
	end;

	if maxFt <= 0 then
		txt = "Alcance 0 ft: a criatura só ameaça o próprio quadrado (nada a desenhar).";
	end;

	return {maxSq = maxFt / fps, minSq = minFt / fps, maxFt = maxFt}, txt;
end;

function FSREACH.renderToken(scene, token, r, view)
	r = r or FSREACH.getRecord(token);
	view = view or FSREACH.getView(scene);

	if r == nil or view == "hidden" then
		FSC.removeOps(token.canvas, PREFIX);
		return;
	end;

	local c = FSREACH.compute(scene, token, r);

	if c == nil or c.maxFt <= 0 then
		FSC.removeOps(token.canvas, PREFIX);
		return;
	end;

	local color = r.color or "#E53935";

	local spec = {
		shape = "emanation",
		maxSq = c.maxSq,
		minSq = c.minSq,
		mode = "grid",
		diag = FSC.diagMode(scene, r.diag),
		reach10 = r.diag10 ~= "0"
	};

	-- Bem translúcido e tracejado: visível, mas sem poluir
	local style = {
		color = color,
		fillAlpha = (view == "always") and 0.06 or 0.10,
		lineAlpha = (view == "always") and 0.45 or 0.7,
		lineWidth = 1.5,
		lineDash = "dash",
		trigger = (view == "always") and {} or {"hover", "selected"},
		z = -60
	};

	token:beginUpdate();
	pcall(FSC.renderTokenArea, scene, token, PREFIX, spec, style);
	token:endUpdate();

	local ud = token.userData;

	if ud ~= nil then
		ud[SIG_FIELD] = FSC.tokenSignature(scene, token, false);
	end;
end;

function FSREACH.setRecord(scene, token, r)
	local ud = token.userData;

	if ud ~= nil then
		ud[UD_FIELD] = (r ~= nil) and FSC.encode(r) or "";
	end;

	FSREACH.renderToken(scene, token, r);
end;

function FSREACH.rerenderAll(scene)
	local view = FSREACH.getView(scene);

	for _, t in ipairs(FSC.allTokens(scene)) do
		local r = FSREACH.getRecord(t);

		if r ~= nil or FSC.hasOps(t.canvas, PREFIX) then
			FSREACH.renderToken(scene, t, r, view);
		end;
	end;
end;

local DEFAULT_RECORD = {natural = "5 ft", weapon = "0", adjacent = "0",
                        diag10 = "1", color = "#E53935", diag = "pf"};

----------------------------------------------------------------------
-- Formulário
----------------------------------------------------------------------

local forms = {};

function FSREACH.openFor(scene, tokens)
	local editable = {};

	for _, t in ipairs(tokens) do
		if FSC.canEdit(scene, t) then
			editable[#editable + 1] = t;
		end;
	end;

	if #editable == 0 then
		showMessage("Você só pode configurar o alcance dos seus próprios tokens.");
		return;
	end;

	local frm = forms[scene.objectID];

	if frm == nil then
		frm = GUI.newForm("frmFSReach");
		forms[scene.objectID] = frm;
	end;

	local first = editable[1];
	local title = "Alcance — " .. ((first.name ~= "" and first.name) or "token");

	if #editable > 1 then
		title = title .. " e mais " .. (#editable - 1);
	end;

	frm:prepareFor({
		title = title,
		record = FSREACH.getRecord(first) or DEFAULT_RECORD,
		close = function() scene.viewport:closeForm(frm); end,

		describe = function(r)
			local _, txt = FSREACH.compute(scene, first, r);
			local view = FSREACH.getView(scene);

			if view == "hover" then
				txt = txt .. "\n(aparece ao passar o mouse ou selecionar o token)";
			elseif view == "hidden" then
				txt = txt .. "\n(o mestre ocultou os alcances nesta mesa)";
			end;

			return txt;
		end,

		onApply = function(r)
			if FSREACH.compute(scene, first, r) == nil then
				showMessage("Alcance inválido: use algo como 10 ft, 3 m ou 2 q.");
				return;
			end;

			for _, t in ipairs(editable) do
				if t.isObjectAlive then
					FSREACH.setRecord(scene, t, r);
				end;
			end;
		end,

		onRemove = function()
			for _, t in ipairs(editable) do
				if t.isObjectAlive then
					FSREACH.setRecord(scene, t, nil);
				end;
			end;
		end
	});

	FSC.showFormFit(scene.viewport, frm, 430, 390, "center");
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local lstMouseDown = nil;

	FSC.setupCategory(viewport, TOOL_CATEGORY, "Alcance", 52);

	viewport:addToolButton(TOOL_CATEGORY, "Alcance: clique em um token (ou use os selecionados)",
		"/images/tool_reach.png", 30, {selectable = true, defaultOfCategory = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel > 0 then
				FSREACH.openFor(scene, sel);
			end;

			lstMouseDown = viewport:listen("onMouseDown", function(event)
				if event.button ~= "left" then
					return;
				end;

				local tk = FSC.tokenAt(scene, event.x, event.y);

				if tk ~= nil then
					local s = FSC.selectedTokens(scene);
					local inSel = false;

					for _, t in ipairs(s) do
						if t == tk then inSel = true; end;
					end;

					FSREACH.openFor(scene, inSel and s or {tk});
				end;
			end);
		end,
		function()
			if lstMouseDown ~= nil then
				viewport:unlisten(lstMouseDown);
				lstMouseDown = nil;
			end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Alcance: modo de exibição na mesa (mestre)",
		"/images/tool_view.png", 32, {dontFocus = true},
		function()
			if not scene.isGM then
				showMessage("Apenas o mestre pode mudar a exibição dos alcances.");
				return;
			end;

			local vals = {"hover", "always", "hidden"};
			local names = {"Ao passar o mouse / selecionar (recomendado)", "Sempre visível (bem translúcido)", "Ocultar todos"};
			local cur = FSREACH.getView(scene);
			local def = 1;

			for i, v in ipairs(vals) do
				if v == cur then def = i; end;
			end;

			Dialogs.choose("Como mostrar os alcances?", names, function(ok, idx)
				if ok then
					local ud = scene.userData;

					if ud ~= nil then
						ud[VIEW_FIELD] = vals[idx];
					end;

					FSREACH.rerenderAll(scene);
				end;
			end, def);
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Alcance: remover dos selecionados",
		"/images/tool_clear.png", 33, {dontFocus = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel == 0 then
				showMessage("Selecione os tokens primeiro.");
				return;
			end;

			for _, t in ipairs(sel) do
				if FSC.canEdit(scene, t) then
					FSREACH.setRecord(scene, t, nil);
				end;
			end;
		end);

	-- Redesenha quando o token muda de tamanho ou sai do grid
	FSC.watchTokenBounds(scene, "fsreach", function(token)
		if not scene.isGM then
			return;
		end;

		local r = FSREACH.getRecord(token);

		if r == nil then
			return;
		end;

		local ud = token.userData;

		if ud ~= nil and ud[SIG_FIELD] ~= FSC.tokenSignature(scene, token, false) then
			FSREACH.renderToken(scene, token, r);
		end;
	end);
end);
