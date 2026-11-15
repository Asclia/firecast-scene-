--[[
  Scene Suite - biblioteca compartilhada (fsCommon.lua)

  Este arquivo é COPIADO para dentro de cada plugin da suíte pelo script
  tools/build.py (cada plugin roda em sua própria sandbox e não enxerga
  arquivos dos outros). Edite sempre a versão em /common e rode o build.

  Contém apenas lógica pura (unidades, distâncias, geometria, caminhos SVG)
  e alguns utilitários de canvas. Nada aqui depende de um plugin específico.
]]

FSC = FSC or {};
local FSC = FSC;

FSC.VERSION = "1.0.0";

local floor, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt;
local sin, cos, rad, max, min = math.sin, math.cos, math.rad, math.max, math.min;

----------------------------------------------------------------------
-- Texto / serialização simples (userData guarda só textos planos)
----------------------------------------------------------------------

function FSC.trim(s)
	s = tostring(s or "");
	return (s:gsub("^%s+", ""):gsub("%s+$", ""));
end;

local function escapeField(s)
	return (tostring(s):gsub("[%%;=|]", function(c) return string.format("%%%02X", string.byte(c)); end));
end;

local function unescapeField(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)); end));
end;

-- Codifica uma tabela plana {k = v} (v: string/número/booleano) em "k=v;k=v"
function FSC.encode(t)
	local parts = {};

	for k, v in pairs(t or {}) do
		local tv = type(v);

		if tv == "boolean" then
			v = v and "1" or "0";
		end;

		if tv == "string" or tv == "number" or tv == "boolean" then
			parts[#parts + 1] = escapeField(k) .. "=" .. escapeField(v);
		end;
	end;

	table.sort(parts);
	return table.concat(parts, ";");
end;

function FSC.decode(s)
	local t = {};

	if type(s) ~= "string" then
		return t;
	end;

	for pair in s:gmatch("[^;]+") do
		local k, v = pair:match("^([^=]*)=(.*)$");

		if k ~= nil then
			t[unescapeField(k)] = unescapeField(v);
		end;
	end;

	return t;
end;

-- Lista de tabelas planas <-> texto ("registro|registro")
function FSC.encodeList(list)
	local parts = {};

	for i = 1, #(list or {}) do
		parts[#parts + 1] = escapeField(FSC.encode(list[i]));
	end;

	return table.concat(parts, "|");
end;

function FSC.decodeList(s)
	local list = {};

	if type(s) ~= "string" or s == "" then
		return list;
	end;

	for rec in s:gmatch("[^|]+") do
		list[#list + 1] = FSC.decode(unescapeField(rec));
	end;

	return list;
end;

function FSC.toBool(v, default)
	if v == nil or v == "" then
		return default == true;
	end;

	return v == true or v == "1" or v == "true" or v == 1;
end;

----------------------------------------------------------------------
-- Unidades: ft / m / quadrados
----------------------------------------------------------------------

-- Convenção de Pathfinder / D&D em português: 5 ft = 1,5 m (fator 0,3)
FSC.METERS_PER_FOOT = 0.3;

local UNIT_ALIASES = {
	ft = "ft", ["pé"] = "ft", ["pés"] = "ft", ["pÉs"] = "ft", pe = "ft", pes = "ft", feet = "ft", foot = "ft", ["'"] = "ft",
	m = "m", mt = "m", mts = "m", metro = "m", metros = "m", meter = "m", meters = "m",
	q = "sq", sq = "sq", quad = "sq", quads = "sq", quadrado = "sq", quadrados = "sq",
	square = "sq", squares = "sq", c = "sq", cel = "sq", celula = "sq", celulas = "sq",
	["célula"] = "sq", ["células"] = "sq",
	cm = "cm", km = "km"
};

function FSC.normalizeUnit(u)
	u = FSC.trim(u):lower();

	if u == "" then
		return nil;
	end;

	return UNIT_ALIASES[u];
end;

-- Quantos pés vale um quadrado do grid deste scene.
-- Usa grid.cellSize + scene.worldMetricName (configuração do tabuleiro).
function FSC.feetPerSquare(scene)
	local cs = 1.5;
	local metric = nil;

	if scene ~= nil then
		local grid = scene.grid;

		if grid ~= nil and type(grid.cellSize) == "number" and grid.cellSize > 0 then
			cs = grid.cellSize;
		end;

		metric = FSC.normalizeUnit(scene.worldMetricName);
	end;

	if metric == "m" then
		return cs / FSC.METERS_PER_FOOT;
	elseif metric == "ft" then
		return cs;
	elseif metric == "cm" then
		return cs / (FSC.METERS_PER_FOOT * 100);
	elseif metric == "km" then
		return cs / (FSC.METERS_PER_FOOT / 1000);
	else
		-- Métrica desconhecida/vazia: assume 1 quadrado = 5 ft (padrão PF)
		return 5;
	end;
end;

function FSC.cellSize(scene)
	if scene ~= nil and scene.grid ~= nil then
		local cs = scene.grid.cellSize;

		if type(cs) == "number" and cs > 0 then
			return cs;
		end;
	end;

	return 1.5;
end;

-- Interpreta "20", "20ft", "20 pés", "6m", "6 metros", "4q", "4 quadrados", "7,5 m"
-- Retorna: quadrados (float), pés (float)  -- ou nil se inválido
function FSC.parseDistance(text, scene, defaultUnit)
	local s = FSC.trim(text):lower():gsub(",", ".");
	local num, unit = s:match("^([%d%.]+)%s*(.-)$");
	num = tonumber(num);

	if num == nil or num < 0 then
		return nil;
	end;

	local u;

	if FSC.trim(unit) == "" then
		u = defaultUnit or "ft";
	else
		u = FSC.normalizeUnit(unit);
	end;

	if u == nil then
		return nil;
	end;

	local fps = FSC.feetPerSquare(scene);
	local feet;

	if u == "ft" then
		feet = num;
	elseif u == "m" then
		feet = num / FSC.METERS_PER_FOOT;
	elseif u == "sq" then
		feet = num * fps;
	elseif u == "cm" then
		feet = num / (FSC.METERS_PER_FOOT * 100);
	elseif u == "km" then
		feet = num / (FSC.METERS_PER_FOOT / 1000);
	end;

	return feet / fps, feet;
end;

local function fmtNum(n)
	if abs(n - floor(n + 0.5)) < 0.01 then
		return tostring(floor(n + 0.5));
	end;

	return (string.format("%.1f", n):gsub("%.", ","));
end;

FSC.fmtNum = fmtNum;

-- "20 ft (6 m)"
function FSC.formatFeet(feet)
	return fmtNum(feet) .. " ft (" .. fmtNum(feet * FSC.METERS_PER_FOOT) .. " m)";
end;

----------------------------------------------------------------------
-- Distância no grid
----------------------------------------------------------------------

-- mode: "pf" / "alternated" (5-10-5), "simplified" (diagonal = 1),
--       "manhattan" (diagonal = 2), "euclidean"
function FSC.gridDist(dx, dy, mode)
	dx, dy = abs(dx), abs(dy);
	local mx, mn = max(dx, dy), min(dx, dy);

	if mode == "manhattan" then
		return dx + dy;
	elseif mode == "simplified" then
		return mx;
	elseif mode == "euclidean" then
		return sqrt(dx * dx + dy * dy);
	else
		return mx + floor(mn / 2);
	end;
end;

-- Resolve qual regra de diagonal usar. pref = "pf" (padrão) | "board"
function FSC.diagMode(scene, pref)
	if pref == "board" and scene ~= nil and scene.grid ~= nil then
		local m = scene.grid.squareDiagonals;

		if m == "simplified" or m == "manhattan" or m == "euclidean" or m == "alternated" then
			return m;
		end;
	end;

	return "alternated";
end;

----------------------------------------------------------------------
-- Direções: graus, 0 = para cima (norte), sentido horário
----------------------------------------------------------------------

function FSC.dirVector(angleDeg)
	local a = rad(angleDeg or 0);
	return sin(a), -cos(a);
end;

function FSC.angleOf(dx, dy)
	if dx == 0 and dy == 0 then
		return 0;
	end;

	local a = math.deg(math.atan(dx, -dy));

	if a < 0 then
		a = a + 360;
	end;

	return a;
end;

local function angleDiff(a, b)
	local d = (a - b) % 360;

	if d > 180 then
		d = d - 360;
	end;

	return abs(d);
end;

FSC.angleDiff = angleDiff;

-- Arredonda para múltiplos de "step" graus (cones de PF costumam ser 45°)
function FSC.snapAngle(a, step)
	step = step or 45;
	return (floor(a / step + 0.5) * step) % 360;
end;

----------------------------------------------------------------------
-- Conjuntos de células
-- Coordenadas "de célula": a = coluna, b = linha; a célula (a,b) ocupa
-- [a, a+1] x [b, b+1]. A origem é sempre um retângulo alinhado ao grid
-- (0,0)-(w,h); w = h = 0 significa uma interseção do grid (ponto).
----------------------------------------------------------------------

local function newCellSet()
	return {list = {}, map = {}};
end;

local function addCell(set, a, b)
	local k = a .. "," .. b;

	if not set.map[k] then
		set.map[k] = true;
		set.list[#set.list + 1] = {a, b};
	end;
end;

FSC.newCellSet = newCellSet;
FSC.addCell = addCell;

local function rectDelta(a, w)
	if a < 0 then
		return -a;
	elseif a >= w then
		return a - w + 1;
	else
		return 0;
	end;
end;

--[[ Células dentro do alcance de um retângulo de origem (w x h células).
  opts.maxR    : alcance máximo em quadrados (ex.: 4 = 20 ft)
  opts.minR    : células com distância <= minR são excluídas (arma de haste)
  opts.mode    : regra de diagonais (ver gridDist)
  opts.reach10 : aplica a exceção de 10 ft de PF (alcança 2 diagonais)
  opts.filter  : função(cx, cy) -> bool, centro da célula relativo à origem
  opts.includeInside : inclui as células ocupadas pela própria origem ]]
function FSC.cellsInRange(w, h, opts)
	local set = newCellSet();
	local maxR = opts.maxR or 0;
	local minR = opts.minR or 0;
	local mode = opts.mode or "alternated";
	local R = ceil(maxR) + 1;
	local eps = 1e-6;

	for b = -R, h + R - 1 do
		for a = -R, w + R - 1 do
			local dx = rectDelta(a, w);
			local dy = rectDelta(b, h);
			local ok;

			if dx == 0 and dy == 0 then
				ok = opts.includeInside == true;
			else
				local d = FSC.gridDist(dx, dy, mode);

				if opts.reach10 and maxR >= 2 and maxR < 3 and dx == 2 and dy == 2 then
					d = 2;
				end;

				ok = (d <= maxR + eps) and (d > minR + eps);
			end;

			if ok and opts.filter ~= nil then
				ok = opts.filter(a + 0.5, b + 0.5);
			end;

			if ok then
				addCell(set, a, b);
			end;
		end;
	end;

	return set;
end;

-- Cone de PF (quarto de círculo, 90°) a partir de um retângulo de origem.
function FSC.cellsCone(w, h, opts)
	local cx, cy = w / 2, h / 2;
	local dir = opts.angle or 0;
	local half = (opts.coneAngle or 90) / 2 + 0.01;
	local o = {};

	for k, v in pairs(opts) do o[k] = v; end;

	o.filter = function(x, y)
		return angleDiff(FSC.angleOf(x - cx, y - cy), dir) <= half;
	end;

	return FSC.cellsInRange(w, h, o);
end;

-- Linha a partir do ponto (ox, oy) (coordenadas de célula, float).
-- Marca todas as células por onde a linha passa (amostragem densa).
function FSC.cellsLine(ox, oy, angle, lengthSq, widthSq)
	local set = newCellSet();
	local dx, dy = FSC.dirVector(angle);
	local px, py = -dy, dx;
	local nW = max(1, floor((widthSq or 1) + 0.5));
	local step = 0.05;

	for k = 0, nW - 1 do
		local off = (k - (nW - 1) / 2);
		local t = step;

		while t <= lengthSq + 1e-6 do
			-- desloca levemente para fora de quinas exatas
			local x = ox + dx * t + px * off + 1e-4;
			local y = oy + dy * t + py * off + 1e-4;
			addCell(set, floor(x), floor(y));
			t = t + step;
		end;
	end;

	return set;
end;

-- Quadrado/cubo com uma quina na interseção (ox, oy), crescendo para o
-- quadrante indicado pelo ângulo.
function FSC.cellsSquare(ox, oy, angle, sideSq)
	local set = newCellSet();
	local dx, dy = FSC.dirVector(angle);
	local s = max(1, floor(sideSq + 0.5));
	local a0 = (dx >= -1e-6) and ox or (ox - s);
	local b0 = (dy >= -1e-6) and oy or (oy - s);

	for b = 0, s - 1 do
		for a = 0, s - 1 do
			addCell(set, floor(a0 + a + 0.5), floor(b0 + b + 0.5));
		end;
	end;

	return set;
end;

-- Desloca um conjunto de células
function FSC.shiftCells(set, da, db)
	local out = newCellSet();

	for i = 1, #set.list do
		addCell(out, set.list[i][1] + da, set.list[i][2] + db);
	end;

	return out;
end;

----------------------------------------------------------------------
-- Caminhos (path data no padrão SVG)
----------------------------------------------------------------------

local function n2s(n)
	local s = string.format("%.3f", n);
	s = s:gsub("0+$", ""):gsub("%.$", "");

	if s == "-0" then
		s = "0";
	end;

	return s;
end;

FSC.n2s = n2s;

-- bbox de um conjunto de células: minX, minY, maxX, maxY
function FSC.cellsBBox(set)
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge;

	for i = 1, #set.list do
		local a, b = set.list[i][1], set.list[i][2];
		x1 = min(x1, a); y1 = min(y1, b);
		x2 = max(x2, a + 1); y2 = max(y2, b + 1);
	end;

	if x1 == math.huge then
		return nil;
	end;

	return {x1, y1, x2, y2};
end;

--[[ Converte células em dois caminhos:
     fill    - retângulos (corridas horizontais) para preenchimento
     outline - apenas as bordas externas, segmentos mesclados
  ox, oy: deslocamento subtraído de todas as coordenadas. ]]
function FSC.cellsToPaths(set, ox, oy)
	ox, oy = ox or 0, oy or 0;
	local rows = {};

	for i = 1, #set.list do
		local a, b = set.list[i][1], set.list[i][2];
		rows[b] = rows[b] or {};
		table.insert(rows[b], a);
	end;

	local fill = {};

	for b, cols in pairs(rows) do
		table.sort(cols);
		local i = 1;

		while i <= #cols do
			local s = cols[i];
			local e = s;

			while cols[i + 1] == e + 1 do
				i = i + 1;
				e = cols[i];
			end;

			fill[#fill + 1] = "M" .. n2s(s - ox) .. " " .. n2s(b - oy) ..
			                  "H" .. n2s(e + 1 - ox) .. "V" .. n2s(b + 1 - oy) ..
			                  "H" .. n2s(s - ox) .. "Z";
			i = i + 1;
		end;
	end;

	-- Bordas: horizontais agrupadas por y, verticais agrupadas por x
	local map = set.map;
	local hEdges, vEdges = {}, {};

	local function has(a, b) return map[a .. "," .. b] == true; end;

	for i = 1, #set.list do
		local a, b = set.list[i][1], set.list[i][2];

		if not has(a, b - 1) then
			hEdges[b] = hEdges[b] or {}; table.insert(hEdges[b], a);
		end;

		if not has(a, b + 1) then
			hEdges[b + 1] = hEdges[b + 1] or {}; table.insert(hEdges[b + 1], a);
		end;

		if not has(a - 1, b) then
			vEdges[a] = vEdges[a] or {}; table.insert(vEdges[a], b);
		end;

		if not has(a + 1, b) then
			vEdges[a + 1] = vEdges[a + 1] or {}; table.insert(vEdges[a + 1], b);
		end;
	end;

	local outline = {};

	local function emitRuns(groups, horizontal)
		for fixed, starts in pairs(groups) do
			table.sort(starts);
			local i = 1;

			while i <= #starts do
				local s = starts[i];
				local e = s;

				while starts[i + 1] == e + 1 do
					i = i + 1;
					e = starts[i];
				end;

				if horizontal then
					outline[#outline + 1] = "M" .. n2s(s - ox) .. " " .. n2s(fixed - oy) .. "H" .. n2s(e + 1 - ox);
				else
					outline[#outline + 1] = "M" .. n2s(fixed - ox) .. " " .. n2s(s - oy) .. "V" .. n2s(e + 1 - oy);
				end;

				i = i + 1;
			end;
		end;
	end;

	emitRuns(hEdges, true);
	emitRuns(vEdges, false);

	return table.concat(fill, ""), table.concat(outline, "");
end;

-- Lista de polígonos {{x,y},...} -> path data e bbox
function FSC.polysToPath(polys, closed)
	local parts = {};
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge;

	for p = 1, #polys do
		local poly = polys[p];

		for i = 1, #poly do
			local x, y = poly[i][1], poly[i][2];
			x1 = min(x1, x); y1 = min(y1, y); x2 = max(x2, x); y2 = max(y2, y);
			parts[#parts + 1] = ((i == 1) and "M" or "L") .. n2s(x) .. " " .. n2s(y);
		end;

		if closed ~= false then
			parts[#parts + 1] = "Z";
		end;
	end;

	if x1 == math.huge then
		return "", nil;
	end;

	return table.concat(parts, ""), {x1, y1, x2, y2};
end;

-- Retângulo arredondado (soma de Minkowski de um retângulo hw x hh com um
-- círculo de raio r), centrado em (0,0). hw = hh = 0 => círculo.
function FSC.roundRectPoly(hw, hh, r, segsPerQuarter)
	local segs = segsPerQuarter or 12;
	local pts = {};
	local corners = {{hw, -hh, -90}, {hw, hh, 0}, {-hw, hh, 90}, {-hw, -hh, 180}};

	for c = 1, 4 do
		local cx, cy, a0 = corners[c][1], corners[c][2], corners[c][3];

		for s = 0, segs do
			local a = rad(a0 + 90 * s / segs);
			pts[#pts + 1] = {cx + r * cos(a), cy + r * sin(a)};
		end;
	end;

	return pts;
end;

function FSC.circlePoly(cx, cy, r, segs)
	segs = segs or 48;
	local pts = {};

	for s = 0, segs - 1 do
		local a = 2 * math.pi * s / segs;
		pts[#pts + 1] = {cx + r * cos(a), cy + r * sin(a)};
	end;

	return pts;
end;

function FSC.reversePoly(p)
	local out = {};

	for i = #p, 1, -1 do
		out[#out + 1] = p[i];
	end;

	return out;
end;

-- Cone: vértice em (ax, ay), comprimento len, abertura coneAngle (graus)
function FSC.conePoly(ax, ay, angle, len, coneAngle, segs)
	segs = segs or 24;
	coneAngle = coneAngle or 90;
	local pts = {{ax, ay}};

	for s = 0, segs do
		local a = angle - coneAngle / 2 + coneAngle * s / segs;
		local dx, dy = FSC.dirVector(a);
		pts[#pts + 1] = {ax + dx * len, ay + dy * len};
	end;

	return pts;
end;

-- Retângulo de uma linha a partir de (ox, oy)
function FSC.linePoly(ox, oy, angle, len, width)
	local dx, dy = FSC.dirVector(angle);
	local px, py = -dy * width / 2, dx * width / 2;
	return {{ox + px, oy + py}, {ox + dx * len + px, oy + dy * len + py},
	        {ox + dx * len - px, oy + dy * len - py}, {ox - px, oy - py}};
end;

-- Quadrado com quina em (ox, oy) crescendo para o quadrante do ângulo
function FSC.squarePoly(ox, oy, angle, side)
	local dx, dy = FSC.dirVector(angle);
	local x0 = (dx >= -1e-6) and ox or (ox - side);
	local y0 = (dy >= -1e-6) and oy or (oy - side);
	return {{x0, y0}, {x0 + side, y0}, {x0 + side, y0 + side}, {x0, y0 + side}};
end;

----------------------------------------------------------------------
-- Cores
----------------------------------------------------------------------

-- Retorna a cor com alpha "a" (0..1). Usa as funções do SDK quando
-- disponíveis (aceitam nomes como "Red"); senão trata "#RRGGBB".
function FSC.withAlpha(color, a)
	a = max(0, min(1, a or 1));
	color = color or "#FFFFFF";

	if colorToRGBA ~= nil and RGBAToColor ~= nil then
		local ok, r, g, b = pcall(colorToRGBA, color);

		if ok and r ~= nil then
			return RGBAToColor(r, g, b, a);
		end;
	end;

	local hex = tostring(color):match("^#?(%x%x%x%x%x%x)");

	if hex == nil then
		hex = "FFFFFF";
	end;

	return "#" .. hex .. string.format("%02X", floor(a * 255 + 0.5));
end;

-- Cores padrão por "lado" do token
FSC.FOF_COLORS = {
	foe = "#E53935",
	friend = "#1E88E5",
	neutral = "#FDD835",
	unknown = "#B0BEC5"
};

function FSC.colorForToken(token)
	local fof = "unknown";

	if token ~= nil then
		local ok, v = pcall(function() return token.friendOrFoe; end);

		if ok and v ~= nil then
			fof = v;
		end;
	end;

	return FSC.FOF_COLORS[fof] or FSC.FOF_COLORS.unknown;
end;

----------------------------------------------------------------------
-- Canvas / Scene
----------------------------------------------------------------------

function FSC.startsWith(s, prefix)
	return type(s) == "string" and s:sub(1, #prefix) == prefix;
end;

-- Remove todas as operações gráficas cujo nome começa com prefix
function FSC.removeOps(canvas, prefix)
	if canvas == nil then
		return;
	end;

	for i = canvas.opCount - 1, 0, -1 do
		local op = canvas:getOp(i);

		if op ~= nil and FSC.startsWith(op.name, prefix) then
			op:delete();
		end;
	end;
end;

function FSC.hasOps(canvas, prefix)
	if canvas == nil then
		return false;
	end;

	for i = canvas.opCount - 1, 0, -1 do
		local op = canvas:getOp(i);

		if op ~= nil and FSC.startsWith(op.name, prefix) then
			return true;
		end;
	end;

	return false;
end;

local function applyCommonOpProps(op, o)
	local metric = o.metric or "cellMetric";
	op.xMetric = metric;
	op.yMetric = metric;
	op.widthMetric = metric;
	op.heightMetric = metric;
	op.xOrigin = o.xOrigin or 0.5;
	op.yOrigin = o.yOrigin or 0.5;
	op.z = o.z or 0;
	op.opacity = o.opacity or 1.0;
	op.rotMode = o.rotMode or "ignoreCanvasRot";
	op.outOfOrderMode = o.outOfOrderMode or "noOutOfOrder";
	op.visibility = o.visibility or "everyone";
	op.drawingTrigger = o.trigger or {};
end;

--[[ Adiciona um path ao canvas. bbox = {x1, y1, x2, y2} nas coordenadas do
  path; a operação é posicionada exatamente sobre o bbox (o Firecast ajusta
  o path às dimensões da operação, então bbox do path = caixa da operação). ]]
function FSC.addPathOp(canvas, name, pathData, bbox, o)
	o = o or {};
	local op = canvas:addPath();
	op.name = name;
	applyCommonOpProps(op, o);
	op.x = bbox[1];
	op.y = bbox[2];
	op.width = max(bbox[3] - bbox[1], 0.001);
	op.height = max(bbox[4] - bbox[2], 0.001);
	op.color = o.fill or "#00000000";
	op.strokeColor = o.stroke or "#00000000";
	op.strokeSize = o.strokeSize or 0;
	op.strokeSizeMetric = o.strokeSizeMetric or "screenMetric";
	op.strokeJoin = o.strokeJoin or "round";
	op.strokeCap = o.strokeCap or "flat";
	op.strokeDash = o.strokeDash or "solid";
	op.data = pathData;
	return op;
end;

-- Texto com altura h (na métrica escolhida); largura calculada pelo aspecto.
-- align: "center" (x é o centro), "leading" (x é a esquerda), "trailing"
function FSC.addTextOp(canvas, name, text, x, y, h, o)
	o = o or {};
	local op = canvas:addText();
	op.name = name;
	applyCommonOpProps(op, o);
	op.text = text;
	op.color = o.color or "#FFFFFF";
	op.fontStyle = o.fontStyle or {"bold"};
	op.horzTextAlign = "center";
	op.vertTextAlign = "center";

	local aspect = op.aspect;

	if type(aspect) ~= "number" or aspect <= 0 then
		aspect = max(1, #tostring(text) * 0.55);
	end;

	local w = h * aspect;
	local left = x;

	if (o.align or "center") == "center" then
		left = x - w / 2;
	elseif o.align == "trailing" then
		left = x - w;
	end;

	op.x = left;
	op.y = y;
	op.width = w;
	op.height = h;
	return op, w;
end;

-- Dimensões do token em quadrados e o deslocamento do centro em relação à
-- célula do grid (para posicionar células relativas ao centro do token).
function FSC.tokenGridInfo(scene, item)
	local cs = FSC.cellSize(scene);
	local grid = scene.grid;
	local gx, gy = grid:cellToWorld(0, 0); -- centro da célula (linha 0, coluna 0)
	-- cellToWorld(i, j): i = linha, j = coluna
	gx, gy = gx - cs / 2, gy - cs / 2;

	local w = item.width / cs;
	local h = item.height / cs;
	local x = (item.x - gx) / cs;
	local y = (item.y - gy) / cs;

	-- células ocupadas (arredondadas) - tokens menores que 1 quadrado
	-- ocupam 1 quadrado para efeito de alcance
	local wi = max(1, floor(w + 0.5));
	local hi = max(1, floor(h + 0.5));
	local cx, cy = x + w / 2, y + h / 2;
	local a0 = floor(cx - wi / 2 + 0.5);
	local b0 = floor(cy - hi / 2 + 0.5);

	return {
		cs = cs, gx = gx, gy = gy,
		w = w, h = h, wi = wi, hi = hi,
		cx = cx, cy = cy,         -- centro do token em coordenadas de célula
		a0 = a0, b0 = b0           -- canto superior-esquerdo da área ocupada
	};
end;

-- Origem do grid em métrica de mundo (canto superior esquerdo da célula 0,0)
function FSC.gridOrigin(scene)
	local cs = FSC.cellSize(scene);
	local gx, gy = scene.grid:cellToWorld(0, 0);
	return gx - cs / 2, gy - cs / 2, cs;
end;

function FSC.worldToCellCoords(scene, wx, wy)
	local gx, gy, cs = FSC.gridOrigin(scene);
	return (wx - gx) / cs, (wy - gy) / cs;
end;

function FSC.cellCoordsToWorld(scene, a, b)
	local gx, gy, cs = FSC.gridOrigin(scene);
	return gx + a * cs, gy + b * cs;
end;

function FSC.isSquareGrid(scene)
	return scene.grid == nil or scene.grid.gridType == nil or scene.grid.gridType == "square";
end;

-- Pode editar o item? (mestre ou dono)
function FSC.canEdit(scene, item)
	if scene.isGM then
		return true;
	end;

	local ok, mine = pcall(function() return item.isMine; end);
	return ok and mine == true;
end;

-- Tokens selecionados (apenas tokens)
function FSC.selectedTokens(scene)
	local out = {};
	local sel = scene.items.selection or {};

	for i = 1, #sel do
		if sel[i] ~= nil and sel[i].objectType == "token" then
			out[#out + 1] = sel[i];
		end;
	end;

	return out;
end;

function FSC.allTokens(scene)
	local out = {};
	local items = scene.items;

	for i = 1, #items do
		local it = items[i];

		if it ~= nil and it.objectType == "token" then
			out[#out + 1] = it;
		end;
	end;

	return out;
end;

function FSC.tokenAt(scene, screenX, screenY)
	local wx, wy = scene.viewport:screenToWorld(screenX, screenY);
	local list = scene.items:enumAtPoint(wx, wy, "tokens");

	for i = #list, 1, -1 do
		if list[i].objectType == "token" then
			return list[i], wx, wy;
		end;
	end;

	return nil, wx, wy;
end;

-- Escreve uma mensagem local no chat da mesa (só para quem executou)
function FSC.chatLocal(scene, text)
	local ok = pcall(function()
		local mesa = Firecast.getMesaDe(scene);

		if mesa ~= nil and mesa.chat ~= nil then
			mesa.chat:escrever(text);
		end;
	end);

	return ok;
end;

function FSC.isSpectator(scene)
	local ok, r = pcall(function()
		local mesa = Firecast.getMesaDe(scene);
		return mesa ~= nil and mesa.meuJogador ~= nil and mesa.meuJogador.isEspectador;
	end);

	return ok and r == true;
end;

-- Agenda fn (debounce por chave)
local _debounces = {};

function FSC.debounce(key, ms, fn)
	local h = _debounces[key];

	if h ~= nil then
		clearTimeout(h);
	end;

	_debounces[key] = setTimeout(function()
		_debounces[key] = nil;
		fn();
	end, ms);
end;

----------------------------------------------------------------------
-- Áreas ao redor de tokens (usado por Auras e Alcance)
----------------------------------------------------------------------

--[[ Calcula a geometria de uma área ao redor de um token.
  spec.shape  : "emanation" | "square" | "cone" | "line"
  spec.maxSq  : alcance em quadrados (a partir da borda do token)
  spec.minSq  : (opcional) não inclui células até esta distância
  spec.widthSq: largura da linha (quadrados)
  spec.angle  : direção em graus (0 = cima, horário)
  spec.followFacing : direção relativa à rotação do token
  spec.mode   : "grid" (células, regra do PF) | "smooth" (forma geométrica)
  spec.diag   : regra de diagonal (ver FSC.gridDist)
  spec.reach10: exceção de 10 ft
  Retorna {fill=path, outline=path|nil, bbox={...}, rotMode=...} com
  coordenadas em quadrados relativas ao CENTRO do token. ]]
function FSC.tokenAreaGeometry(scene, token, spec)
	local info = FSC.tokenGridInfo(scene, token);
	local shape = spec.shape or "emanation";
	local maxSq = spec.maxSq or 1;
	local minSq = spec.minSq or 0;
	local angle = spec.angle or 0;
	local mode = spec.mode or "grid";
	local rotMode = "ignoreCanvasRot";

	if not FSC.isSquareGrid(scene) then
		mode = "smooth";
	end;

	if spec.followFacing then
		if mode == "grid" then
			angle = angle + (token.rotation or 0);
		else
			rotMode = "default";
		end;
	end;

	if mode == "grid" then
		local set;
		local wi, hi = info.wi, info.hi;

		if shape == "cone" then
			set = FSC.cellsCone(wi, hi, {maxR = maxSq, minR = minSq, mode = spec.diag, angle = angle});
		elseif shape == "line" then
			local dx, dy = FSC.dirVector(angle);
			local startX, startY = wi / 2, hi / 2;
			local extra = max(wi, hi) / 2;
			set = FSC.cellsLine(startX + dx * extra * 0.999, startY + dy * extra * 0.999, angle, maxSq, spec.widthSq or 1);
		elseif shape == "square" then
			set = FSC.cellsInRange(wi, hi, {maxR = maxSq, minR = minSq, mode = "simplified",
			                                includeInside = minSq <= 0});
		else
			-- inclui os quadrados do próprio token (sem "buraco" contornado no meio),
			-- exceto quando há alcance mínimo (arma de haste)
			set = FSC.cellsInRange(wi, hi, {maxR = maxSq, minR = minSq, mode = spec.diag, reach10 = spec.reach10,
			                                includeInside = minSq <= 0});
		end;

		if #set.list == 0 then
			return nil;
		end;

		-- células relativas ao canto do token -> relativas ao centro
		local ox = info.cx - info.a0;
		local oy = info.cy - info.b0;
		local fill, outline = FSC.cellsToPaths(set, ox, oy);
		local bb = FSC.cellsBBox(set);
		return {fill = fill, outline = outline,
		        bbox = {bb[1] - ox, bb[2] - oy, bb[3] - ox, bb[4] - oy},
		        rotMode = rotMode, cells = #set.list};
	else
		local hw, hh = info.w / 2, info.h / 2;
		local polys;

		if shape == "cone" then
			polys = {FSC.conePoly(0, 0, angle, maxSq + max(hw, hh), spec.coneAngle or 90, 32)};
		elseif shape == "line" then
			polys = {FSC.linePoly(0, 0, angle, maxSq + max(hw, hh), spec.widthSq or 1)};
		elseif shape == "square" then
			local R = maxSq;
			polys = {{{-hw - R, -hh - R}, {hw + R, -hh - R}, {hw + R, hh + R}, {-hw - R, hh + R}}};

			if minSq > 0 then
				local r = minSq;
				table.insert(polys, {{-hw - r, -hh - r}, {-hw - r, hh + r}, {hw + r, hh + r}, {hw + r, -hh - r}});
			end;
		else
			polys = {FSC.roundRectPoly(hw, hh, maxSq, 16)};

			if minSq > 0 then
				table.insert(polys, FSC.reversePoly(FSC.roundRectPoly(hw, hh, minSq, 16)));
			end;
		end;

		local data, bbox = FSC.polysToPath(polys, true);

		if bbox == nil then
			return nil;
		end;

		return {fill = data, outline = nil, bbox = bbox, rotMode = rotMode};
	end;
end;

--[[ Desenha (persistindo no canvas do token) uma área.
  prefix: prefixo dos nomes das operações (as antigas com o mesmo prefixo
          são removidas antes)
  style.color, style.fillAlpha, style.lineAlpha, style.lineWidth,
  style.lineDash, style.visibility ("everyone"|"gmOnly"),
  style.trigger ({} | {"hover","selected"}), style.z, style.label ]]
function FSC.renderTokenArea(scene, token, prefix, spec, style)
	local canvas = token.canvas;
	FSC.removeOps(canvas, prefix);

	if spec == nil then
		return true;
	end;

	local geo = FSC.tokenAreaGeometry(scene, token, spec);

	if geo == nil then
		return false;
	end;

	local color = style.color or "#FFFFFF";
	local fillC = FSC.withAlpha(color, style.fillAlpha or 0.2);
	local lineC = FSC.withAlpha(color, style.lineAlpha or 0.8);
	local common = {
		z = style.z or -10,
		rotMode = geo.rotMode,
		outOfOrderMode = style.outOfOrderMode or "beforeOwnerLayer",
		visibility = style.visibility or "everyone",
		trigger = style.trigger or {}
	};

	local function opts(extra)
		local o = {};
		for k, v in pairs(common) do o[k] = v; end;
		for k, v in pairs(extra) do o[k] = v; end;
		return o;
	end;

	if geo.outline ~= nil then
		FSC.addPathOp(canvas, prefix .. "fill", geo.fill, geo.bbox, opts({fill = fillC}));

		if (style.lineAlpha or 0.8) > 0 and (style.lineWidth or 2) > 0 then
			FSC.addPathOp(canvas, prefix .. "line", geo.outline, geo.bbox,
				opts({stroke = lineC, strokeSize = style.lineWidth or 2, strokeDash = style.lineDash or "solid",
				      strokeCap = "round", z = common.z + 1}));
		end;
	else
		local lw = style.lineWidth or 2;

		if (style.lineAlpha or 0.8) <= 0 then
			lw = 0;
		end;

		FSC.addPathOp(canvas, prefix .. "fill", geo.fill, geo.bbox,
			opts({fill = fillC, stroke = lineC, strokeSize = lw, strokeDash = style.lineDash or "solid"}));
	end;

	if style.label ~= nil and style.label ~= "" then
		local h = 0.28;
		local y = geo.bbox[2] - h - 0.05;
		FSC.addTextOp(canvas, prefix .. "label", style.label, 0, y, h,
			opts({color = FSC.withAlpha(color, 1), z = common.z + 2,
			      trigger = {"hover", "selected"}, outOfOrderMode = "afterOwnerLayer"}));
	end;

	return true;
end;

-- Observa mudanças de tamanho/posição/rotação dos tokens (com debounce).
-- fn(token) é chamada ~400 ms depois da última mudança.
function FSC.watchTokenBounds(scene, key, fn)
	local hooked = {};

	local function hook(item)
		if item == nil or item.objectType ~= "token" then
			return;
		end;

		local id = item.objectID;

		if hooked[id] then
			return;
		end;

		hooked[id] = item:listen("onBoundsChange", function()
			FSC.debounce(key .. id, 400, function()
				if item.isObjectAlive then
					fn(item);
				end;
			end);
		end);
	end;

	for _, t in ipairs(FSC.allTokens(scene)) do
		hook(t);
	end;

	scene.items:listen("onItemAdded", function(item)
		hook(item);
	end);

	scene.items:listen("onItemRemoved", function(item)
		if item ~= nil then
			hooked[item.objectID] = nil;
		end;
	end);
end;

-- Assinatura geométrica do token (para saber se precisa redesenhar)
function FSC.tokenSignature(scene, token, withRotation)
	local info = FSC.tokenGridInfo(scene, token);
	local fx = info.cx - math.floor(info.cx);
	local fy = info.cy - math.floor(info.cy);
	local s = string.format("%.3f|%.3f|%.2f|%.2f", info.w, info.h, fx, fy);

	if withRotation then
		s = s .. "|" .. string.format("%.1f", token.rotation or 0);
	end;

	return s;
end;

return FSC;
