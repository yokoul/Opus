-- PageRoster.lua : la composition de la guilde, et la formation d'un groupe de donjon (vue « Former un groupe »). À gauche les classes (effectif, spés, rôles), à droite les membres de la
-- classe choisie (ou de toutes), triables par colonne ; un clic sur un membre ouvre sa fiche (onglet Guilde). Les spés
-- sont celles qu'annonce l'addon de chacun (Specs.lua).
local _, Opus = ...

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local NIVEAU_MAX = 60
local GAUCHE, HAUT = 226, 26                 -- largeur du panneau des classes, hauteur de la ligne des rôles
local HAUTEUR_CLASSE, HAUTEUR, LIGNES = 36, 20, 16
local filtre, classe, tri, croissant, decalage = "tous", nil, "role", true, 0
local boutons, lignes, entetes = {}, {}, {}

local FILTRES = { { "tous", "Tous les membres" }, { "max", "Niveau " .. NIVEAU_MAX }, { "raid", "Raiders (voie du Tour)" }, { "enligne", "En ligne" }, { "groupe", "Former un groupe" } }
local ATLAS_ROLES = { tank = "roleicon-tiny-tank", soin = "roleicon-tiny-healer", degats = "roleicon-tiny-dps" }
local ORDRE_ROLES = { tank = 1, soin = 2, degats = 3 }

local function IconeRole (role, taille) return role and CreateAtlasMarkup(ATLAS_ROLES[role], taille or 14, taille or 14) or "" end
local function NomClasse (c) return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c end

-- colonnes de la liste : clé de tri, titre, x (depuis le panneau de droite), largeur, alignement
local COLONNES = {
	{ "role", "Rôle", 0, 30, "CENTER" }, { "nom", "Membre", 34, 132, "LEFT" }, { "niveau", "Niv.", 168, 28, "RIGHT" },
	{ "spe", "Spé", 204, 110, "LEFT" }, { "grade", "Grade", 318, 70, "LEFT" }, { "statut", "Statut", 390, 46, "LEFT" },
}

local function Garder (m)
	if filtre == "groupe" then
		-- en ligne, dans la tranche du donjon, et pas soi-même (on est déjà dans son groupe)
		local min, max = Opus.Tranche()
		return m.enLigne and m.niveau >= min and m.niveau <= max and m.nom ~= Opus.MonNom()
	end
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

------------------------------------------------------------------------
-- le panneau du groupe (à la place des classes, vue « Former un groupe »)
------------------------------------------------------------------------

local function RafraichirGroupe (g)
	g.donjon:GenerateMenu()
	local min, max, nom = Opus.Tranche()
	g.tranche:SetText(Opus.Gris(("niveaux %d à %d · toi : %d"):format(min, max, UnitLevel("player"))))
	for i, r in ipairs(Opus.PLACES) do
		local p, membre = g.places[i], Opus.groupe.places[i]
		local m = membre and Opus.TrouverMembre(membre)
		p.role:SetText(IconeRole(r, 18))
		p.nom:SetText(m and (Opus.Couleur(m.classe) .. m.nom .. "|r" .. Opus.Gris("  " .. m.niveau)) or Opus.Gris(membre or "libre"))
		p.retirer:SetShown(membre ~= nil and membre ~= Opus.MonNom())
	end
	local manque = Opus.Manque()
	local fautifs = Opus.AlerteNiveaux()
	g.manque:SetText((manque == "" and Opus.Vert("Groupe complet !") or (Opus.Normal("Il manque : ") .. manque))
		.. (#fautifs > 0 and ("\n" .. Opus.Rouge(("Pas d'XP pour le groupe : monstres gris pour %s (%d niveaux d'écart ou plus)."):format(table.concat(fautifs, ", "), Opus.ECART_GRIS))) or ""))
	local invitations, annonce = Opus.MacroInvitations(), Opus.MacroAnnonce()
	g.inviter:SetAttribute("macrotext", invitations)
	g.inviter:SetEnabled(invitations ~= "")
	g.annoncer:SetAttribute("macrotext", annonce or "")
	g.annoncer:SetEnabled(annonce ~= nil)
end

local function Rafraichir (cadre)
	cadre.filtre:GenerateMenu()
	local groupe = filtre == "groupe"
	for _, b in ipairs(boutons) do b:SetShown(not groupe) end
	cadre.groupe:SetShown(groupe)
	cadre.roles:SetShown(not groupe)
	entetes[5].texte:SetText(groupe and "" or "Grade")
	entetes[6].texte:SetText(groupe and "" or "Statut")
	if groupe then
		-- on est soi-même dans son groupe, à la place de son rôle
		local moi = Opus.TrouverMembre(Opus.MonNom())
		if moi and not Opus.DansLeGroupe(moi.nom) then Opus.AjouterAuGroupe(moi) end
		RafraichirGroupe(cadre.groupe)
	end
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
		if groupe or not classe or m.classe == classe then liste[#liste + 1] = m end
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
			l.cases.role:SetText(IconeRole(m.role))
			l.cases.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
			l.cases.niveau:SetText(groupe and Opus.RisqueGris(m.niveau) and Opus.Rouge(m.niveau) or m.niveau)
			l.cases.spe:SetText(m.spe and (m.spe.arbre .. Opus.Gris("  " .. m.spe.points)) or Opus.Gris("inconnue"))
			l.cases.grade:SetText(groupe and (m.zone or "") or m.nomGrade)
			l.cases.statut:SetText(groupe and (Opus.DansLeGroupe(m.nom) and Opus.Vert("groupé") or "") or (m.enLigne and Opus.Vert("en ligne") or ""))
			-- dans la vue groupe : écrire (message tout prêt), et proposer par l'addon à qui l'a
			local libre = groupe and not Opus.DansLeGroupe(m.nom)
			l.ecrire:SetShown(libre)
			l.proposer:SetShown(libre and Opus.AAddon(m.nom))
			if groupe then l.cases.grade:SetText("") end
		end
	end
	local visibles = math.min(#liste, LIGNES)
	cadre.ascenseur:SetHeight(math.max(visibles, 1) * HAUTEUR)
	cadre.ascenseur:Recaler(decalage, #liste, LIGNES)
	cadre.vide:SetShown(#liste == 0)
	cadre.vide:SetText(groupe and "Personne en ligne dans cette tranche de niveaux." or "Personne avec ce filtre.")
	return math.max(HAUT + (#CLASSES + 1) * HAUTEUR_CLASSE, HAUT + 22 + visibles * HAUTEUR)
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	cadre.filtre = Opus.Menu(barre, 200, FILTRES, function () return filtre end, function (v) filtre, decalage = v, 0 Opus.Rafraichir() end)
	cadre.filtre:SetPoint("LEFT", 0, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)
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
		-- un clic : dans la vue groupe, l'ajouter au groupe ; sinon, ouvrir sa fiche
		l:SetScript("OnClick", function (self)
			if not self.m then return end
			if filtre == "groupe" then Opus.AjouterAuGroupe(self.m) else Opus.OuvrirGuilde(nil, self.m.nom) end
		end)
		Opus.Bulle(l, function (self) return self.m and self.m.nom end, function (self)
			local texte = {}
			if filtre == "groupe" and self.m then
				if self.m.zone then texte[#texte + 1] = self.m.zone end
				if Opus.RisqueGris(self.m.niveau) then
					texte[#texte + 1] = Opus.Rouge(("Les monstres seraient gris pour lui (%d niveaux d'écart ou plus) : plus personne ne gagnerait d'XP."):format(Opus.ECART_GRIS))
				end
			end
			texte[#texte + 1] = Opus.Gris(filtre == "groupe" and "Clic : l'ajouter au groupe." or "Clic : ouvrir sa fiche.")
			return texte
		end)
		-- chuchoter : la ligne de discussion du jeu s'ouvre avec la proposition déjà écrite, à envoyer ou retoucher
		l.ecrire = Opus.Bouton(l, "Écrire", 52, function (self)
			local m = self:GetParent().m
			if not m then return end
			local avecMessage = ChatFrameUtil and ChatFrameUtil.SendTellWithMessage
			local seul = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
			local appel = avecMessage and function () avecMessage(m.nom, Opus.MessageProposition(m)) end or function () seul(m.nom) end
			if securecall then securecall(appel) else appel() end
		end, true)
		l.ecrire:SetPoint("RIGHT", -2, 0)
		l.ecrire:Hide()
		Opus.Bulle(l.ecrire, "Écrire", function (self) return self:GetParent().m and Opus.MessageProposition(self:GetParent().m) end)
		-- proposer : une fenêtre s'ouvre chez lui (s'il a l'addon), sa réponse revient ici
		l.proposer = Opus.Bouton(l, "Proposer", 70, function (self)
			local m = self:GetParent().m
			if m then Opus.Proposer(m) end
		end, true)
		l.proposer:SetPoint("RIGHT", l.ecrire, "LEFT", -4, 0)
		l.proposer:Hide()
		Opus.Bulle(l.proposer, "Proposer par l'addon", "Une fenêtre s'ouvre chez lui pour accepter ou refuser ; s'il accepte, il rejoint ton groupe et tu n'as plus qu'à l'inviter.")
		lignes[i] = l
	end
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) decalage = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", -2, -HAUT - 22)
	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", x0 + 4, -HAUT - 26)
	cadre.vide:SetText("Personne avec ce filtre.")

	-- le panneau du groupe
	local g = CreateFrame("Frame", nil, cadre)
	g:SetPoint("TOPLEFT", 0, -4) g:SetSize(GAUCHE, 380)
	cadre.groupe = g
	g.donjon = CreateFrame("DropdownButton", nil, g, "WowStyle1DropdownTemplate")
	g.donjon:SetWidth(GAUCHE - 6)
	g.donjon:SetPoint("TOPLEFT", 0, 0)
	g.donjon:SetupMenu(function (_, racine)
		local function Choisi (d) return (Opus.groupe.donjon and Opus.groupe.donjon.cle) == (d and d.cle) end
		local function Choisir (d) decalage = 0 Opus.ChoisirDonjon(d) end
		racine:CreateRadio("Autour de mon niveau (±3)", function () return Opus.groupe.donjon == nil end, function () Choisir(nil) end)
		local n = UnitLevel("player")
		for _, d in ipairs(Opus.Donjons()) do
			-- les donjons à portée : de 5 niveaux en dessous de leur minimum à leur maximum
			if n >= d.min - 5 and n <= d.max + 2 then
				racine:CreateRadio(("%s  (%d-%d)"):format(d.nom, d.min, d.max), function () return Choisi(d) end, function () Choisir(d) end)
			end
		end
	end)
	g.tranche = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	g.tranche:SetPoint("TOPLEFT", 4, -34)
	g.places = {}
	for i = 1, #Opus.PLACES do
		local p = CreateFrame("Frame", nil, g)
		p:SetSize(GAUCHE - 6, 28)
		p:SetPoint("TOPLEFT", 0, -54 - (i - 1) * 30)
		p.role = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.role:SetPoint("LEFT", 4, 0)
		p.nom = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.nom:SetPoint("LEFT", 30, 0) p.nom:SetWidth(GAUCHE - 70) p.nom:SetJustifyH("LEFT") p.nom:SetWordWrap(false)
		p.retirer = Opus.Bouton(p, "×", 24, function () Opus.RetirerDuGroupe(i) end, true)
		p.retirer:SetPoint("RIGHT", -4, 0)
		g.places[i] = p
	end
	g.manque = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	g.manque:SetPoint("TOPLEFT", 4, -54 - #Opus.PLACES * 30 - 4) g.manque:SetWidth(GAUCHE - 10) g.manque:SetJustifyH("LEFT")
	-- inviter et annoncer passent par des commandes (/invite, /g) dans des boutons sécurisés : les fonctions directes
	-- sont restreintes pour un addon sur Forever
	g.inviter = Opus.BoutonSecurise(g, (GAUCHE - 12) / 2, function ()
		GameTooltip:SetText("Inviter le groupe")
		GameTooltip:AddLine("Invite les membres placés qui ne sont pas encore avec toi.", 1, 1, 1, true)
	end)
	g.inviter:SetText("Inviter")
	g.inviter:SetPoint("TOPLEFT", 0, -54 - #Opus.PLACES * 30 - 26)
	g.annoncer = Opus.BoutonSecurise(g, (GAUCHE - 12) / 2, function ()
		GameTooltip:SetText("Annoncer en guilde")
		GameTooltip:AddLine(Opus.MacroAnnonce() and Opus.MacroAnnonce():sub(4) or "Le groupe est complet.", 1, 1, 1, true)
	end)
	g.annoncer:SetText("Annoncer")
	g.annoncer:SetPoint("LEFT", g.inviter, "RIGHT", 6, 0)
	local vider = Opus.Bouton(g, "Vider le groupe", GAUCHE - 6, function () Opus.ViderGroupe() end, true)
	vider:SetPoint("TOPLEFT", 0, -54 - #Opus.PLACES * 30 - 52)
	g:Hide()
end

-- /opus groupe : le Roster, vue « Former un groupe »
function Opus.OuvrirGroupe ()
	filtre, decalage = "groupe", 0
	Opus.db.page = "roster"
	Opus.Fenetre(true)
end
Opus.Commande("groupe", "groupe", "former un groupe de donjon avec les membres en ligne de ton niveau", function () Opus.OuvrirGroupe() end)

Opus.Page("roster", "Roster", Construire, Rafraichir, function (_, d) decalage = decalage - d * 2 end)
