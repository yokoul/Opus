-- PageBanque.lua : la participation de chacun à la banque de guilde (or, réparations, objets), par période
local _, Opus = ...

local LIGNES, HAUTEUR, ENTETE = 14, 20, 52
local lignes, decalage = {}, 0
local periode, tri, croissant = 7, "orPlus", false
local periodes, entetes = {}, {}

-- colonnes : clé de tri, titre, x, largeur, alignement, texte d'une ligne
local COLONNES = {
	{ "nom",      "Membre",       2,   150, "LEFT" },
	{ "grade",    "Grade",        154, 80,  "LEFT" },
	{ "orPlus",   "Or déposé",    236, 78,  "RIGHT", function (p) return Opus.Or(p.orPlus) end },
	{ "orMoins",  "Or retiré",    316, 78,  "RIGHT", function (p) return Opus.Or(p.orMoins) end },
	{ "rep",      "Réparations",  396, 82,  "RIGHT", function (p) return Opus.Or(p.rep) end },
	{ "objPlus",  "Obj. déposés", 480, 66,  "RIGHT", function (p) return p.objPlus > 0 and p.objPlus or "|cff666666–|r" end },
	{ "objMoins", "Obj. retirés", 548, 66,  "RIGHT", function (p) return p.objMoins > 0 and p.objMoins or "|cff666666–|r" end },
	{ "dernier",  "Dernière",     616, 74,  "RIGHT", function (p) return Opus.Depuis(p.dernier) end },
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
		if i > 12 then lignesBulle[#lignesBulle + 1] = ("|cffaaaaaa… et %d autre(s)|r"):format(#p.ev - 12) break end
		lignesBulle[#lignesBulle + 1] = Opus.Operation(e)
	end
	return lignesBulle
end

local function Rafraichir (cadre)
	for _, b in ipairs(periodes) do
		if b.jours == periode then Opus.Choisir(periodes, b) end
	end
	for _, h in ipairs(entetes) do
		h.texte:SetText(h.titre .. (h.cle == tri and (croissant and " ^" or " v") or ""))
	end
	local banque = Opus.db.banque
	cadre.info:SetText(banque.releve > 0
		and ("relevé il y a %s · %d opérations en mémoire"):format(Opus.Depuis(math.floor(banque.releve / 3600)), #banque.evenements)
		or "|cffff6060jamais relevée|r")

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
				if col[1] == "nom" then texte = (p.parti and "|cff888888" or Opus.Couleur(p.classe)) .. p.nom .. "|r"
				elseif col[1] == "grade" then texte = p.parti and "|cff888888parti|r" or p.grade
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

local function Construire (cadre)
	local largeur = Opus.LARGEUR - 28

	for i, choix in ipairs { { 7, "7 jours" }, { 30, "30 jours" }, { false, "Tout" } } do
		local b = Opus.Bouton(cadre, choix[2], 80, nil)
		b.jours = choix[1] or nil
		b:SetScript("OnClick", function (self) periode = self.jours Opus.Rafraichir() end)
		b:SetPoint("TOPLEFT", (i - 1) * 84, 0)
		periodes[i] = b
	end
	cadre.info = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("TOPRIGHT", -2, -5)

	-- en-têtes cliquables : un clic trie, un second inverse
	for c, col in ipairs(COLONNES) do
		local h = CreateFrame("Button", nil, cadre)
		h:SetSize(col[4], 18)
		h:SetPoint("TOPLEFT", col[3], -30)
		h.texte = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.texte:SetAllPoints() h.texte:SetJustifyH(col[5])
		h.cle, h.titre = col[1], col[2]
		h:SetScript("OnClick", function (self)
			if tri == self.cle then croissant = not croissant
			else tri, croissant = self.cle, (self.cle == "nom" or self.cle == "grade") end
			Opus.Rafraichir()
		end)
		h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		entetes[c] = h
	end

	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -ENTETE - (i - 1) * HAUTEUR)
		l:EnableMouse(true)
		Opus.FondLigne(l, i)
		Cases(l)
		Opus.Bulle(l, function (self) return Opus.Couleur(self.p.classe) .. self.p.nom .. "|r" end, Bulle)
		lignes[i] = l
	end

	cadre.total = CreateFrame("Frame", nil, cadre)
	cadre.total:SetSize(largeur, HAUTEUR)
	local filet = cadre.total:CreateTexture(nil, "ARTWORK")
	filet:SetColorTexture(1, 0.82, 0, 0.3)
	filet:SetPoint("TOPLEFT") filet:SetPoint("TOPRIGHT") filet:SetHeight(1)
	Cases(cadre.total)
	for _, t in ipairs(cadre.total.cases) do t:SetFontObject("GameFontNormalSmall") end

	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", 4, -ENTETE - 3)
	cadre.vide:SetText("Rien sur cette période.")

	cadre.aide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.aide:SetWidth(largeur - 4) cadre.aide:SetJustifyH("LEFT")
	cadre.aide:SetText("Relevé à chaque ouverture de la banque de guilde : le jeu n'y garde que les dernières opérations de chaque onglet, "
		.. "alors plus on l'ouvre souvent, plus le bilan est complet. Survole un membre pour le détail.")
end

Opus.Page("banque", "Banque", Construire, Rafraichir, function (_, d) decalage = decalage - d end)
