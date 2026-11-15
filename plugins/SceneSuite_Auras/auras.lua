--[[
  Scene Suite - Auras
  Até 3 auras por token: emanação, quadrado, cone ou linha, com tamanho em
  ft/m/quadrados. No modo "quadrados" a aura marca exatamente as células
  afetadas pela regra de diagonais do Pathfinder (5-10-5), medida a partir
  da borda do token (como emanações de PF).

  Dados: token.userData.fsAuras (lista codificada, 1 registro por slot)
  Desenho: operações no canvas do token com prefixo "fsaura<slot>_"
]]

require("scene.lua");
require("firecast.lua");
require("utils.lua");
require("gui.lua");
require("dialogs.lua");
require("fsCommon.lua");

local FSC = FSC;
local UD_FIELD = "fsAuras";
local SIG_FIELD = "fsAurasSig";
local TOOL_CATEGORY = "SceneSuite";
local MAX_SLOTS = 3;

FSAURA = FSAURA or {};
local FSAURA = FSAURA;

local SHAPE_NAMES = {emanation = "emanação", square = "quadrado", cone = "cone", line = "linha"};

function FSAURA.getSlots(token)
	local ud = token.userData;
	local list = (ud ~= nil) and FSC.decodeList(ud[UD_FIELD]) or {};
	local slots = {};

	for i = 1, MAX_SLOTS do
		local r = list[i];

		if r ~= nil and r.shape ~= nil and r.shape ~= "" then
			slots[i] = r;
		else
			slots[i] = {on = "0", shape = ""};
		end;
	end;

	return slots;
end;

local function saveSlots(token, slots)
	local ud = token.userData;

	if ud ~= nil then
		ud[UD_FIELD] = FSC.encodeList(slots);
	end;
end;

local function hasAnyAura(slots)
	for i = 1, MAX_SLOTS do
		if slots[i].shape ~= "" and slots[i].on ~= "0" then
			return true;
		end;
	end;

	return false;
end;

-- Converte um registro do formulário em spec/style para FSC.renderTokenArea
local function toSpec(scene, r)
	local sq, feet = FSC.parseDistance(r.radius, scene, "ft");

	if sq == nil or sq <= 0 then
		return nil, "Alcance inválido: use algo como 10 ft, 3 m ou 2 q.";
	end;

	local wsq = FSC.parseDistance(r.width ~= "" and r.width or "5 ft", scene, "ft") or 1;

	local spec = {
		shape = r.shape,
		maxSq = sq,
		widthSq = math.max(1, wsq),
		angle = tonumber(r.dir) or 0,
		followFacing = r.follow == "1",
		mode = r.mode or "grid",
		diag = FSC.diagMode(scene, r.diag)
	};

	return spec, feet;
end;

local function toStyle(r, slot)
	local fill = tonumber(r.fill) or 0.15;
	local label = r.name;

	if label == nil or label == "" then
		label = nil;
	end;

	return {
		color = r.color or "#7E57C2",
		fillAlpha = fill,
		lineAlpha = 0.85,
		lineWidth = 2,
		visibility = (r.gm == "1") and "gmOnly" or "everyone",
		trigger = (r.show == "hover") and {"hover", "selected"} or {},
		z = -20 - slot * 3,
		label = label
	};
end;

function FSAURA.renderToken(scene, token, slots)
	slots = slots or FSAURA.getSlots(token);
	local errors = {};

	token:beginUpdate();

	for i = 1, MAX_SLOTS do
		local prefix = "fsaura" .. i .. "_";
		local r = slots[i];

		if r.shape == "" or r.on == "0" then
			FSC.removeOps(token.canvas, prefix);
		else
			local spec, err = toSpec(scene, r);

			if spec == nil then
				FSC.removeOps(token.canvas, prefix);
				errors[#errors + 1] = err;
			else
				local ok, e = pcall(FSC.renderTokenArea, scene, token, prefix, spec, toStyle(r, i));

				if not ok then
					errors[#errors + 1] = tostring(e);
				end;
			end;
		end;
	end;

	token:endUpdate();

	local ud = token.userData;

	if ud ~= nil then
		ud[SIG_FIELD] = FSC.tokenSignature(scene, token, true);
	end;

	return errors;
end;

function FSAURA.describe(scene, r)
	local sq, feet = FSC.parseDistance(r.radius, scene, "ft");

	if sq == nil then
		return "Alcance inválido.";
	end;

	local txt = (SHAPE_NAMES[r.shape] or r.shape) .. " de " .. FSC.formatFeet(feet) ..
	            " = " .. FSC.fmtNum(sq) .. " quadrado(s)";

	if r.mode == "grid" and math.abs(sq - math.floor(sq + 0.5)) > 0.01 then
		txt = txt .. " (arredondado para baixo no grid)";
	end;

	if r.mode == "grid" and not FSC.isSquareGrid(scene) then
		txt = txt .. " - grid hexagonal: usando forma suave";
	end;

	return txt;
end;

----------------------------------------------------------------------
-- Formulário
----------------------------------------------------------------------

local forms = {};

function FSAURA.openFor(scene, tokens)
	local editable = {};

	for _, t in ipairs(tokens) do
		if FSC.canEdit(scene, t) then
			editable[#editable + 1] = t;
		end;
	end;

	if #editable == 0 then
		showMessage("Você só pode colocar auras nos seus próprios tokens.");
		return;
	end;

	local frm = forms[scene.objectID];

	if frm == nil then
		frm = GUI.newForm("frmFSAura");
		forms[scene.objectID] = frm;
	end;

	local title = "Auras — " .. ((editable[1].name ~= "" and editable[1].name) or "token");

	if #editable > 1 then
		title = title .. " e mais " .. (#editable - 1);
	end;

	frm:prepareFor({
		title = title,
		close = function() scene.viewport:closeForm(frm); end,

		getSlot = function(i)
			local r = FSAURA.getSlots(editable[1])[i];

			if r.shape == "" then
				return nil; -- valores padrão
			end;

			return r;
		end,

		describe = function(r)
			return FSAURA.describe(scene, r);
		end,

		onApply = function(slot, r)
			local spec, err = toSpec(scene, r);

			if spec == nil then
				showMessage(err);
				return;
			end;

			for _, t in ipairs(editable) do
				if t.isObjectAlive then
					local slots = FSAURA.getSlots(t);
					slots[slot] = r;
					saveSlots(t, slots);
					local errs = FSAURA.renderToken(scene, t, slots);

					if #errs > 0 then
						FSC.chatLocal(scene, "[Auras] " .. table.concat(errs, "; "));
					end;
				end;
			end;
		end,

		onRemove = function(slot)
			for _, t in ipairs(editable) do
				if t.isObjectAlive then
					local slots = FSAURA.getSlots(t);
					slots[slot] = {on = "0", shape = ""};
					saveSlots(t, slots);
					FSAURA.renderToken(scene, t, slots);
				end;
			end;
		end
	});

	scene.viewport:showForm(frm, {placement = "center"});
end;

----------------------------------------------------------------------
-- Registro no Scene
----------------------------------------------------------------------

SceneLib.registerPlugin(function(scene, attachment)
	local viewport = scene.viewport;
	local lstMouseDown = nil;

	viewport:setupToolCategory(TOOL_CATEGORY, "Scene Suite", 50);

	viewport:addToolButton(TOOL_CATEGORY, "Auras: clique em um token (ou use os selecionados)",
		"/images/tool_aura.png", 20, {selectable = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel > 0 then
				FSAURA.openFor(scene, sel);
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

					FSAURA.openFor(scene, inSel and s or {tk});
				end;
			end);
		end,
		function()
			if lstMouseDown ~= nil then
				viewport:unlisten(lstMouseDown);
				lstMouseDown = nil;
			end;
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Auras: redesenhar todas (após mudar o grid)",
		"/images/tool_refresh.png", 21, {dontFocus = true},
		function()
			local n = 0;

			for _, t in ipairs(FSC.allTokens(scene)) do
				if FSC.canEdit(scene, t) then
					local slots = FSAURA.getSlots(t);

					if hasAnyAura(slots) or FSC.hasOps(t.canvas, "fsaura") then
						FSAURA.renderToken(scene, t, slots);
						n = n + 1;
					end;
				end;
			end;

			FSC.chatLocal(scene, "[Auras] " .. n .. " token(s) redesenhado(s).");
		end);

	viewport:addToolButton(TOOL_CATEGORY, "Auras: remover dos selecionados",
		"/images/tool_clear.png", 22, {dontFocus = true},
		function()
			local sel = FSC.selectedTokens(scene);

			if #sel == 0 then
				showMessage("Selecione os tokens primeiro.");
				return;
			end;

			for _, t in ipairs(sel) do
				if FSC.canEdit(scene, t) then
					saveSlots(t, {});
					FSC.removeOps(t.canvas, "fsaura");
				end;
			end;
		end);

	-- Redesenha automaticamente quando o token muda de tamanho, sai do grid
	-- ou gira (cones que seguem a rotação). Apenas o mestre faz isso, para
	-- evitar que vários clientes reescrevam o mesmo token ao mesmo tempo.
	FSC.watchTokenBounds(scene, "fsaura", function(token)
		if not scene.isGM then
			return;
		end;

		local ud = token.userData;

		if ud == nil or ud[UD_FIELD] == nil or ud[UD_FIELD] == "" then
			return;
		end;

		local slots = FSAURA.getSlots(token);

		if not hasAnyAura(slots) then
			return;
		end;

		if ud[SIG_FIELD] ~= FSC.tokenSignature(scene, token, true) then
			FSAURA.renderToken(scene, token, slots);
		end;
	end);
end);
