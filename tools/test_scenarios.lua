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

------------------------------------------------------------------ PV rápido
do
	medium.barValue1 = "20"; medium.barMax1 = "30"
	large.barValue1 = "50"; large.barMax1 = "50"
	medium.selected = true; large.selected = true
	tool("PV rápido").cb()
	local f = MOCK.forms.frmFSHP
	assert(f ~= nil and f.labSel.text:find("20/30"), "painel mostra seleção: " .. tostring(f and f.labSel.text))
	f.edtAmount.text = "8"; f:doOp("damage")
	assert(medium.barValue1 == "12" and large.barValue1 == "42", "dano")
	f.edtAmount.text = "5"; f:doOp("half")
	assert(medium.barValue1 == "10", "metade (mínimo 1): " .. medium.barValue1)
	f.edtAmount.text = "4"; f:doOp("weak")
	assert(medium.barValue1 == "4", "x1,5: " .. medium.barValue1)
	f:doUndo()
	assert(medium.barValue1 == "10", "desfazer")
	f.edtAmount.text = "100"; f:doOp("heal")
	assert(medium.barValue1 == "30" and large.barValue1 == "50", "cura limitada ao máximo")
	f.edtAmount.text = "6"; f:doOp("temp")
	assert(FSHP.getTemp(medium) == 6 and count(medium.canvas, "fshp_temp") == 2, "PV temporário")
	f.edtAmount.text = "10"; f:doOp("damage")
	assert(FSHP.getTemp(medium) == 0 and medium.barValue1 == "26", "temp absorve primeiro: " .. medium.barValue1)
	assert(count(medium.canvas, "fshp_temp") == 0, "temp some ao zerar")
	f.edtAmount.text = "40"; f:doOp("damage")
	assert(medium.barValue1 == "-14", "PV negativo permitido (morrendo)")
	f.edtAmount.text = "7"; f:doOp("set")
	assert(medium.barValue1 == "7", "definir")
	frames(70, 25)   -- números flutuantes
	f.edtAmount.text = "-3"; f:doOp("damage")   -- inválido
	f.edtAmount.text = "3"; f.cmbBar.value = "2"; f:barChanged(); f:doOp("damage")  -- sem barra 2
	assert(f.labSel.text:find("sem barra"), "aviso sem barra")
	f:doClose()
	medium.selected = false; large.selected = false
	print("PV rápido OK")
end

------------------------------------------------------------------ Tracker de combate
do
	medium.image = {url = "http://exemplo/guerreiro.png"}
	medium.name = "Guerreiro"; large.name = "Ogro"; tiny.name = "Rato"
	-- condição de 2 rodadas no guerreiro para checar a integração
	FSCOND.setList(scene, medium, {{id = "blinded", r = "2", u = "r", h = "0"}})

	-- painel no Scene
	tool("Combate: abrir").cb()
	local panel = MOCK.forms.frmFSCombatPanel
	assert(panel ~= nil, "painel")
	assert(panel.labRound.text == "Sem combate", "sem combate: " .. panel.labRound.text)

	medium.selected = true; large.selected = true
	panel:act("addSel")
	medium.selected = false; large.selected = false
	tiny.selected = true; panel:act("addHidden"); tiny.selected = false
	local st, list = FSCOMBAT.getState(scene)
	assert(#list == 3 and st.active, "3 no combate")
	assert(medium.userData.fsUid ~= nil, "uid estável")

	-- iniciativas manuais e ordenação
	panel.rowInit1.text = "12"; panel:rowInit(1)
	panel.rowInit2.text = "18"; panel:rowInit(2)
	FSCOMBAT.setMod(scene, 3, 4)
	panel:act("roll")       -- só o rato (sem iniciativa)
	st, list = FSCOMBAT.getState(scene)
	assert(list[1].n == "Ogro" or list[1].i >= list[2].i, "ordenado")
	for _, e in ipairs(list) do assert(e.i ~= nil, "todos com iniciativa") end
	panel:refreshFromScene()
	assert(panel.row3.visible and not panel.row4.visible, "3 linhas visíveis")
	assert(panel.labRound.text == "Rodada 1", panel.labRound.text)

	-- anel no token da vez
	local first = FSCOMBAT.tokenMap(scene)[list[1].u]
	assert(count(first.canvas, "fscombat_turn") == 1, "anel no primeiro")

	-- jogador não vê o oculto
	scene.isGM = false
	local vm = FSCOMBAT.viewModel(scene)
	assert(#vm.rows == 2, "oculto escondido do jogador")
	panel:refreshFromScene()
	assert(panel.flaGM.visible == false, "jogador sem controles")
	scene.isGM = true

	-- avançar turnos: ao fechar a volta, Condições desconta 1 rodada
	panel:act("next"); panel:act("next")
	st = FSCOMBAT.getState(scene)
	assert(st.turn == 3 and st.round == 1)
	panel:act("next")
	st = FSCOMBAT.getState(scene)
	assert(st.turn == 1 and st.round == 2, "nova rodada")
	assert(FSCOND.getList(medium)[1].r == "1", "condição descontada pelo tracker")
	panel:act("prev")
	st = FSCOMBAT.getState(scene)
	assert(st.turn == 3 and st.round == 1, "voltar turno volta rodada")

	-- menu da linha (Dialogs mock escolhe a opção padrão = 1: ocultar)
	panel:rowMenu(1)
	panel:act("sort"); panel:act("reset")
	FSCOMBAT.move(scene, 1, 1)
	FSCOMBAT.removeAt(scene, 3)
	st, list = FSCOMBAT.getState(scene)
	assert(#list == 2, "remover")
	panel:act("addCustom")   -- inputQuery mock devolve "" -> ignorado
	FSCOMBAT.addCustom(scene, "Ação de covil")
	st, list = FSCOMBAT.getState(scene)
	assert(#list == 3, "entrada sem token")
	panel:refreshFromScene()

	-- janela acoplável encontra o scene sozinha
	local dock = GUI.newForm("frmFSCombatDock")
	dock:refreshFromScene()
	assert(dock.labRound.text:find("Rodada"), "dock achou o scene: " .. dock.labRound.text)
	dock:act("next")

	-- poll detecta mudança remota
	frames(30, 50)

	-- encerrar
	panel:act("end")
	st, list = FSCOMBAT.getState(scene)
	assert(#list == 0 and not st.active, "encerrado")
	for _, t in ipairs({medium, large, tiny}) do assert(count(t.canvas, "fscombat_turn") == 0, "anéis removidos") end
	panel:doClose()
	print("Tracker de combate OK")
end

------------------------------------------------------------------ Luz e visão
do
	FSLIGHT.openFor(scene, {medium})
	local f = MOCK.forms.frmFSLight
	f.cmbLight.value = "torch"; f.cmbVision.value = "dark60"; f:changed()
	assert(f.labHint.text:find("20 ft normal"), f.labHint.text)
	f:doApply()
	-- 20 ft = 4 quadrados = 6 m (célula de 1,5 m)
	assert(math.abs(medium.lightIntenseRange - 6) < 1e-6 and math.abs(medium.lightWeakRange - 12) < 1e-6, "tocha em métrica de mundo")
	assert(math.abs(medium.visionDarknessRange - 18) < 1e-6 and medium.visionHaveVision == true, "visão no escuro 60 ft")
	FSLIGHT.openFor(scene, {medium})
	f.cmbLight.value = "custom"; f.edtBright.text = "3 m"; f.edtDim.text = "6 m"; f.cmbAngle.value = "90"
	f.cmbVision.value = "keep"; f:doApply()
	assert(math.abs(medium.lightIntenseRange - 3) < 1e-6 and medium.lightAngle == 90, "luz personalizada em metros")
	FSLIGHT.openFor(scene, {medium})
	f.cmbLight.value = "custom"; f.edtBright.text = "abc"; f:changed()
	assert(f.labHint.text:find("inválida"), "erro de valor")
	-- botão rápido: apaga, depois reacende com a mesma luz
	medium.selected = true
	tool("Luz: acender").cb()
	assert(medium.lightWeakRange == 0, "apagou")
	tool("Luz: acender").cb()
	assert(math.abs(medium.lightWeakRange - 6) < 1e-6 and medium.lightAngle == 90, "reacendeu com a última luz")
	medium.selected = false
	-- token sem memória acende uma tocha
	large.lightWeakRange = 0; large.lightIntenseRange = 0
	FSLIGHT.toggle(scene, large)
	assert(math.abs(large.lightWeakRange - 12) < 1e-6, "tocha padrão")
	local t = tool("Luz e visão: clique"); t.cb(); click(medium.x + 0.1, medium.y + 0.1); t.deact()
	print("Luz e visão OK")
end

------------------------------------------------------------------ Gatilhos e portas
do
	scene.isGM = true
	local function drag(tl, x1, y1, x2, y2, extra)
		local a, b = vp:worldToScreen(x1, y1)
		local c, d = vp:worldToScreen(x2, y2)
		vp:fire("onMouseDown", {x = a, y = b, button = "left"})
		vp:fire("onMouseMove", {x = c, y = d})
		frames(1)
		vp:fire("onMouseUp", {x = c, y = d, button = "left"})
	end

	-- porta
	local tDoor = tool("Portas: arraste")
	tDoor.cb()
	drag(tDoor, 15, 15, 16.5, 18)   -- inputQuery mock devolve "Porta"
	tDoor.deact()
	local door = FSTRIG.findByName(scene, "door", "Porta")
	assert(door ~= nil and #scene.fogOfWar.opaque == 1, "porta fechada = parede")

	-- gatilho de destino e gatilho com ações
	local tTrig = tool("Gatilhos: arraste")
	tTrig.cb()
	drag(tTrig, 30, 30, 33, 33)
	local dest = scene._items[#scene._items]
	assert(FSTRIG.isTrigger(dest) and dest.visible == false, "gatilho só para o mestre")
	local f = MOCK.forms.frmFSTrigger
	f.edtName.text = "Saída"; f:doSave()

	drag(tTrig, 4.5, 4.5, 6, 6)         -- área sob o token médio (4.5..6)
	f.edtName.text = "Armadilha"
	f.cmbWho.value = "any"
	f.cmbType1.value = "damage"; f.edtA1.text = "2d6+3"; f.edtB1.text = "1"
	f.cmbType2.value = "condition"; f.edtA2.text = "Enredado"; f.edtB2.text = "3"
	f.cmbType3.value = "door_open"; f.edtA3.text = "porta"
	f.cmbType4.value = "teleport"; f.edtA4.text = "saída"
	f:updateHints()
	assert(f.edtB2.textPrompt:find("rodadas"), "dica por tipo")
	f.cbxOnce.checked = true
	f:doSave()
	tTrig.deact()
	local trap = FSTRIG.findByName(scene, "trigger", "Armadilha")

	-- grupo escondido que outro gatilho vai mostrar
	tiny.selected = true
	tool("Gatilhos: dar nome").cb()   -- inputQuery mock devolve o valor atual ("")
	tiny.selected = false
	tiny.userData.fsGroup = "emboscada"; tiny.visible = false
	FSTRIG.run(scene, trap, {{t = "show", a = "Emboscada"}}, nil)
	assert(tiny.visible == true, "mostrar grupo")
	FSTRIG.run(scene, trap, {{t = "hide", a = "emboscada"}}, nil)
	assert(tiny.visible == false, "esconder grupo")

	-- token entra na armadilha
	medium.barValue1 = "30"
	medium.x, medium.y = 20, 20
	medium:fire("onBoundsChange", medium); MOCK.runTimers()     -- fora
	medium.x, medium.y = 4.6, 4.6
	medium:fire("onBoundsChange", medium); MOCK.runTimers()     -- entra
	local hp = tonumber(medium.barValue1)
	assert(hp <= 25 and hp >= 15, "dano 2d6+3: " .. medium.barValue1)
	local hasEnredado = false
	for _, e in ipairs(FSCOND.getList(medium)) do if e.id == "entangled" and e.r == "3" then hasEnredado = true end end
	assert(hasEnredado, "condição aplicada via gatilho")
	assert(#scene.fogOfWar.opaque == 0, "porta aberta")
	local cx, cy = medium:getCenter()
	assert(cx > 30 and cx < 33 and cy > 30 and cy < 33, "teletransportado: " .. cx .. "," .. cy)
	MOCK.runTimers()
	-- só uma vez: voltar não dispara de novo
	medium.barValue1 = "30"
	medium.x, medium.y = 20, 20; medium:fire("onBoundsChange", medium); MOCK.runTimers()
	medium.x, medium.y = 4.6, 4.6; medium:fire("onBoundsChange", medium); MOCK.runTimers()
	assert(medium.barValue1 == "30", "uso único")

	-- editar: alternar porta e rearmar/testar gatilho
	local tEdit = tool("Gatilhos: clique")
	tEdit.cb()
	click(door.x + 0.2, door.y + 0.2)
	assert(#scene.fogOfWar.opaque == 1, "porta fechada pelo clique")
	click(trap.x + 0.2, trap.y + 0.2)
	f:doReset(); f:doTest()
	f.cmbType1.value = "message"; f.edtA1.text = "Você ouve um clique..."
	f.cmbType2.value = "fx"; f.edtA2.text = "fireball"; f.edtB2.text = "10 ft"
	f:doTest()
	frames(60, 25)
	tEdit.deact()
	-- jogador não dispara nada (detecção só no mestre)
	scene.isGM = false
	medium.x, medium.y = 20, 20; medium:fire("onBoundsChange", medium); MOCK.runTimers()
	scene.isGM = true
	assert(FSTRIG.rollDice("3d1+2") == 5 and FSTRIG.rollDice("10") == 10 and FSTRIG.rollDice("abc") == nil, "dados")
	f:doDelete()
	print("Gatilhos OK")
end
