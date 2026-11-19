-- PageRoster.lua : la composition de la guilde. À gauche les classes (effectif, spés, rôles), à droite les membres de la
-- classe choisie (ou de toutes), triables par colonne ; un clic sur un membre ouvre sa fiche (onglet Guilde). Les spés
-- sont celles qu'annonce l'addon de chacun (Specs.lua).
local _, Opus = ...

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local NIVEAU_MAX = 60
local GAUCHE, HAUT = 226, 26                 -- largeur du panneau des classes, hauteur de la ligne des rôles
local HAUTEUR_CLASSE, HAUTEUR, LIGNES = 36, 20, 16
local filtre, classe, tri, croissant, decalage = "tous", nil, "role", true, 0
local boutons, lignes, entetes = {}, {}, {}

local FILTRES = { { "tous", "Tous" }, { "max", "Niveau " .. NIVEAU_MAX }, { "raid", "Raiders" }, { "enligne", "En ligne" } }
local ATLAS_ROLES = { tank = "roleicon-tiny-tank", soin = "roleicon-tiny-healer", degats = "roleicon-tiny-dps" }
local ORDRE_ROLES = { tank = 1, soin = 2, degats = 3 }

local function IconeRole (role, taille) return role and CreateAtlasMarkup(ATLAS_ROLES[role], taille or 14, taille or 14) or "" end
-- ses rôles : le principal, puis les autres qu'il peut tenir, plus petits
local function IconesRoles (s)
	local roles, icones = Opus.RolesDe(s), {}
	for i, r in ipairs(roles) do icones[#icones + 1] = IconeRole(r, i == 1 and 14 or 11) end
	return table.concat(icones, "")
end
local function NomClasse (c) return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c end

-- colonnes de la liste : clé de tri, titre, x (depuis le panneau de droite), largeur, alignement
local COLONNES = {
	{ "role", "Rôle", 0, 30, "CENTER" }, { "nom", "Membre", 34, 132, "LEFT" }, { "niveau", "Niv.", 168, 28, "RIGHT" },
	{ "spe", "Spé", 204, 110, "LEFT" }, { "grade", "Grade", 318, 70, "LEFT" }, { "statut", "Statut", 390, 46, "LEFT" },
}

local function Garder (m)
	if filtre == "max" then return m.niveau >= NIVEAU_MAX end
	if filtre == "enligne" then return m.enLigne end
	if filtre == "raid" then
		local g = Opus.GRADES[m.grade] or {}
		return g.voie == "Tour" or g.essai == "raid"
	end
	return true
end

-- les membres retenus, avec leur spé et leur rôle ; et par classe, l'effectif et les spés
local function Composition ()
	local membres, parClasse, roles = {}, {}, { tank = 0, soin = 0, degats = 0, inconnu = 0, connues = 0 }
	for _, c in ipairs(CLASSES) do parClasse[c] = { n = 0, spes = {}, inconnues = 0 } end
	for _, m in ipairs(Opus.Membres()) do
		local c = m.classe and parClasse[m.classe]
		if c and Garder(m) then
			local s = Opus.db.spes[m.nom]
			m.spe, m.role = s, Opus.RoleDe(s)
			membres[#membres + 1] = m
			c.n = c.n + 1
			if s then
				c.spes[s.arbre] = (c.spes[s.arbre] or 0) + 1
				roles.connues = roles.connues + 1
			else
				c.inconnues = c.inconnues + 1
			end
			roles[m.role or "inconnu"] = roles[m.role or "inconnu"] + 1
		end
	end
	return membres, parClasse, roles
end

local function Valeur (m, cle)
	if cle == "role" then return ORDRE_ROLES[m.role] or 9 end
	if cle == "spe" then return m.spe and m.spe.arbre or "~" end
	if cle == "grade" then return m.grade end
	if cle == "statut" then return m.enLigne and 0 or 1 end
	return m[cle]
end

local function Rafraichir (cadre)
	cadre.filtre:Maj()
	local membres, parClasse, roles = Composition()
	local connues = roles.connues
	cadre.info:SetText(("%d membres · %d spé(s) connue(s)"):format(#membres, connues))
	cadre.roles:SetText(("%s %s tanks    %s %s soigneurs    %s %s dégâts    %s"):format(
		IconeRole("tank", 16), Opus.Blanc(roles.tank), IconeRole("soin", 16), Opus.Blanc(roles.soin),
		IconeRole("degats", 16), Opus.Blanc(roles.degats), Opus.Gris(roles.inconnu .. " sans rôle connu")))

	-- le panneau des classes : « Toutes », puis une ligne par classe
	boutons[1].nom:SetText(Opus.Normal("Toutes les classes"))
	boutons[1].nombre:SetText(Opus.Blanc(#membres))
	boutons[1].spes:SetText(Opus.Gris(connues .. " spé(s) connue(s)"))
	for i, c in ipairs(CLASSES) do
		local b, pc = boutons[i + 1], parClasse[c]
		b.icone:SetText(CreateAtlasMarkup(GetClassAtlas(c:lower()), 22, 22))
		b.icone:SetAlpha(pc.n > 0 and 1 or 0.35)
		b.nom:SetText(pc.n > 0 and (Opus.Couleur(c) .. NomClasse(c) .. "|r") or Opus.Gris(NomClasse(c)))
		b.nombre:SetText(pc.n > 0 and Opus.Blanc(pc.n) or Opus.Gris("0"))
		local liste = {}
		for arbre, k in pairs(pc.spes) do liste[#liste + 1] = { arbre = arbre, k = k } end
		table.sort(liste, function (x, y) return x.k > y.k end)
		local morceaux = {}
		for _, s in ipairs(liste) do morceaux[#morceaux + 1] = s.arbre .. " " .. s.k end
		if pc.inconnues > 0 then morceaux[#morceaux + 1] = Opus.Gris(pc.inconnues .. " ?") end
		b.spes:SetText(table.concat(morceaux, " · "))
	end
	for i, b in ipairs(boutons) do
		if (i == 1 and classe == nil) or CLASSES[i - 1] == classe then b:LockHighlight() else b:UnlockHighlight() end
	end

	-- la liste des membres de la classe choisie
	local liste = {}
	for _, m in ipairs(membres) do
		if not classe or m.classe == classe then liste[#liste + 1] = m end
	end
	table.sort(liste, function (a, b)
		local x, y = Valeur(a, tri), Valeur(b, tri)
		if x == y then
			if a.niveau ~= b.niveau then return a.niveau > b.niveau end
			return a.nom < b.nom
		end
		if croissant then return x < y end
		return x > y
	end)
	for _, h in ipairs(entetes) do
		h.fleche:SetShown(h.cle == tri)
		if croissant then h.fleche:SetTexCoord(0, 1, 1, 0) else h.fleche:SetTexCoord(0, 1, 0, 1) end
	end
	decalage = math.max(0, math.min(decalage, #liste - LIGNES))
	for i = 1, LIGNES do
		local l, m = lignes[i], liste[i + decalage]
		l:SetShown(m ~= nil)
		if m then
			l.m = m
			l.cases.role:SetText(IconesRoles(m.spe))
			l.cases.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
			l.cases.niveau:SetText(m.niveau)
			l.cases.spe:SetText(m.spe and (m.spe.arbre .. Opus.Gris("  " .. m.spe.points)) or Opus.Gris("inconnue"))
			l.cases.grade:SetText(m.nomGrade)
			l.cases.statut:SetText(m.enLigne and Opus.Vert("en ligne") or "")
		end
	end
	local visibles = math.min(#liste, LIGNES)
	cadre.ascenseur:SetHeight(math.max(visibles, 1) * HAUTEUR)
	cadre.ascenseur:Recaler(decalage, #liste, LIGNES)
	cadre.vide:SetShown(#liste == 0)
	return math.max(HAUT + (#CLASSES + 1) * HAUTEUR_CLASSE, HAUT + 22 + visibles * HAUTEUR)
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	cadre.filtre = Opus.Onglets(barre, FILTRES, function () return filtre end, function (v) filtre, decalage = v, 0 Opus.Rafraichir() end)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 4)
	cadre.roles = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cadre.roles:SetPoint("TOPLEFT", 4, -4)

	-- les classes
	for i = 1, #CLASSES + 1 do
		local b = CreateFrame("Button", nil, cadre)
		b:SetSize(GAUCHE, HAUTEUR_CLASSE - 2)
		b:SetPoint("TOPLEFT", 0, -HAUT - (i - 1) * HAUTEUR_CLASSE)
		-- la surbrillance du bouton marque aussi la classe choisie (LockHighlight)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local function Texte (police, ...)
			local t = b:CreateFontString(nil, "OVERLAY", police)
			t:SetPoint(...) t:SetJustifyH("LEFT") t:SetWordWrap(false)
			return t
		end
		b.icone = Texte("GameFontHighlight", "LEFT", 4, 0)
		b.nom = Texte("GameFontNormal", "TOPLEFT", 32, -4)
		b.nombre = Texte("GameFontHighlight", "TOPRIGHT", -6, -4)
		b.spes = Texte("GameFontHighlightSmall", "BOTTOMLEFT", 32, 4)
		b.spes:SetWidth(GAUCHE - 38)
		b:SetScript("OnClick", function ()
			classe, decalage = i > 1 and CLASSES[i - 1] or nil, 0
			Opus.Rafraichir()
		end)
		boutons[i] = b
	end

	-- la liste des membres, à droite
	local x0, droite = GAUCHE + 14, largeur - GAUCHE - 14
	for c, col in ipairs(COLONNES) do
		local h = CreateFrame("Button", nil, cadre)
		h:SetSize(col[4], 18)
		h:SetPoint("TOPLEFT", x0 + col[3], -HAUT)
		h.texte = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.texte:SetPoint(col[5]) h.texte:SetText(col[2])
		h.fleche = h:CreateTexture(nil, "OVERLAY")
		h.fleche:SetAtlas("auctionhouse-ui-sortarrow", true)
		if col[5] == "RIGHT" then h.fleche:SetPoint("RIGHT", h.texte, "LEFT", -3, 0) else h.fleche:SetPoint("LEFT", h.texte, "RIGHT", 3, 0) end
		h.cle = col[1]
		h:SetScript("OnClick", function (self)
			if tri == self.cle then croissant = not croissant else tri, croissant = self.cle, true end
			Opus.Rafraichir()
		end)
		Opus.Survol(h)
		entetes[c] = h
	end
	for i = 1, LIGNES do
		local l = CreateFrame("Button", nil, cadre)
		l:SetSize(droite - 14, HAUTEUR)
		l:SetPoint("TOPLEFT", x0, -HAUT - 22 - (i - 1) * HAUTEUR)
		Opus.Survol(l)
		l.cases = {}
		for _, col in ipairs(COLONNES) do
			local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", col[3], 0) t:SetWidth(col[4]) t:SetJustifyH(col[5]) t:SetWordWrap(false)
			l.cases[col[1]] = t
		end
		l:SetScript("OnClick", function (self) if self.m then Opus.OuvrirGuilde(nil, self.m.nom) end end)
		Opus.Bulle(l, function (self) return self.m and self.m.nom end, function () return { Opus.Gris("Clic : ouvrir sa fiche.") } end)
		lignes[i] = l
	end
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) decalage = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", -2, -HAUT - 22)
	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", x0 + 4, -HAUT - 26)
	cadre.vide:SetText("Personne avec ce filtre.")
end

Opus.Page("roster", "Roster", Construire, Rafraichir, function (_, d) decalage = decalage - d * 2 end)
