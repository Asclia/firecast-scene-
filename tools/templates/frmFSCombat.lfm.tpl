<?xml version="1.0" encoding="UTF-8"?>
<!-- ARQUIVO GERADO por tools/build.py a partir de tools/templates/frmFSCombat.lfm.tpl. Edite o template. -->
@ROOT_OPEN@

	<script><![CDATA[
		local scene = nil;
		local onCloseFn = nil;
		local loading = false;
		local rowIdx = {};      -- linha da tela -> posição na lista do combate
		local MAX = @MAX@;

		function self:findScene()
			if scene ~= nil and scene.isObjectAlive then
				return scene;
			end;

			scene = nil;

			if FSCOMBAT == nil then
				return nil;
			end;

			local mesa = nil;

			pcall(function()
				mesa = Firecast.getMesaDe(sheet or self);
			end);

			scene = FSCOMBAT.sceneForMesa(mesa);
			return scene;
		end;

		-- painel do Scene: liga diretamente ao scene
		function self:bindScene(sc, onClose)
			scene = sc;
			onCloseFn = onClose;
			FSCOMBAT.registerView(self);
			self:refreshFromScene();
		end;

		function self:refreshFromScene()
			local sc = self:findScene();

			loading = true;
			self:beginUpdate();

			if sc == nil then
				self.labRound.text = "Abra o Scene desta mesa";
				self.flaGM.visible = false;

				for i = 1, MAX do
					self["row" .. i].visible = false;
				end;

				self:endUpdate();
				loading = false;
				return;
			end;

			local vm = FSCOMBAT.viewModel(sc);

			if vm.active and vm.count > 0 then
				self.labRound.text = "Rodada " .. vm.round;
			else
				self.labRound.text = "Sem combate";
			end;

			self.flaGM.visible = vm.isGM;
			rowIdx = {};

			for i = 1, MAX do
				local row = self["row" .. i];
				local r = vm.rows[i];

				if r == nil then
					row.visible = false;
				else
					rowIdx[i] = r.idx;
					row.visible = true;
					local name = r.name or "?";

					if r.hidden then
						name = name .. "  (oculto)";
					end;

					self["rowName" .. i].text = name;
					self["rowInit" .. i].text = (r.init ~= nil) and tostring(r.init) or "";
					self["rowInit" .. i].readOnly = not r.canEdit;
					self["rowImg" .. i].src = r.image or "";
					self["rowMenu" .. i].visible = vm.isGM;

					if r.current then
						self["rowBg" .. i].color = "#FFD54F38";
						self["rowBg" .. i].strokeColor = "#FFD54F";
						self["rowBg" .. i].strokeSize = 2;
						self["rowName" .. i].fontStyle = "bold";
					else
						self["rowBg" .. i].color = "#FFFFFF0D";
						self["rowBg" .. i].strokeColor = "#00000000";
						self["rowBg" .. i].strokeSize = 0;
						self["rowName" .. i].fontStyle = r.hidden and "italic" or "";
					end;
				end;
			end;

			self:endUpdate();
			loading = false;
		end;

		local function sc()
			local s = self:findScene();

			if s == nil then
				showMessage("Abra o Scene desta mesa primeiro.");
			end;

			return s;
		end;

		function self:rowInit(i)
			if loading or rowIdx[i] == nil then
				return;
			end;

			local s = sc();

			if s ~= nil then
				FSCOMBAT.setInit(s, rowIdx[i], self["rowInit" .. i].text);
			end;
		end;

		function self:rowMenu(i)
			local s = sc();
			local idx = rowIdx[i];

			if s == nil or idx == nil then
				return;
			end;

			local opts = {"Ocultar / mostrar para os jogadores", "Definir modificador de iniciativa",
			              "Subir", "Descer", "Tornar o turno atual", "Remover do combate"};

			Dialogs.choose("Ação:", opts, function(ok, k)
				if not ok then return; end;

				if k == 1 then
					FSCOMBAT.toggleHidden(s, idx);
				elseif k == 2 then
					Dialogs.inputQuery("Modificador", "Modificador de iniciativa (ex.: 3 ou -1):", "0", function(v)
						FSCOMBAT.setMod(s, idx, v);
					end);
				elseif k == 3 then
					FSCOMBAT.move(s, idx, -1);
				elseif k == 4 then
					FSCOMBAT.move(s, idx, 1);
				elseif k == 5 then
					local st, list = FSCOMBAT.getState(s);
					st.turn = idx;
					st.active = true;
					FSCOMBAT.save(s, st, list);
				elseif k == 6 then
					FSCOMBAT.removeAt(s, idx);
				end;
			end);
		end;

		function self:act(name)
			local s = sc();

			if s == nil then
				return;
			end;

			if name == "next" then
				FSCOMBAT.next(s);
			elseif name == "prev" then
				FSCOMBAT.prev(s);
			elseif name == "addSel" then
				local sel = FSC.selectedTokens(s);

				if #sel == 0 then
					showMessage("Selecione os tokens no Scene primeiro.");
				else
					FSCOMBAT.addTokens(s, sel, false);
				end;
			elseif name == "addHidden" then
				local sel = FSC.selectedTokens(s);

				if #sel == 0 then
					showMessage("Selecione os tokens no Scene primeiro.");
				else
					FSCOMBAT.addTokens(s, sel, true);
				end;
			elseif name == "addCustom" then
				Dialogs.inputQuery("Nova entrada", "Nome (ex.: Ação de covil):", "", function(v)
					if v ~= nil and v:gsub("%s", "") ~= "" then
						FSCOMBAT.addCustom(s, v);
					end;
				end);
			elseif name == "roll" then
				FSCOMBAT.roll(s, true, false);
			elseif name == "rollAll" then
				FSCOMBAT.roll(s, false, false);
			elseif name == "sort" then
				FSCOMBAT.sort(s);
			elseif name == "reset" then
				FSCOMBAT.resetRounds(s);
			elseif name == "end" then
				Dialogs.confirmYesNo("Encerrar o combate e limpar a lista?", function(yes)
					if yes then FSCOMBAT.endCombat(s); end;
				end);
			end;
		end;

		function self:doClose()
			if onCloseFn ~= nil then
				onCloseFn();
			end;
		end;

		if FSCOMBAT ~= nil then
			FSCOMBAT.registerView(self);
		end;
	]]></script>

	<!-- Cabeçalho: rodada + controles do mestre (se reorganizam conforme a largura) -->
	<flowLayout align="top" autoHeight="true" margins="{left=4, right=4, top=4}">
		<flowPart minWidth="150" maxWidth="5000" height="28">
			<label name="labRound" align="client" fontSize="16" fontStyle="bold" text="Sem combate" wordWrap="false"/>
			@CLOSE_BUTTON@
		</flowPart>
		<flowLineBreak/>
	</flowLayout>

	<flowLayout name="flaGM" align="top" autoHeight="true" margins="{left=4, right=4, bottom=4}">
		<flowPart width="44" height="30"><button align="client" text="&#9664;" margins="{right=2}" onClick="self:act('prev')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="Próximo &#9654;" fontStyle="bold" margins="{right=2}" onClick="self:act('next')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="+ Selecion." margins="{right=2}" onClick="self:act('addSel')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="+ Ocultos" margins="{right=2}" onClick="self:act('addHidden')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="+ Entrada" margins="{right=2}" onClick="self:act('addCustom')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="Rolar faltantes" margins="{right=2}" onClick="self:act('roll')"/></flowPart>
		<flowPart width="96" height="30"><button align="client" text="Rolar todos" margins="{right=2}" onClick="self:act('rollAll')"/></flowPart>
		<flowPart width="70" height="30"><button align="client" text="Ordenar" margins="{right=2}" onClick="self:act('sort')"/></flowPart>
		<flowPart width="80" height="30"><button align="client" text="Rodada 1" margins="{right=2}" onClick="self:act('reset')"/></flowPart>
		<flowPart width="80" height="30"><button align="client" text="Encerrar" margins="{right=2}" onClick="self:act('end')"/></flowPart>
	</flowLayout>

	<scrollBox align="client" margins="{left=4, right=2, bottom=4}">
@ROWS@
	</scrollBox>
@ROOT_CLOSE@
