-- PageContenu.lua : les vues « Contenu » et « Journal » de l'onglet Banque (Contenu.lua, Banque.lua)
-- Contenu : les objets des onglets photographiés, en grille comme la banque (un onglet) ou en liste, à chercher par nom, par onglet, ou « pour moi » (ce que sa classe peut
-- porter à son niveau, mieux que ce qu'il porte ; Pawn décide s'il est installé). L'infobulle est celle de l'objet.
-- Journal : les entrées et sorties de la banque, objets et or, de la plus récente à la plus ancienne.
local _, Opus = ...

local HAUTEUR, LIGNES = 20, 14
local decalages = { contenu = 0, journal = 0 }
local recherche, onglet, pourMoi, genre, mode = "", 0, false, "objets", "grille"
local CASE, ECART = 36, 8              -- la grille : 98 cases, 7 groupes de 2 colonnes sur 7 rangs, comme la banque
local LIBELLES = { ["or+"] = "dépôt", ["or-"] = "retrait", rep = "réparations", ong = "achat d'onglet", ["obj+"] = "dépôt", ["obj-"] = "retrait" }

local function Qualite (id)
	local q = GetItemInfo and select(3, GetItemInfo(id))
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and c.hex or "|cffffffff"
end

local function Icone (id)
	local i = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
	return i and ("|T" .. i .. ":16|t ") or ""
end

local function NomOnglet (tab, o)
	return (o and o.nom) or Opus.ONGLETS[tab] or ("Onglet " .. tab)
end

local function Cherche (texte)
	return recherche == "" or (texte and texte:lower():find(recherche, 1, true)) ~= nil
end

------------------------------------------------------------------------
-- données
------------------------------------------------------------------------

-- { id, n, tab, nom, utile } ; « pour moi » : les améliorations d'abord
local function Objets ()
	local liste = {}
	for tab, o in pairs(Opus.OngletsBanque()) do
		if onglet == 0 or onglet == tab then
			for id, n in pairs(o.objets) do
				local nom = Opus.NomObjet(id) or ("objet " .. id)
				if Cherche(nom) then
					local utile = pourMoi and Opus.UtilePourMoi(id)
					if not pourMoi or utile then liste[#liste + 1] = { id = id, n = n, tab = tab, nom = nom, utile = utile } end
				end
			end
		end
	end
	table.sort(liste, function (a, b)
		local ra, rb = a.utile and a.utile[1] or 0, b.utile and b.utile[1] or 0
		if ra ~= rb then return ra > rb end
		if a.nom ~= b.nom then return a.nom < b.nom end
		return a.tab < b.tab
	end)
	return liste
end

local function Operations ()
	local liste = {}
	for _, e in ipairs(Opus.db.banque.evenements) do
		local objet = e.q == "obj+" or e.q == "obj-"
		if (genre == "tout" or (genre == "objets") == objet) and (onglet == 0 or e.tab == onglet)
			and (Cherche(e.nom) or Cherche(e.o) or (e.id and Cherche(Opus.NomObjet(e.id)))) then
			liste[#liste + 1] = e
		end
	end
	table.sort(liste, function (a, b) return a.t > b.t end)
	return liste
end

------------------------------------------------------------------------
-- la vue
------------------------------------------------------------------------

local COL_CONTENU = { { "Objet", 2, 300 }, { "Quantité", 306, 60, "RIGHT" }, { "Onglet", 380, 110 }, { "Pour toi", 494, 190 } }
local COL_JOURNAL = { { "Quand", 2, 54 }, { "Joueur", 60, 130 }, { "Opération", 194, 90 }, { "Quoi", 288, 280 }, { "Onglet", 572, 110 } }

local function Ligne (parent, largeur)
	local l = CreateFrame("Button", nil, parent)
	l:SetSize(largeur, HAUTEUR)
	Opus.Survol(l)
	l.cases = {}
	for c = 1, 5 do
		local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetWordWrap(false)
		l.cases[c] = t
	end
	return l
end

local function Colonnes (l, colonnes)
	for c, t in ipairs(l.cases) do
		local col = colonnes[c]
		t:SetShown(col ~= nil)
		if col then t:ClearAllPoints() t:SetPoint("LEFT", col[2], 0) t:SetWidth(col[3]) t:SetJustifyH(col[4] or "LEFT") end
	end
end

local function BulleObjet (self)
	local id = self.id
	if not id then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. id)
	if self.detail then
		GameTooltip:AddLine(" ")
		for _, d in ipairs(self.detail) do GameTooltip:AddLine(d, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
	end
	GameTooltip:Show()
end

function Opus.ConstruireContenu (parent, largeur)
	local v = CreateFrame("Frame", nil, parent)
	v:SetPoint("TOPLEFT") v:SetPoint("TOPRIGHT") v:SetHeight(1)

	-- filtres : recherche, onglet, « pour moi » (contenu) ou genre (journal)
	v.recherche = CreateFrame("EditBox", nil, v, "SearchBoxTemplate")
	v.recherche:SetSize(200, 20) v.recherche:SetPoint("TOPLEFT", 8, -2)
	v.recherche:SetAutoFocus(false)
	v.recherche:HookScript("OnTextChanged", function (self)
		recherche = strtrim(self:GetText() or ""):lower()
		decalages.contenu, decalages.journal = 0, 0
		Opus.Rafraichir()
	end)
	v.onglet = CreateFrame("DropdownButton", nil, v, "WowStyle1DropdownTemplate")
	v.onglet:SetWidth(150) v.onglet:SetPoint("LEFT", v.recherche, "RIGHT", 12, 0)
	v.onglet:SetupMenu(function (_, racine)
		racine:CreateRadio("Tous les onglets", function () return onglet == 0 end, function () onglet = 0 Opus.Rafraichir() end)
		local banque = Opus.OngletsBanque()
		for tab = 1, 8 do
			local o = banque[tab]
			if o or Opus.ONGLETS[tab] then
				racine:CreateRadio(NomOnglet(tab, o), function () return onglet == tab end, function () onglet = tab Opus.Rafraichir() end)
			end
		end
	end)
	v.pourMoi = CreateFrame("CheckButton", nil, v, "UICheckButtonTemplate")
	v.pourMoi:SetSize(24, 24) v.pourMoi:SetPoint("LEFT", v.onglet, "RIGHT", 12, 0)
	local t = v.pourMoi.Text or v.pourMoi.text
	if t then t:SetText("Pour moi") t:SetFontObject("GameFontHighlightSmall") end
	v.pourMoi:SetScript("OnClick", function (self) pourMoi = self:GetChecked() and true or false decalages.contenu = 0 Opus.Rafraichir() end)
	Opus.Bulle(v.pourMoi, "Pour moi", "Ce que ta classe peut porter à ton niveau (ou dans 5 niveaux) et qui vaut mieux que ce que tu portes : "
		.. "d'après Pawn s'il est installé, sinon d'après le niveau d'objet.")
	v.mode = Opus.Menu(v, 90, { { "grille", "Grille" }, { "liste", "Liste" } }, function () return mode end,
		function (x) mode = x Opus.Rafraichir() end)
	v.mode:SetPoint("TOPRIGHT", -2, 0)
	v.grille = CreateFrame("Frame", nil, v)
	v.grille:SetSize(14 * CASE + 6 * ECART, 7 * CASE)
	v.grille:SetPoint("TOP", 0, -34)
	v.cases = {}
	for case = 1, 98 do
		local b = CreateFrame("Button", nil, v.grille)
		b:SetSize(CASE - 2, CASE - 2)
		local groupe, dans = math.floor((case - 1) / 14), (case - 1) % 14
		local x = (groupe * 2 + math.floor(dans / 7)) * CASE + groupe * ECART
		b:SetPoint("TOPLEFT", x, -(dans % 7) * CASE)
		b.fond = b:CreateTexture(nil, "BACKGROUND")
		b.fond:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
		b.fond:SetPoint("TOPLEFT", -9, 9) b.fond:SetPoint("BOTTOMRIGHT", 9, -9)
		b.icone = b:CreateTexture(nil, "ARTWORK")
		b.icone:SetAllPoints()
		b.bord = b:CreateTexture(nil, "OVERLAY")
		b.bord:SetTexture("Interface\\Common\\WhiteIconFrame")
		b.bord:SetAllPoints()
		b.nombre = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.nombre:SetPoint("BOTTOMRIGHT", -2, 2)
		local h = b:CreateTexture(nil, "HIGHLIGHT")
		h:SetTexture("Interface\\Buttons\\ButtonHilight-Square") h:SetBlendMode("ADD") h:SetAllPoints()
		b:SetScript("OnEnter", BulleObjet)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", function (self)
			if self.id and IsModifiedClick and IsModifiedClick("CHATLINK") then
				local _, lien = GetItemInfo(self.id)
				if lien and ChatEdit_InsertLink then ChatEdit_InsertLink(lien) end
			end
		end)
		v.cases[case] = b
	end
	v.legende = v:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	v.legende:SetPoint("TOPLEFT", v.grille, "BOTTOMLEFT", 0, -6)
	v.genre = Opus.Menu(v, 120, { { "objets", "Objets" }, { "or", "Or" }, { "tout", "Tout" } },
		function () return genre end, function (x) genre = x decalages.journal = 0 Opus.Rafraichir() end)
	v.genre:SetPoint("LEFT", v.onglet, "RIGHT", 12, 0)

	v.entetes = {}
	for c = 1, 5 do
		local h = v:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		v.entetes[c] = h
	end
	v.lignes = {}
	for i = 1, LIGNES do
		local l = Ligne(v, largeur)
		l:SetPoint("TOPLEFT", 0, -50 - (i - 1) * HAUTEUR)
		l:SetScript("OnEnter", BulleObjet)
		l:SetScript("OnLeave", GameTooltip_Hide)
		-- maj-clic : le lien de l'objet dans la discussion
		l:SetScript("OnClick", function (self)
			if self.id and IsModifiedClick and IsModifiedClick("CHATLINK") then
				local _, lien = GetItemInfo(self.id)
				if lien and ChatEdit_InsertLink then ChatEdit_InsertLink(lien) end
			end
		end)
		v.lignes[i] = l
	end
	v.ascenseur = Opus.Ascenseur(v, function (d) decalages[v.vue] = d Opus.Rafraichir() end)
	v.ascenseur:SetPoint("TOPRIGHT", -2, -50)
	v.vide = v:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	v.vide:SetPoint("TOPLEFT", 4, -53)
	v.aide = v:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	v.aide:SetWidth(largeur - 4) v.aide:SetJustifyH("LEFT")
	return v
end

local function Entetes (v, colonnes)
	for c, h in ipairs(v.entetes) do
		local col = colonnes[c]
		h:SetShown(col ~= nil)
		if col then h:ClearAllPoints() h:SetPoint("TOPLEFT", col[2], -32) h:SetWidth(col[3]) h:SetJustifyH(col[4] or "LEFT") h:SetText(col[1]) end
	end
end

-- sans photo : demandée à la guilde (Contenu.lua) ; sinon, il faut que quelqu'un passe à la banque
local function AucunePhoto ()
	if Opus.ContenuDemande() then return Opus.Gris("aucune photo : demandée aux membres en ligne, elle arrive dans quelques secondes") end
	return Opus.Rouge("aucune photo : passe à la banque de guilde")
end

local function RemplirContenu (v, info)
	local liste = Objets()
	local banque, plusVieille, n = Opus.OngletsBanque(), nil, 0
	for _, o in pairs(banque) do n = n + 1 plusVieille = plusVieille and math.min(plusVieille, o.t) or o.t end
	info:SetText(n > 0 and ("%d onglet(s) · photo la plus ancienne il y a %s"):format(n, Opus.Depuis(math.floor(plusVieille / 3600)))
		or AucunePhoto())
	Entetes(v, COL_CONTENU)
	local d = math.max(0, math.min(decalages.contenu, #liste - LIGNES))
	decalages.contenu = d
	for i, l in ipairs(v.lignes) do
		local x = liste[i + d]
		l:SetShown(x ~= nil)
		Colonnes(l, COL_CONTENU)
		if x then
			local o = banque[x.tab]
			l.id = x.id
			l.detail = { ("%s · photo il y a %s par %s"):format(NomOnglet(x.tab, o), Opus.Depuis(math.floor(o.t / 3600)), o.par or "?"),
				Opus.Gris("Maj-clic : le lien dans la discussion.") }
			l.cases[1]:SetText(Icone(x.id) .. Qualite(x.id) .. x.nom .. "|r")
			l.cases[2]:SetText(x.n)
			l.cases[3]:SetText(NomOnglet(x.tab, o))
			l.cases[4]:SetText(x.utile and (x.utile[1] == 3 and Opus.Vert(x.utile[2]) or x.utile[1] == 2 and Opus.Normal(x.utile[2]) or Opus.Gris(x.utile[2])) or "")
		end
	end
	v.vide:SetText(n == 0 and "Aucune photo de la banque pour l'instant." or pourMoi and "Rien qui te serve ici, pour l'instant." or "Aucun objet.")
	v.aide:SetText("Le contenu de chaque onglet est photographié quand un membre qui a l'addon ouvre la banque, puis partagé à la guilde. "
		.. "Tu ne vois que les onglets que ton grade peut voir.")
	return liste
end

-- la grille d'un onglet : l'onglet choisi, ou le premier ; recherche et « pour moi » éteignent ce qui ne correspond pas
local function RemplirGrille (v, info)
	local banque, tab = Opus.OngletsBanque(), onglet
	if tab == 0 or not banque[tab] then
		tab = nil
		for t in pairs(banque) do if not tab or t < tab then tab = t end end
	end
	local o = tab and banque[tab]
	info:SetText(o and ("%s · photo il y a %s par %s"):format(NomOnglet(tab, o), Opus.Depuis(math.floor(o.t / 3600)), o.par or "?")
		or AucunePhoto())
	local filtre, trouves = recherche ~= "" or pourMoi, 0
	for case, b in ipairs(v.cases) do
		local x = o and o.cases and o.cases[case]
		b.id = x and x[1]
		b.detail = x and { NomOnglet(tab, o), Opus.Gris("Maj-clic : le lien dans la discussion.") } or nil
		b.icone:SetShown(x ~= nil) b.bord:SetShown(x ~= nil) b.nombre:SetShown(x ~= nil and x[2] > 1)
		b:SetAlpha(1)
		if x then
			local icone = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(x[1])) or (GetItemIcon and GetItemIcon(x[1]))
			b.icone:SetTexture(icone or "Interface\\Icons\\INV_Misc_QuestionMark")
			b.nombre:SetText(x[2])
			local q = GetItemInfo and select(3, GetItemInfo(x[1]))
			local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
			b.bord:SetShown(c ~= nil)
			if c then b.bord:SetVertexColor(c.r, c.g, c.b) end
			if filtre then
				local utile = pourMoi and Opus.UtilePourMoi(x[1])
				local ok = Cherche(Opus.NomObjet(x[1])) and (not pourMoi or utile)
				if utile then b.detail[#b.detail + 1] = Opus.Vert("Pour toi : " .. utile[2]) end
				if ok then trouves = trouves + 1 else b:SetAlpha(0.2) end
			end
		end
	end
	v.legende:SetText(o and not o.cases and "Photo d'une version précédente, sans les cases : elle se refait au prochain passage à la banque."
		or filtre and ("%d objet(s) correspondent."):format(trouves) or "")
end

local function RemplirJournal (v, info)
	local liste = Operations()
	info:SetText(("%d opération(s)"):format(#liste))
	Entetes(v, COL_JOURNAL)
	local d = math.max(0, math.min(decalages.journal, #liste - LIGNES))
	decalages.journal = d
	for i, l in ipairs(v.lignes) do
		local e = liste[i + d]
		l:SetShown(e ~= nil)
		Colonnes(l, COL_JOURNAL)
		if e then
			l.id, l.detail = e.id, nil
			local m = Opus.TrouverMembre(e.nom)
			local entre = e.q == "obj+" or e.q == "or+"
			l.cases[1]:SetText(Opus.Depuis(e.t))
			l.cases[2]:SetText(m and (Opus.Couleur(m.classe) .. e.nom .. "|r") or Opus.Gris(e.nom))
			l.cases[3]:SetText((entre and Opus.Vert or (e.q == "ong" or e.q == "rep") and Opus.Gris or Opus.Rouge)(LIBELLES[e.q] or e.q))
			l.cases[4]:SetText(e.c and Opus.OrDetail(e.c) or (e.n .. " × " .. (e.id and Icone(e.id) .. Qualite(e.id) or "") .. (e.o or Opus.NomObjet(e.id) or "?") .. "|r"))
			l.cases[5]:SetText(e.tab and NomOnglet(e.tab, Opus.OngletsBanque()[e.tab]) or "")
		end
	end
	v.vide:SetText("Aucune opération.")
	v.aide:SetText("Les journaux de la banque, relevés à chaque ouverture et partagés à la guilde ; le jeu ne garde que les dernières "
		.. "opérations de chaque onglet. Les déplacements d'un onglet à l'autre n'y figurent pas.")
	return liste
end

-- vue = « contenu » ou « journal » ; renvoie la hauteur utile
function Opus.RafraichirContenu (v, vue, info)
	v.vue = vue
	if vue == "contenu" then Opus.DemanderContenu() end
	v.pourMoi:SetShown(vue == "contenu")
	v.pourMoi:SetChecked(pourMoi)
	v.genre:SetShown(vue == "journal")
	v.genre:GenerateMenu()
	v.onglet:GenerateMenu()
	local grille = vue == "contenu" and mode == "grille"
	v.mode:SetShown(vue == "contenu")
	v.mode:GenerateMenu()
	v.grille:SetShown(grille)
	v.legende:SetShown(grille)
	for _, h in ipairs(v.entetes) do h:SetShown(not grille) end
	if grille then
		for _, l in ipairs(v.lignes) do l:Hide() end
		v.ascenseur:Hide() v.vide:Hide()
		RemplirGrille(v, info)
		local y = 34 + 7 * CASE + 26
		v.aide:SetPoint("TOPLEFT", 2, -y)
		v.aide:SetText("Le contenu de chaque onglet est photographié quand un membre qui a l'addon ouvre la banque, puis partagé à la guilde. "
			.. "Tu ne vois que les onglets que ton grade peut voir.")
		local h = v.aide:GetStringHeight()
		return y + math.ceil(type(h) == "number" and h or 36) + 8
	end
	local liste = vue == "contenu" and RemplirContenu(v, info) or RemplirJournal(v, info)
	local n = math.min(#liste, LIGNES)
	v.ascenseur:SetHeight(math.max(n, 1) * HAUTEUR)
	v.ascenseur:Recaler(decalages[vue], #liste, LIGNES)
	v.vide:SetShown(#liste == 0)
	local y = 50 + math.max(n, 1) * HAUTEUR + 10
	v.aide:SetPoint("TOPLEFT", 2, -y)
	local h = v.aide:GetStringHeight()
	return y + math.ceil(type(h) == "number" and h or 36) + 8
end

function Opus.MoletteContenu (vue, d) decalages[vue] = decalages[vue] - d end
