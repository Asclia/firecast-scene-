-- Cenários executados por tools/test_harness.py contra o SDK simulado.

local scene = MOCK.newScene()
local vp = scene.viewport

-- tokens: médio em (3,3), grande em (6,2) (2x2 quadrados), minúsculo
local medium = scene:addToken(3 * 1.5, 3 * 1.5, 1.5, 1.5)
local large = scene:addToken(6 * 1.5, 2 * 1.5, 3.0, 3.0)
large.name = "Ogro"
local tiny = scene:addToken(10 * 1.5, 10 * 1.5, 0.75, 0.75)

for _, fn in ipairs(SceneLib.plugins) do
	fn(scene, {})
end

MOCK.runTimers()

local function tool(prefix)
	for _, t in ipairs(vp.tools) do
		if t.title:sub(1, #prefix) == prefix then return t end
	end
	error("ferramenta não encontrada: " .. prefix)
end

local function count(canvas, prefix)
	local n = 0
	-- conta direto na lista interna do mock (verdade, independe do índice)
	for _, op in ipairs(canvas._ops) do
		if FSC.startsWith(op.name, prefix) then n = n + 1 end
	end
	return n
end

local function click(x, y, button, extra)
	local sx, sy = vp:worldToScreen(x, y)
	local ev = {x = sx, y = sy, button = button or "left"}
	for k, v in pairs(extra or {}) do ev[k] = v end
	vp:fire("onMouseMove", ev)
	vp:fire("onMouseDown", ev)
end

local function frames(n, dtMs)
	for i = 1, n do
		MOCK.now = MOCK.now + (dtMs or 40)
		MOCK.tickIntervals()
		vp:fire("onAfterDrawLayers")
		MOCK.runTimers()
	end
end

------------------------------------------------------------------ Condições
do
	medium.selected = true
	local t = tool("Condições: clique")
	t.cb()
	-- o formulário foi aberto; pega a instância criada
	local frm
	for k, v in pairs(FSCOND) do end
	-- simula marcação via formulário real (script do .lfm)
	-- (a forma é guardada internamente; reabrimos pelo openFor para pegar)
	FSCOND.openFor(scene, {large})
	local opened = MOCK.forms.frmFSConditions
	assert(opened ~= nil and opened._name == "frmFSConditions", "form de condições")
	opened.cbx_blinded.checked = true
	opened.edt_blinded.text = "3"
	opened.cbx_shaken.checked = true
	opened.cbx_ff_haste.checked = true
	opened.edt_ff_haste.text = "2"
	opened.cmbU_ff_haste.value = "min"
	opened.cbx_shaken.checked = true
	opened.edt_shaken.text = "1"
	opened.cmbU_shaken.value = "h"
	opened.cmbFilter.value = "ff"
	opened:applyFilter()
	assert(opened.flp_blinded.visible == false and opened.flp_ff_haste.visible == true, "filtro")
	opened.cmbFilter.value = "all"; opened.edtSearch.text = "cego"; opened:applyFilter()
	assert(opened.flp_blinded.visible == true and opened.flp_shaken.visible == false, "busca por nome")
	assert(opened.grpHdr_ff.visible == false and opened.grpHdr_pf.visible == true, "cabeçalho some sem resultados")
	opened.edtSearch.text = "haste"; opened:applyFilter()
	assert(opened.flp_ff_haste.visible and opened.flp_haste.visible, "busca em inglês")
	opened.edtSearch.text = ""; opened:applyFilter()
	opened:doApply()
	local list = FSCOND.getList(large)
	assert(#list == 3, "3 condições, veio " .. #list)
	local byId = {}
	for _, e in ipairs(list) do byId[e.id] = e end
	assert(byId.ff_haste.r == "20" and byId.ff_haste.u == "min", "2 min = 20 rodadas")
	assert(byId.shaken.r == "600" and byId.shaken.u == "h", "1 h = 600 rodadas")
	assert(byId.blinded.r == "3" and byId.blinded.u == "r", "3 rodadas")
	local badge = large.canvas:findByName("fscond_" .. (function() for i, e in ipairs(list) do if e.id == "ff_haste" then return i end end end)() .. "_dt")
	assert(badge.text == "2m", "selo em minutos: " .. tostring(badge.text))
	-- avança 1 rodada e reabre: 19 rodadas = 1.9 min
	FSCOND.advanceRound(scene)
	FSCOND.openFor(scene, {large})
	assert(opened.edt_ff_haste.text == "1.9" and opened.cmbU_ff_haste.value == "min", "reabrir em min: " .. opened.edt_ff_haste.text)
	assert(opened.edt_shaken.text == "1.0" or opened.edt_shaken.text == "1", "hora: " .. opened.edt_shaken.text)
	FSCOND.undoRound(scene)
	FSCOND.openFor(scene, {large})
	assert(opened.edt_ff_haste.text == "2", "desfazer volta a 2 min")
	-- sufixo digitado tem prioridade sobre a unidade escolhida
	assert(FSCOND.parseRounds("3h", "r") == 1800 and FSCOND.parseRounds("1,5", "min") == 15, "parse")
	-- duração para todas as marcadas, com unidade
	opened.edtAllRounds.text = "10"; opened.cmbAllUnit.value = "min"; opened:setAllRounds()
	assert(opened.edt_blinded.text == "10" and opened.cmbU_blinded.value == "min", "duração em lote")
	opened.edt_blinded.text = "3"; opened.cmbU_blinded.value = "r"
	opened.edt_ff_haste.text = "2"; opened.cmbU_ff_haste.value = "min"
	opened.edt_shaken.text = "1"; opened.cmbU_shaken.value = "h"
	opened:doApply()
	assert(count(large.canvas, "fscond_") > 6, "ops de condição")
	-- personalizada
	opened.edtCustomName.text = "Marcado pelo Inquisidor"
	opened.edtCustomRounds.text = "2"
	opened.cmbCustomUnit.value = "r"
	opened.cmbCustomColor.color = "#00838F"
	opened:doAddCustom()
	assert(#FSCOND.getList(large) == 4, "custom")
	-- todas as configurações de posição
	for _, pos in ipairs({"top", "bottom", "right", "left"}) do
		for _, names in ipairs({"hover", "always", "never"}) do
			FSCOND.setCfg(scene, {pos = pos, size = "0.4", names = names})
			FSCOND.rerenderAll(scene)
		end
	end
	-- avançar rodadas
	FSCOND.advanceRound(scene)
	local l2 = FSCOND.getList(large)
	local blinded
	for _, e in ipairs(l2) do if e.id == "blinded" then blinded = e end end
	assert(blinded.r == "2", "rodada avançou: " .. tostring(blinded and blinded.r))
	FSCOND.undoRound(scene)
	FSCOND.advanceRound(scene); FSCOND.advanceRound(scene); FSCOND.advanceRound(scene)
	for _, e in ipairs(FSCOND.getList(large)) do assert(e.id ~= "blinded", "cego deveria expirar") end
	-- muitas condições num token pequeno
	local all = {}
	for _, c in ipairs(FSCOND_DATA.list) do if c.group ~= "hidden" then all[#all+1] = {id = c.id, r = "5", h = "0"} end end
	FSCOND.setList(scene, tiny, all)
	assert(count(tiny.canvas, "fscond_") > 200, "muitas condições")
	FSCOND.configure(scene)
	tool("Condições: avançar").cb()
	tool("Condições: desfazer").cb()
	tiny.selected = true
	tool("Condições: remover").cb()
	assert(count(tiny.canvas, "fscond_") == 0, "remover")
	tiny.selected = false
	t.deact()
	medium.selected = false
	print("Condições OK")
end

------------------------------------------------------------------ Auras
do
	local opened
	local oldNew = GUI.newForm
	GUI.newForm = function(n) opened = oldNew(n); return opened end
	FSAURA.openFor(scene, {medium})
	GUI.newForm = oldNew
	assert(opened._name == "frmFSAura")
	for _, shape in ipairs({"emanation", "square", "cone", "line"}) do
		for _, mode in ipairs({"grid", "smooth"}) do
			for _, follow in ipairs({false, true}) do
				opened.cmbSlot.value = "1"
				opened:changeSlot()
				opened.cmbShape.value = shape
				opened.cmbMode.value = mode
				opened.edtRadius.text = "10 ft"
				opened.cbxFollow.checked = follow
				opened.cmbDir.value = "45"
				opened.edtName.text = "Aura de Coragem"
				opened:updateHint()
				opened:doApply()
				assert(count(medium.canvas, "fsaura1_") >= 2, "aura " .. shape .. "/" .. mode)
			end
		end
	end
	-- slot 2 em metros, slot 3 em quadrados
	opened.cmbSlot.value = "2"; opened:changeSlot(); opened.edtRadius.text = "6 m"; opened.cmbShape.value = "emanation"; opened:doApply()
	opened.cmbSlot.value = "3"; opened:changeSlot(); opened.edtRadius.text = "2 q"; opened:doApply()
	assert(count(medium.canvas, "fsaura2_") >= 2 and count(medium.canvas, "fsaura3_") >= 2, "slots 2 e 3")
	-- valor inválido
	opened.edtRadius.text = "abc"; opened:doApply()
	opened:doRemove()
	assert(count(medium.canvas, "fsaura3_") == 0, "remover slot 3")
	medium.selected = true
	tool("Auras: remover").cb()
	assert(count(medium.canvas, "fsaura") == 0, "remoção completa das auras")
	medium.selected = false
	-- redimensionar o token dispara redesenho (mestre)
	medium.width = 3.0; medium.height = 3.0
	medium:fire("onBoundsChange", medium)
	MOCK.runTimers()
	medium.width = 1.5; medium.height = 1.5
	medium:fire("onBoundsChange", medium)
	MOCK.runTimers()
	-- grid hexagonal
	scene.grid.gridType = "vertHex"
	FSAURA.renderToken(scene, medium)
	scene.grid.gridType = "square"
	tool("Auras: redesenhar").cb()
	print("Auras OK")
end

------------------------------------------------------------------ Alcance
do
	local opened
	local oldNew = GUI.newForm
	GUI.newForm = function(n) opened = oldNew(n); return opened end
	FSREACH.openFor(scene, {large})
	GUI.newForm = oldNew
	assert(opened._name == "frmFSReach")
	opened.edtNatural.text = "10 ft"; opened.cbxWeapon.checked = true; opened.cmbColor.color = "#8E24AA"; opened:updateHint()
	assert(opened.labHint.text:find("20 ft"), "10 ft + haste = 20 ft: " .. opened.labHint.text)
	opened:doApply()
	assert(count(large.canvas, "fsreach_") >= 2, "reach ops")
	FSREACH.openFor(scene, {medium})
	opened.edtNatural.text = "3 m"; opened.cbxWeapon.checked = false; opened:doApply()
	assert(count(medium.canvas, "fsreach_") >= 2)
	-- remover precisa limpar tudo com um clique
	FSREACH.openFor(scene, {medium})
	opened:doRemove()
	assert(count(medium.canvas, "fsreach_") == 0, "remoção completa do alcance")
	FSREACH.openFor(scene, {medium})
	opened.edtNatural.text = "0 ft"; opened:doApply()
	assert(count(medium.canvas, "fsreach_") == 0, "0 ft não desenha")
	FSREACH.openFor(scene, {medium})
	opened.edtNatural.text = "5 ft"; opened:doApply()
	for _, v in ipairs({"always", "hidden", "hover"}) do
		scene.userData.fsReachView = v
		FSREACH.rerenderAll(scene)
	end
	tool("Alcance: modo").cb()
	large.width = 4.5; large.height = 4.5
	large:fire("onBoundsChange", large); MOCK.runTimers()
	print("Alcance OK")
end

------------------------------------------------------------------ Áreas de magia
do
	local frm
	local oldNew = GUI.newForm
	GUI.newForm = function(n) frm = oldNew(n); return frm end
	local t = tool("Área de magia")
	t.cb()
	GUI.newForm = oldNew
	assert(frm._name == "frmFSSpellArea", "form de área")

	-- preset 1 = Bola de Fogo (explosão de 20 ft)
	frm.cmbPreset.value = "1"; frm:applyPreset()
	local before = #scene._items
	medium.selected = true
	click(5 * 1.5, 5 * 1.5)
	assert(#scene._items == before + 1, "área criada")
	local ud = scene._items[#scene._items]
	assert(ud.objectType == "userDrawing" and count(ud.canvas, "fssa_") == 3, "ops da área")
	assert(math.abs(ud.width - 8 * 1.5) < 1e-6, "20 ft = 8 quadrados de diâmetro, veio " .. ud.width)
	medium.selected = false
	frames(60)
	-- ctrl+clique remove
	click(5 * 1.5, 5 * 1.5, "left", {ctrlOrCmdKey = true})
	assert(#scene._items == before, "remoção com ctrl")

	-- todos os presets e modos
	for idx = 1, #FSSA.PRESETS do
		for _, mode in ipairs({"grid", "smooth"}) do
			frm.cmbPreset.value = tostring(idx); frm:applyPreset()
			frm.cmbMode.value = mode; frm:notify()
			local p = FSSA.PRESETS[idx]
			local n0 = #scene._items
			click(20 * 1.5, 20 * 1.5)
			frames(1)
			if p.shape == "cone" or p.shape == "line" or p.shape == "square" then
				assert(#scene._items == n0, "primeiro clique só define a origem")
				click(24 * 1.5, 18 * 1.5)
			end
			assert(#scene._items == n0 + 1, "área " .. p.label .. " " .. mode)
		end
	end
	-- personalizada em metros, origem livre, cancelamento
	frm.cmbPreset.value = "0"; frm:applyPreset()
	frm.cmbShape.value = "line"; frm.edtSize.text = "9 m"; frm.edtWidth.text = "3 m"; frm:notify()
	click(2, 2, "left", {shiftKey = true}); click(2, 2, "right")
	vp:fire("onKeyDown", {keyCode = 27})
	click(2, 2); click(9, 9)
	frm.edtSize.text = "xyz"; frm:notify(); click(3, 3)
	tool("Áreas de magia: remover").cb()
	frm:doClose()
	t.deact()
	print("Áreas de magia OK")
end

------------------------------------------------------------------ Clima
do
	local frm
	local oldNew = GUI.newForm
	GUI.newForm = function(n) frm = oldNew(n); return frm end
	tool("Clima: escolher").cb()
	GUI.newForm = oldNew
	assert(frm._name == "frmFSWeather")
	for _, fx in ipairs({"rain", "storm", "snow", "blizzard", "fog", "wind", "sand", "embers", "leaves", "night", "underwater", "fireflies"}) do
		for _, it in ipairs({"1", "3"}) do
			for _, wind in ipairs({"0", "-0.7", "0.7"}) do
				frm.cmbEffect.value = fx; frm.cmbIntensity.value = it; frm.cmbWind.value = wind; frm.cmbOpacity.value = "0.6"
				frm:doApply()
				local d0 = vp.draws
				frames(80, 50)
				assert(vp.draws > d0, "clima desenhou: " .. fx)
			end
		end
	end
	tool("Clima: ligar/desligar").cb(); frames(3)
	tool("Clima: ligar/desligar").cb(); frames(3)
	frm:doOff(); frames(3)
	print("Clima OK")
end

------------------------------------------------------------------ Animações
do
	local frm
	local oldNew = GUI.newForm
	GUI.newForm = function(n) frm = oldNew(n); return frm end
	local t = tool("Animações de magia")
	t.cb()
	GUI.newForm = oldNew
	assert(frm._name == "frmFSSpellFX")
	local ids = frm.cmbFX.values
	assert(#ids >= 25, "catálogo com " .. #ids .. " efeitos")
	for _, id in ipairs(ids) do
		frm.cmbFX.value = id; frm:fxChanged()
		frm.edtCount.text = "4"; frm:notify()
		local m0 = #MOCK.messages
		medium.selected = true
		click(15 * 1.5, 6 * 1.5)
		if id == "chain_lightning" then
			click(16 * 1.5, 9 * 1.5); click(18 * 1.5, 7 * 1.5)
			click(0, 0, "right")
		end
		medium.selected = false
		assert(#MOCK.messages == m0 + 1, "mensagem enviada para " .. id)
		local d0 = vp.draws
		for k = 1, 140 do frames(1, 25) end
		assert(vp.draws > d0, "animação desenhou: " .. id)
	end
	-- sem token selecionado: clique de origem + alvo
	frm.cmbFX.value = "fireball"; frm:fxChanged()
	click(2, 2); click(20, 20); frames(100, 25)
	-- várias ao mesmo tempo
	for _, id in ipairs({"fireball", "meteor_swarm", "holy_burst", "ice_storm"}) do
		scene:broadcastMessage("fsfx_play", {fx = id, sx = 3, sy = 3, tx = 15, ty = 12, r = 6, n = 3}, true)
	end
	frames(150, 25)
	-- mensagem malformada é ignorada
	scene:broadcastMessage("fsfx_play", {fx = "nao_existe", sx = 1, sy = 1}, true)
	scene:broadcastMessage("fsfx_play", {fx = "fireball"}, true)
	frames(5)
	tool("Animações: parar").cb()
	frm:doClose(); t.deact()
	print("Animações OK (" .. #ids .. " efeitos)")
end

------------------------------------------------------------------ Integração Áreas -> Animações
do
	local m0 = #MOCK.messages
	local cfg = {preset = "1", shape = "burst", size = "20 ft", fx = true}
	FSSA.sendFX(scene, cfg, 10, 10, 90, 4)
	assert(#MOCK.messages == m0 + 1 and MOCK.messages[#MOCK.messages].msg.fx == "fireball", "integração")
	frames(120, 25)
	print("Integração OK")
end

------------------------------------------------------------------ Responsividade
do
	local W0, H0 = vp.width, vp.height
	vp.width, vp.height = 320, 240   -- Scene pequeno no canto da tela
	FSCOND.openFor(scene, {large})
	local f = MOCK.forms.frmFSConditions
	assert(f.width <= 320 * 0.92 and f.height <= 240 * 0.92, "condições cabe no scene: " .. f.width .. "x" .. f.height)
	FSAURA.openFor(scene, {large})
	assert(MOCK.forms.frmFSAura.width <= 295, "auras cabe")
	vp.width, vp.height = 120, 90     -- menor que o mínimo: respeita o mínimo
	FSREACH.openFor(scene, {large})
	assert(MOCK.forms.frmFSReach.width == 220 and MOCK.forms.frmFSReach.height == 160, "mínimo")
	vp.width, vp.height = 2000, 1400  -- tela grande: tamanho natural
	FSCOND.openFor(scene, {large})
	assert(f.width == 940 and f.height == 640, "tamanho natural")
	vp.width, vp.height = W0, H0
	print("Responsividade OK")
end
