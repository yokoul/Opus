-- PageBanque.lua : la participation de chacun à la banque de guilde (or, réparations, objets), par période
local _, Opus = ...

local LIGNES, HAUTEUR, ENTETE = 16, 20, 22
local lignes, decalage = {}, 0
local periode, tri, croissant = 7, "orPlus", false
local entetes = {}
local TIRET = GRAY_FONT_COLOR:WrapTextInColorCode("–")

-- colonnes : clé de tri, titre, x, largeur, alignement, texte d'une ligne
local COLONNES = {
	{ "nom",      "Membre",       2,   134, "LEFT" },
	{ "grade",    "Grade",        140, 84,  "LEFT" },
	{ "orPlus",   "Or déposé",    226, 78,  "RIGHT", function (p) return Opus.Or(p.orPlus) end },
	{ "orMoins",  "Or retiré",    306, 74,  "RIGHT", function (p) return Opus.Or(p.orMoins) end },
	{ "rep",      "Réparations",  382, 84,  "RIGHT", function (p) return Opus.Or(p.rep) end },
	{ "objPlus",  "Obj. déposés", 468, 80,  "RIGHT", function (p) return p.objPlus > 0 and p.objPlus or TIRET end },
	{ "objMoins", "Obj. retirés", 550, 78,  "RIGHT", function (p) return p.objMoins > 0 and p.objMoins or TIRET end },
	{ "dernier",  "Dernière",     630, 60,  "RIGHT", function (p) return Opus.Depuis(p.dernier) end },
}

-- bilan de la période, avec le grade et la classe de ceux encore dans la guilde
local function Liste ()
	local membres = {}
	for _, m in ipairs(Opus.Membres()) do membres[m.nom] = m end
	local liste = Opus.Participation(periode)
	for _, p in ipairs(liste) do
		local m = membres[p.nom]
		p.grade, p.classe, p.parti = m and m.nomGrade or "", m and m.classe, m == nil
	end
	table.sort(liste, function (a, b)
		local x, y = a[tri], b[tri]
		if x == y then return a.nom < b.nom end
		if croissant then return x < y end
		return x > y
	end)
	return liste
end

local function Bulle (l)
	local p, lignesBulle = l.p, {}
	for i, e in ipairs(p.ev) do
		if i > 12 then lignesBulle[#lignesBulle + 1] = Opus.Gris(("… et %d autre(s)"):format(#p.ev - 12)) break end
		lignesBulle[#lignesBulle + 1] = Opus.Operation(e)
	end
	return lignesBulle
end

local function Rafraichir (cadre)
	cadre.periode:GenerateMenu()
	for _, h in ipairs(entetes) do
		h.fleche:SetShown(h.cle == tri)
		if croissant then h.fleche:SetTexCoord(0, 1, 1, 0) else h.fleche:SetTexCoord(0, 1, 0, 1) end
	end
	local banque = Opus.db.banque
	cadre.info:SetText(banque.releve > 0
		and ("relevé il y a %s · %d opérations · partagé avec %d membre(s)"):format(Opus.Depuis(math.floor(banque.releve / 3600)), #banque.evenements, Opus.Pairs())
		or Opus.Rouge("jamais relevée : passe à la banque de guilde"))

	local liste = Liste()
	decalage = math.max(0, math.min(decalage, #liste - LIGNES))
	local totaux = { orPlus = 0, orMoins = 0, rep = 0, objPlus = 0, objMoins = 0, dernier = 0 }
	for _, p in ipairs(liste) do
		for k in pairs(totaux) do totaux[k] = k == "dernier" and math.max(totaux[k], p[k]) or totaux[k] + p[k] end
	end
	for i = 1, LIGNES do
		local l, p = lignes[i], liste[i + decalage]
		l:SetShown(p ~= nil)
		if p then
			l.p = p
			for c, col in ipairs(COLONNES) do
				local texte
				if col[1] == "nom" then texte = p.parti and Opus.Gris(p.nom) or (Opus.Couleur(p.classe) .. p.nom .. "|r")
				elseif col[1] == "grade" then texte = p.parti and Opus.Gris("parti") or p.grade
				else texte = col[6](p) end
				l.cases[c]:SetText(texte)
			end
		end
	end

	local n = math.min(#liste, LIGNES)
	cadre.vide:SetShown(#liste == 0)
	cadre.total:SetShown(#liste > 0)
	cadre.total:SetPoint("TOPLEFT", 0, -ENTETE - n * HAUTEUR - 4)
	if #liste > 0 then
		totaux.nom = "Total (" .. #liste .. ")"
		for c, col in ipairs(COLONNES) do
			local texte = col[1] == "nom" and totaux.nom or (col[1] == "grade" and "" or col[6](totaux))
			cadre.total.cases[c]:SetText(texte)
		end
	end
	cadre.aide:SetPoint("TOPLEFT", 2, -ENTETE - math.max(n, 1) * HAUTEUR - (#liste > 0 and 30 or 8))
	return ENTETE + math.max(n, 1) * HAUTEUR + (#liste > 0 and 30 or 8) + 30
end

local function Cases (l)
	l.cases = {}
	for c, col in ipairs(COLONNES) do
		local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("LEFT", col[3], 0) t:SetWidth(col[4]) t:SetJustifyH(col[5]) t:SetWordWrap(false)
		l.cases[c] = t
	end
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	-- la période, en menu du client ; « Tout » vaut 0 (le menu ne garde pas nil)
	cadre.periode = Opus.Menu(barre, 130, { { 7, "7 derniers jours" }, { 30, "30 derniers jours" }, { 0, "Depuis le début" } },
		function () return periode or 0 end,
		function (v) periode = v > 0 and v or nil Opus.Rafraichir() end)
	cadre.periode:SetPoint("LEFT", 0, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	-- en-têtes cliquables : un clic trie, un second inverse
	for c, col in ipairs(COLONNES) do
		local h = CreateFrame("Button", nil, cadre)
		h:SetSize(col[4], 18)
		h:SetPoint("TOPLEFT", col[3], 0)
		h.texte = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.texte:SetPoint(col[5]) h.texte:SetText(col[2])
		-- la flèche se met du côté libre du titre
		h.fleche = h:CreateTexture(nil, "OVERLAY")
		h.fleche:SetAtlas("auctionhouse-ui-sortarrow", true)
		if col[5] == "LEFT" then h.fleche:SetPoint("LEFT", h.texte, "RIGHT", 3, 0)
		else h.fleche:SetPoint("RIGHT", h.texte, "LEFT", -3, 0) end
		h.cle = col[1]
		h:SetScript("OnClick", function (self)
			if tri == self.cle then croissant = not croissant
			else tri, croissant = self.cle, (self.cle == "nom" or self.cle == "grade") end
			Opus.Rafraichir()
		end)
		Opus.Survol(h)
		entetes[c] = h
	end

	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -ENTETE - (i - 1) * HAUTEUR)
		l:EnableMouse(true)
		Opus.Survol(l)
		Cases(l)
		Opus.Bulle(l, function (self) return Opus.Couleur(self.p.classe) .. self.p.nom .. "|r" end, Bulle)
		lignes[i] = l
	end

	cadre.total = CreateFrame("Frame", nil, cadre)
	cadre.total:SetSize(largeur, HAUTEUR)
	Cases(cadre.total)
	for _, t in ipairs(cadre.total.cases) do t:SetFontObject("GameFontNormalSmall") end

	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", 4, -ENTETE - 3)
	cadre.vide:SetText("Rien sur cette période.")

	cadre.aide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.aide:SetWidth(largeur - 4) cadre.aide:SetJustifyH("LEFT")
	cadre.aide:SetText("Relevé à chaque ouverture de la banque de guilde et partagé avec les membres qui ont l'addon : il suffit que "
		.. "l'un d'eux passe à la banque. Le jeu n'y garde que les dernières opérations, alors plus elle est ouverte souvent, "
		.. "plus le bilan est complet. Survole un membre pour le détail.")
end

Opus.Page("banque", "Banque", Construire, Rafraichir, function (_, d) decalage = decalage - d end)
