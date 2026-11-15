<?xml version="1.0" encoding="UTF-8"?>
<!-- ARQUIVO GERADO por tools/build.py a partir de tools/templates/frmFSConditions.lfm.tpl. Edite o template. -->
<popupForm name="frmFSConditions" width="740" height="580" drawContainer="true" resizable="true"
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

		function self:applyFilter()
			local f = self.cmbFilter.value or "all";

			for _, g in ipairs(FSCOND_DATA.groups) do
				local hdr = self["grpHdr_" .. g.id];

				if hdr ~= nil then
					hdr.visible = (f == "all") or (f == g.id);
				end;
			end;

			eachCondition(function(c)
				local flp = self["flp_" .. c.id];

				if flp ~= nil then
					flp.visible = (f == "all") or (f == c.group);
				end;
			end);
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
			end);

			local names = {};

			for _, cu in ipairs(options.customs or {}) do
				local txt = cu.n or "?";

				if cu.r ~= nil and cu.r ~= "" then
					txt = txt .. " (" .. cu.r .. ")";
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
			self:applyFilter();
			self:endUpdate();
		end;

		function self:collect()
			local result = {list = {}, hidden = self.cbxHidden.checked == true};

			eachCondition(function(c)
				if self["cbx_" .. c.id].checked then
					result.list[#result.list + 1] = {id = c.id, r = self["edt_" .. c.id].text or ""};
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
				options.onAddCustom({n = name, r = self.edtCustomRounds.text or "", c = self.cmbCustomColor.color},
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

			eachCondition(function(c)
				if self["cbx_" .. c.id].checked then
					self["edt_" .. c.id].text = v;
				end;
			end);
		end;
	]]></script>

	<layout align="top" height="66" margins="{left=8, right=8, top=6}">
		<label name="labTitle" left="0" top="0" width="720" height="24" fontSize="16" fontStyle="bold"
		       text="Condições" wordWrap="false"/>
		<label left="0" top="32" width="50" height="26" text="Mostrar:" vertTextAlign="center"/>
		<comboBox name="cmbFilter" left="52" top="32" width="150" height="26"
		          items="{'Todas', 'Pathfinder 1e', 'Magias e efeitos', 'FFd20'}"
		          values="{'all', 'pf', 'buff', 'ff'}" value="all" onChange="self:applyFilter()"/>
		<label left="214" top="32" width="160" height="26" text="Duração p/ marcadas:" vertTextAlign="center"
		       horzTextAlign="trailing"/>
		<edit name="edtAllRounds" left="378" top="32" width="48" height="26" textPrompt="&#8734;" horzTextAlign="center"/>
		<button left="430" top="32" width="64" height="26" text="Aplicar" onClick="self:setAllRounds()"/>
		<checkBox name="cbxHidden" left="508" top="32" width="220" height="26"
		          text="Novas condições só p/ o mestre"/>
	</layout>

	<layout align="bottom" height="104" margins="{left=8, right=8, bottom=6}">
		<horzLine align="top" strokeColor="#FFFFFF40"/>
		<label left="0" top="8" width="180" height="26" text="Condição personalizada:" vertTextAlign="center"/>
		<edit name="edtCustomName" left="180" top="8" width="210" height="26" textPrompt="Ex.: Marcado pelo Inquisidor"/>
		<colorComboBox name="cmbCustomColor" left="396" top="8" width="60" height="26" color="#00838F" useAlpha="false"/>
		<edit name="edtCustomRounds" left="462" top="8" width="60" height="26" textPrompt="rodadas" horzTextAlign="center"/>
		<button left="528" top="8" width="90" height="26" text="Adicionar" onClick="self:doAddCustom()"/>
		<button left="622" top="8" width="100" height="26" text="Limpar pers." onClick="self:doClearCustoms()"/>
		<label name="labCustoms" left="0" top="38" width="720" height="22" fontSize="11" fontColor="#B0BEC5"
		       wordWrap="false"/>
		<label left="0" top="66" width="330" height="30" fontSize="11" fontColor="#B0BEC5" wordWrap="true"
		       text="Duração em rodadas (vazio = indefinida). Aceita 1min = 10 rodadas, 1h = 600."/>
		<button left="402" top="66" width="110" height="30" text="Remover todas" onClick="self:doClearAll()"/>
		<button left="518" top="66" width="100" height="30" text="Cancelar" onClick="self:closeMe()"/>
		<button left="622" top="66" width="100" height="30" text="Aplicar" fontStyle="bold" onClick="self:doApply()"/>
	</layout>

	<scrollBox align="client" margins="{left=4, right=4}">
		<flowLayout name="flaTiles" align="top" autoHeight="true" margins="{right=4}">
<!--@TILES@-->
		</flowLayout>
	</scrollBox>
</popupForm>
