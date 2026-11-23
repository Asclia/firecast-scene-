<?xml version="1.0" encoding="UTF-8"?>
<!-- ARQUIVO GERADO por tools/build.py a partir de tools/templates/frmFSConditions.lfm.tpl. Edite o template. -->
<popupForm name="frmFSConditions" width="940" height="640" drawContainer="true" resizable="true"
           placement="center" cancelable="true">

	<script><![CDATA[
		local options = {};

		function self:closeMe()
			if options.close ~= nil then
				options.close();
			else
				self:closeMe();
			end;
		end;

		local function eachCondition(fn)
			for _, c in ipairs(FSCOND_DATA.list) do
				if c.group ~= "hidden" then
					fn(c);
				end;
			end;
		end;

		-- Filtro por grupo + busca por nome (português ou inglês)
		function self:applyFilter()
			local f = self.cmbFilter.value or "all";
			local q = (self.edtSearch.text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "");
			local groupHasVisible = {};

			eachCondition(function(c)
				local flp = self["flp_" .. c.id];

				if flp ~= nil then
					local okGroup = (f == "all") or (f == c.group);
					local okText = (q == "") or (c.name:lower():find(q, 1, true) ~= nil)
					               or ((c.en or ""):lower():find(q, 1, true) ~= nil);
					local vis = okGroup and okText;
					flp.visible = vis;

					if vis then
						groupHasVisible[c.group] = true;
					end;
				end;
			end);

			for _, g in ipairs(FSCOND_DATA.groups) do
				local hdr = self["grpHdr_" .. g.id];

				if hdr ~= nil then
					hdr.visible = groupHasVisible[g.id] == true;
				end;
			end;
		end;

		-- info = {title, current = {[id] = {r = "3", h = "1"}}, customs = {..},
		--         onApply = function(result), onClearAll = function()}
		function self:prepareFor(info)
			options = info or {};
			self:beginUpdate();
			self.labTitle.text = options.title or "Condições";
			local cur = options.current or {};

			eachCondition(function(c)
				local e = cur[c.id];
				self["cbx_" .. c.id].checked = e ~= nil;
				self["edt_" .. c.id].text = (e ~= nil and e.r) or "";
				self["cmbU_" .. c.id].value = (e ~= nil and e.u) or "r";
			end);

			local names = {};

			for _, cu in ipairs(options.customs or {}) do
				local txt = cu.n or "?";

				if cu.d ~= nil then
					txt = txt .. " (" .. cu.d .. ")";
				end;

				names[#names + 1] = txt;
			end;

			if #names > 0 then
				self.labCustoms.text = "Personalizadas: " .. table.concat(names, ", ");
			else
				self.labCustoms.text = "Nenhuma condição personalizada.";
			end;

			self.edtCustomName.text = "";
			self.edtCustomRounds.text = "";
			self.edtSearch.text = "";
			self:applyFilter();
			self:endUpdate();
		end;

		function self:collect()
			local result = {list = {}, hidden = self.cbxHidden.checked == true};

			eachCondition(function(c)
				if self["cbx_" .. c.id].checked then
					result.list[#result.list + 1] = {id = c.id, r = self["edt_" .. c.id].text or "",
					                                 u = self["cmbU_" .. c.id].value or "r"};
				end;
			end);

			return result;
		end;

		function self:doApply()
			if options.onApply ~= nil then
				options.onApply(self:collect());
			end;

			self:closeMe();
		end;

		function self:doAddCustom()
			local name = self.edtCustomName.text or "";

			if name:gsub("%s", "") == "" then
				showMessage("Digite um nome para a condição personalizada.");
				return;
			end;

			if options.onAddCustom ~= nil then
				options.onAddCustom({n = name, r = self.edtCustomRounds.text or "", u = self.cmbCustomUnit.value or "r",
				                     c = self.cmbCustomColor.color},
				                    self:collect());
			end;

			self:closeMe();
		end;

		function self:doClearCustoms()
			if options.onClearCustoms ~= nil then
				options.onClearCustoms(self:collect());
			end;

			self:closeMe();
		end;

		function self:doClearAll()
			if options.onClearAll ~= nil then
				options.onClearAll();
			end;

			self:closeMe();
		end;

		function self:setAllRounds()
			local v = self.edtAllRounds.text or "";
			local u = self.cmbAllUnit.value or "r";

			eachCondition(function(c)
				if self["cbx_" .. c.id].checked then
					self["edt_" .. c.id].text = v;
					self["cmbU_" .. c.id].value = u;
				end;
			end);
		end;
	]]></script>

	<!-- Botões sempre visíveis -->
	<layout align="bottom" height="40" margins="{left=6, right=6, bottom=4}">
		<horzLine align="top" strokeColor="#FFFFFF40"/>
		<button align="right" width="96" text="Aplicar" fontStyle="bold" margins="{left=4, top=6}"
		        onClick="self:doApply()"/>
		<button align="right" width="90" text="Cancelar" margins="{left=4, top=6}" onClick="self:closeMe()"/>
		<button align="right" width="110" text="Remover todas" margins="{left=4, top=6}" onClick="self:doClearAll()"/>
	</layout>

	<!-- Todo o resto rola e se reorganiza conforme a largura do painel -->
	<scrollBox align="client" margins="{left=4, right=2, top=4}">
		<flowLayout name="flaTiles" align="top" autoHeight="true" margins="{right=6}">
			<flowPart minWidth="240" maxWidth="5000" height="26" margins="{left=4, right=4}">
				<label name="labTitle" align="client" fontSize="16" fontStyle="bold" text="Condições" wordWrap="false"/>
			</flowPart>
			<flowLineBreak/>

			<flowPart width="236" height="30" margins="{left=2, right=2}">
				<label left="2" top="2" width="50" height="26" text="Buscar:" vertTextAlign="center"/>
				<edit name="edtSearch" left="54" top="2" width="176" height="26" textPrompt="nome da condição"
				      onChange="self:applyFilter()"/>
			</flowPart>
			<flowPart width="216" height="30" margins="{left=2, right=2}">
				<label left="2" top="2" width="58" height="26" text="Mostrar:" vertTextAlign="center"/>
				<comboBox name="cmbFilter" left="62" top="2" width="148" height="26"
				          items="{'Todas', 'Pathfinder 1e', 'Magias e efeitos', 'FFd20'}"
				          values="{'all', 'pf', 'buff', 'ff'}" value="all" onChange="self:applyFilter()"/>
			</flowPart>
			<flowPart width="312" height="30" margins="{left=2, right=2}">
				<label left="2" top="2" width="104" height="26" text="Duração p/ marcadas:" fontSize="11"
				       vertTextAlign="center" wordWrap="true"/>
				<edit name="edtAllRounds" left="108" top="2" width="44" height="26" textPrompt="&#8734;" horzTextAlign="center"/>
				<comboBox name="cmbAllUnit" left="156" top="2" width="84" height="26"
				          items="{'rodadas', 'minutos', 'horas'}" values="{'r', 'min', 'h'}" value="r"/>
				<button left="244" top="2" width="62" height="26" text="Aplicar" onClick="self:setAllRounds()"/>
			</flowPart>
			<flowPart width="236" height="30" margins="{left=2, right=2}">
				<checkBox name="cbxHidden" left="2" top="2" width="230" height="26" text="Novas condições só p/ o mestre"/>
			</flowPart>
			<flowLineBreak/>

<!--@TILES@-->

			<flowPart minWidth="240" maxWidth="5000" height="30" margins="{left=4, right=4, top=8}">
				<label align="client" text="Condição personalizada" fontSize="15" fontStyle="bold" fontColor="#FFCC66"/>
				<horzLine align="bottom" strokeColor="#FFCC6670"/>
			</flowPart>
			<flowLineBreak/>
			<flowPart width="296" height="30" margins="{left=2, right=2}">
				<edit name="edtCustomName" left="2" top="2" width="224" height="26" textPrompt="Ex.: Marcado pelo Inquisidor"/>
				<colorComboBox name="cmbCustomColor" left="230" top="2" width="60" height="26" color="#00838F" useAlpha="false"/>
			</flowPart>
			<flowPart width="236" height="30" margins="{left=2, right=2}">
				<edit name="edtCustomRounds" left="2" top="2" width="44" height="26" textPrompt="&#8734;" horzTextAlign="center"/>
				<comboBox name="cmbCustomUnit" left="50" top="2" width="84" height="26"
				          items="{'rodadas', 'minutos', 'horas'}" values="{'r', 'min', 'h'}" value="r"/>
				<button left="138" top="2" width="92" height="26" text="Adicionar" onClick="self:doAddCustom()"/>
			</flowPart>
			<flowPart width="126" height="30" margins="{left=2, right=2}">
				<button left="2" top="2" width="118" height="26" text="Limpar pers." onClick="self:doClearCustoms()"/>
			</flowPart>
			<flowLineBreak/>
			<flowPart minWidth="240" maxWidth="5000" height="22" margins="{left=4, right=4}">
				<label name="labCustoms" align="client" fontSize="11" fontColor="#B0BEC5" wordWrap="false"/>
			</flowPart>
			<flowLineBreak/>
			<flowPart minWidth="240" maxWidth="5000" height="34" margins="{left=4, right=4, bottom=6}">
				<label align="client" fontSize="11" fontColor="#B0BEC5" wordWrap="true"
				       text="Duração vazia = indefinida. 1 minuto = 10 rodadas; 1 hora = 600 rodadas. O avanço de rodada desconta de todas."/>
			</flowPart>
		</flowLayout>
	</scrollBox>
</popupForm>
