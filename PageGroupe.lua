-- PageGroupe.lua : former un groupe de donjon. Le donjon (et sa tranche de niveaux) en haut, le groupe à gauche (une
-- place par rôle, ce qui manque, l'alerte d'XP), à droite les membres en ligne de la tranche : un clic les place, « Écrire »
-- ouvre un chuchotement tout prêt, « Proposer » ouvre une fenêtre chez ceux qui ont l'addon (Invitation.lua).
local _, Opus = ...

local GAUCHE, HAUTEUR, LIGNES = 226, 20, 16
local tri, croissant, decalage = "role", true, 0
local lignes, entetes = {}, {}

local ATLAS_ROLES = { tank = "roleicon-tiny-tank", soin = "roleicon-tiny-healer", degats = "roleicon-tiny-dps" }
local ORDRE_ROLES = { tank = 1, soin = 2, degats = 3 }
local function IconeRole (role, taille) return role and CreateAtlasMarkup(ATLAS_ROLES[role], taille or 14, taille or 14) or "" end
-- ses rôles : le principal, puis les autres qu'il peut tenir, plus petits
local function IconesRoles (s)
	local roles, icones = Opus.RolesDe(s), {}
	for i, r in ipairs(roles) do icones[#icones + 1] = IconeRole(r, i == 1 and 14 or 11) end
	return table.concat(icones, "")
end

-- colonnes des candidats : clé de tri, titre, x (depuis le panneau de droite), largeur, alignement ; les boutons à droite
local COLONNES = {
	{ "role", "Rôle", 0, 30, "CENTER" }, { "nom", "Membre", 34, 132, "LEFT" }, { "niveau", "Niv.", 168, 28, "RIGHT" },
	{ "spe", "Spé", 204, 108, "LEFT" },
}

local function Valeur (m, cle)
	if cle == "role" then return ORDRE_ROLES[m.role] or 9 end
	if cle == "spe" then return m.spe and m.spe.arbre or "~" end
	return m[cle]
end

-- les candidats : en ligne, dans la tranche, pas soi-même
local function Candidats ()
	local min, max = Opus.Tranche()
	local moi, liste = Opus.MonNom(), {}
	for _, m in ipairs(Opus.Membres()) do
		if m.enLigne and m.niveau >= min and m.niveau <= max and m.nom ~= moi then
			m.spe = Opus.db.spes[m.nom]
			m.role = Opus.RoleDe(m.spe)
			liste[#liste + 1] = m
		end
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
	return liste
end

local function Rafraichir (cadre)
	-- on est soi-même dans son groupe, à la place de son rôle
	local moi = Opus.TrouverMembre(Opus.MonNom())
	if moi and not Opus.DansLeGroupe(moi.nom) then Opus.AjouterAuGroupe(moi) end

	cadre.donjon:GenerateMenu()
	local min, max = Opus.Tranche()
	cadre.tranche:SetText(("niveaux %d à %d · toi : %d"):format(min, max, UnitLevel("player")))

	-- le groupe
	local g = cadre.groupe
	for i, r in ipairs(Opus.PLACES) do
		local p, membre = g.places[i], Opus.groupe.places[i]
		local m = membre and Opus.TrouverMembre(membre)
		p.role:SetText(IconeRole(r, 18))
		p.nom:SetText(m and (Opus.Couleur(m.classe) .. m.nom .. "|r" .. Opus.Gris("  " .. m.niveau)) or Opus.Gris(membre or "libre"))
		p.retirer:SetShown(membre ~= nil and membre ~= Opus.MonNom())
	end
	local manque, fautifs = Opus.Manque(), Opus.AlerteNiveaux()
	g.manque:SetText((manque == "" and Opus.Vert("Groupe complet !") or (Opus.Normal("Il manque : ") .. manque))
		.. (#fautifs > 0 and ("\n" .. Opus.Rouge(("Pas d'XP pour le groupe : monstres gris pour %s (%d niveaux d'écart ou plus)."):format(table.concat(fautifs, ", "), Opus.ECART_GRIS))) or ""))
	local invitations, annonce = Opus.MacroInvitations(), Opus.MacroAnnonce()
	g.inviter:SetAttribute("macrotext", invitations)
	g.inviter:SetEnabled(invitations ~= "")
	g.annoncer:SetAttribute("macrotext", annonce or "")
	g.annoncer:SetEnabled(annonce ~= nil)

	-- les candidats
	local liste = Candidats()
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
			l.cases.niveau:SetText(Opus.RisqueGris(m.niveau) and Opus.Rouge(m.niveau) or m.niveau)
			l.cases.spe:SetText(m.spe and (m.spe.arbre .. Opus.Gris("  " .. m.spe.points)) or Opus.Gris("inconnue"))
			local place = Opus.DansLeGroupe(m.nom)
			l.groupe:SetShown(place ~= nil)
			l.ecrire:SetShown(not place)
			l.proposer:SetShown(not place and Opus.AAddon(m.nom))
		end
	end
	local visibles = math.min(#liste, LIGNES)
	cadre.ascenseur:SetHeight(math.max(visibles, 1) * HAUTEUR)
	cadre.ascenseur:Recaler(decalage, #liste, LIGNES)
	cadre.vide:SetShown(#liste == 0)
	cadre.info:SetText(("%d en ligne dans la tranche"):format(#liste))
	return math.max(54 + #Opus.PLACES * 30 + 90, 22 + visibles * HAUTEUR)
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	-- le donjon, dans la bande du haut : sa tranche de niveaux décide des candidats
	cadre.donjon = CreateFrame("DropdownButton", nil, barre, "WowStyle1DropdownTemplate")
	cadre.donjon:SetWidth(260)
	cadre.donjon:SetPoint("LEFT", 0, 0)
	cadre.donjon:SetupMenu(function (_, racine)
		local function Choisi (d) return (Opus.groupe.donjon and Opus.groupe.donjon.cle) == (d and d.cle) end
		local function Choisir (d) decalage = 0 Opus.ChoisirDonjon(d) end
		racine:CreateRadio("Autour de mon niveau (±3)", function () return Opus.groupe.donjon == nil end, function () Choisir(nil) end)
		local n = UnitLevel("player")
		for _, d in ipairs(Opus.Donjons()) do
			-- les donjons à portée : de 5 niveaux sous leur minimum à 2 au-dessus de leur maximum
			if n >= d.min - 5 and n <= d.max + 2 then
				racine:CreateRadio(("%s  (%d-%d)"):format(d.nom, d.min, d.max), function () return Choisi(d) end, function () Choisir(d) end)
			end
		end
	end)
	cadre.tranche = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.tranche:SetPoint("LEFT", cadre.donjon, "RIGHT", 12, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	-- le groupe, à gauche
	local g = CreateFrame("Frame", nil, cadre)
	g:SetPoint("TOPLEFT") g:SetSize(GAUCHE, 340)
	cadre.groupe = g
	local titre = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titre:SetPoint("TOPLEFT", 4, -2)
	titre:SetText("Ton groupe")
	g.places = {}
	for i = 1, #Opus.PLACES do
		local p = CreateFrame("Frame", nil, g)
		p:SetSize(GAUCHE - 6, 28)
		p:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 30)
		p.role = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.role:SetPoint("LEFT", 4, 0)
		p.nom = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.nom:SetPoint("LEFT", 30, 0) p.nom:SetWidth(GAUCHE - 70) p.nom:SetJustifyH("LEFT") p.nom:SetWordWrap(false)
		p.retirer = Opus.Bouton(p, "×", 24, function () Opus.RetirerDuGroupe(i) end, true)
		p.retirer:SetPoint("RIGHT", -4, 0)
		g.places[i] = p
	end
	local bas = -24 - #Opus.PLACES * 30
	g.manque = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	g.manque:SetPoint("TOPLEFT", 4, bas - 4) g.manque:SetWidth(GAUCHE - 10) g.manque:SetJustifyH("LEFT")
	-- inviter et annoncer passent par des commandes (/invite, /g) dans des boutons sécurisés : les fonctions directes
	-- sont restreintes pour un addon sur Forever
	g.inviter = Opus.BoutonSecurise(g, (GAUCHE - 12) / 2, function ()
		GameTooltip:SetText("Inviter le groupe")
		GameTooltip:AddLine("Invite les membres placés qui ne sont pas encore avec toi.", 1, 1, 1, true)
	end)
	g.inviter:SetText("Inviter")
	g.inviter:SetPoint("TOPLEFT", 0, bas - 46)
	g.annoncer = Opus.BoutonSecurise(g, (GAUCHE - 12) / 2, function ()
		GameTooltip:SetText("Annoncer en guilde")
		GameTooltip:AddLine(Opus.MacroAnnonce() and Opus.MacroAnnonce():sub(4) or "Le groupe est complet.", 1, 1, 1, true)
	end)
	g.annoncer:SetText("Annoncer")
	g.annoncer:SetPoint("LEFT", g.inviter, "RIGHT", 6, 0)
	local vider = Opus.Bouton(g, "Vider le groupe", GAUCHE - 6, function () Opus.ViderGroupe() end, true)
	vider:SetPoint("TOPLEFT", 0, bas - 72)

	-- les candidats, à droite
	local x0, droite = GAUCHE + 14, largeur - GAUCHE - 14
	for c, col in ipairs(COLONNES) do
		local h = CreateFrame("Button", nil, cadre)
		h:SetSize(col[4], 18)
		h:SetPoint("TOPLEFT", x0 + col[3], 0)
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
		l:SetPoint("TOPLEFT", x0, -22 - (i - 1) * HAUTEUR)
		Opus.Survol(l)
		l.cases = {}
		for _, col in ipairs(COLONNES) do
			local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", col[3], 0) t:SetWidth(col[4]) t:SetJustifyH(col[5]) t:SetWordWrap(false)
			l.cases[col[1]] = t
		end
		l:SetScript("OnClick", function (self) if self.m then Opus.AjouterAuGroupe(self.m) end end)
		Opus.Bulle(l, function (self) return self.m and self.m.nom end, function (self)
			local texte = {}
			if self.m then
				if self.m.zone then texte[#texte + 1] = self.m.zone end
				if Opus.RisqueGris(self.m.niveau) then
					texte[#texte + 1] = Opus.Rouge(("Les monstres seraient gris pour lui (%d niveaux d'écart ou plus) : plus personne ne gagnerait d'XP."):format(Opus.ECART_GRIS))
				end
			end
			texte[#texte + 1] = Opus.Gris("Clic : le placer dans le groupe.")
			return texte
		end)
		l.groupe = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.groupe:SetPoint("RIGHT", -6, 0)
		l.groupe:SetText(Opus.Vert("dans le groupe"))
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
		Opus.Bulle(l.ecrire, "Écrire", function (self) return self:GetParent().m and Opus.MessageProposition(self:GetParent().m) end)
		-- proposer : une fenêtre s'ouvre chez lui (s'il a l'addon), sa réponse revient ici
		l.proposer = Opus.Bouton(l, "Proposer", 70, function (self)
			local m = self:GetParent().m
			if m then Opus.Proposer(m) end
		end, true)
		l.proposer:SetPoint("RIGHT", l.ecrire, "LEFT", -4, 0)
		Opus.Bulle(l.proposer, "Proposer par l'addon", "Une fenêtre s'ouvre chez lui pour accepter ou refuser ; s'il accepte, il rejoint ton groupe et tu n'as plus qu'à l'inviter.")
		lignes[i] = l
	end
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) decalage = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", -2, -22)
	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", x0 + 4, -26)
	cadre.vide:SetText("Personne en ligne dans cette tranche de niveaux.")
end

-- /opus groupe
function Opus.OuvrirGroupe ()
	Opus.db.page = "groupe"
	Opus.Fenetre(true)
end
Opus.Commande("groupe", "groupe", "former un groupe de donjon avec les membres en ligne de ton niveau", function () Opus.OuvrirGroupe() end)

Opus.Page("groupe", "Groupe", Construire, Rafraichir, function (_, d) decalage = decalage - d * 2 end)
