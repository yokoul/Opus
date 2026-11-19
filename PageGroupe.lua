-- PageGroupe.lua : l'onglet Groupe, une seule page qui défile. En haut, « Ton groupe » : le donjon (et sa tranche de
-- niveaux face au sien), les cinq places, ce qui manque, l'alerte d'XP, inviter et annoncer ; replié en une ligne tant
-- qu'on y est seul ; il sert à monter un groupe à la main. Puis les envies de donjon de la guilde, une carte par donjon
-- (Envies.lua, EnviesVue.lua), qui invite elle-même ceux qui sont disponibles. Enfin les membres en ligne à sa portée : un clic les place, « Écrire »
-- ouvre un chuchotement tout prêt, « Proposer » ouvre une fenêtre chez ceux qui ont l'addon (Invitation.lua).
local _, Opus = ...

local VUE_MAX = 520                -- hauteur visible ; au-delà, la page défile à la molette
local LIGNE_H, ECART = 22, 10
local defile = 0

local ORDRE_ROLES = { tank = 1, soin = 2, degats = 3 }

-- les membres en ligne dans la tranche, sauf soi : par rôle, puis du plus haut niveau au plus bas
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
		local x, y = ORDRE_ROLES[a.role] or 9, ORDRE_ROLES[b.role] or 9
		if x ~= y then return x < y end
		if a.niveau ~= b.niveau then return a.niveau > b.niveau end
		return a.nom < b.nom
	end)
	return liste
end

local function Fond (f)
	if not f.SetBackdrop then return end
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	f:SetBackdropColor(0.06, 0.05, 0.04, 0.85)
	f:SetBackdropBorderColor(0.45, 0.38, 0.25, 0.9)
end

------------------------------------------------------------------------
-- « Ton groupe »
------------------------------------------------------------------------

local function CarteGroupe (parent, largeur)
	local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	c:SetWidth(largeur) Fond(c)
	c.titre = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.titre:SetPoint("TOPLEFT", 12, -12) c.titre:SetText("Ton groupe")
	-- le donjon : sa tranche de niveaux décide des membres proposés plus bas
	c.donjon = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
	c.donjon:SetWidth(250) c.donjon:SetPoint("TOPLEFT", 130, -8)
	c.donjon:SetupMenu(function (_, racine)
		local function Choisi (d) return (Opus.groupe.donjon and Opus.groupe.donjon.cle) == (d and d.cle) end
		racine:CreateRadio("Autour de mon niveau (±3)", function () return Opus.groupe.donjon == nil end, function () Opus.ChoisirDonjon(nil) end)
		for _, d in ipairs(Opus.TousLesDonjons()) do
			local texte = ("%s  (%d-%d)"):format(d.nom, d.min, d.max)
			racine:CreateRadio(Opus.APortee(d) and texte or Opus.Gris(texte), function () return Choisi(d) end, function () Opus.ChoisirDonjon(d) end)
		end
	end)
	c.niveaux = Opus.CreerBarre(c, 150)
	c.niveaux.barre:SetPoint("TOPLEFT", 375, -26)
	c.seul = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.seul:SetPoint("TOPLEFT", 395, -10) c.seul:SetWidth(largeur - 410) c.seul:SetJustifyH("LEFT")
	c.seul:SetText("Le donjon visé règle qui t'est proposé plus bas ; « J'ai besoin d'un donjon… » le reprend pour prévenir la guilde.")

	-- les cinq places
	c.places = {}
	local l = math.floor((largeur - 24) / #Opus.PLACES)
	for i = 1, #Opus.PLACES do
		local p = CreateFrame("Frame", nil, c)
		p:SetSize(l - 6, 32) p:SetPoint("TOPLEFT", 12 + (i - 1) * l, -52)
		p.icone = p:CreateTexture(nil, "ARTWORK")
		p.icone:SetSize(28, 28) p.icone:SetPoint("LEFT", 0, 0)
		p.nom = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		p.nom:SetPoint("TOPLEFT", p.icone, "TOPRIGHT", 6, -2) p.nom:SetWidth(l - 60) p.nom:SetJustifyH("LEFT") p.nom:SetWordWrap(false)
		p.niveau = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		p.niveau:SetPoint("TOPLEFT", p.nom, "BOTTOMLEFT", 0, -2)
		p.retirer = Opus.Bouton(p, "×", 20, function () Opus.RetirerDuGroupe(i) end, true)
		p.retirer:SetPoint("RIGHT", 0, 0)
		c.places[i] = p
	end
	c.manque = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.manque:SetPoint("TOPLEFT", 12, -94) c.manque:SetWidth(largeur - 24) c.manque:SetJustifyH("LEFT")
	-- inviter passe par /invite dans un bouton sécurisé (inviter directement est restreint pour un addon sur Forever) ;
	-- chercher en /g prépare seulement le texte dans la ligne de discussion, à envoyer soi-même
	c.inviter = Opus.BoutonSecurise(c, 130, function ()
		GameTooltip:SetText("Inviter le groupe")
		GameTooltip:AddLine("Invite les membres placés qui ne sont pas encore avec toi.", 1, 1, 1, true)
	end)
	c.inviter:SetText("Inviter") c.inviter:SetPoint("BOTTOMLEFT", 10, 10)
	c.annoncer = Opus.Bouton(c, "Chercher en /g", 160, function () Opus.PreRemplir(Opus.MacroAnnonce()) end, true)
	c.annoncer:SetPoint("LEFT", c.inviter, "RIGHT", 6, 0)
	Opus.Bulle(c.annoncer, "Chercher en guilde", function ()
		return { Opus.MacroAnnonce() and Opus.MacroAnnonce():sub(4) or "Le groupe est complet.", Opus.Gris("Le texte s'ouvre dans la discussion : à toi de l'envoyer.") }
	end)
	c.vider = Opus.Bouton(c, "Vider le groupe", 130, function () Opus.ViderGroupe() end, true)
	c.vider:SetPoint("LEFT", c.annoncer, "RIGHT", 6, 0)
	return c
end

local function RemplirGroupe (c)
	local moi = Opus.MonNom()
	local autres = 0
	for i = 1, #Opus.PLACES do
		local nom = Opus.groupe.places[i]
		if nom and nom ~= moi then autres = autres + 1 end
	end
	local replie = autres == 0
	local d = Opus.groupe.donjon
	c.donjon:GenerateMenu()
	local niveaux = {}
	for i = 1, #Opus.PLACES do
		local nom = Opus.groupe.places[i]
		local m = nom and nom ~= moi and Opus.TrouverMembre(nom)
		if m then niveaux[#niveaux + 1] = { niveau = m.niveau } end
	end
	Opus.PlacerBarre(c.niveaux, d, niveaux)
	c.seul:SetShown(replie and not d)
	for _, w in ipairs { c.manque, c.inviter, c.annoncer, c.vider } do w:SetShown(not replie) end
	for i, r in ipairs(Opus.PLACES) do
		local p, nom = c.places[i], Opus.groupe.places[i]
		p:SetShown(not replie)
		if not replie then
			local m = nom and Opus.TrouverMembre(nom)
			Opus.AtlasPlace(p.icone, r)
			p.icone:SetDesaturated(nom == nil) p.icone:SetAlpha(nom and 1 or 0.3)
			p.nom:SetText(m and (Opus.Couleur(m.classe) .. m.nom .. "|r") or Opus.Gris(nom or "libre"))
			p.niveau:SetText(m and (Opus.RisqueGris(m.niveau) and Opus.Rouge(m.niveau) or m.niveau) or "")
			p.retirer:SetShown(nom ~= nil and nom ~= moi)
		end
	end
	if replie then
		c:SetHeight(58)
		return 58
	end
	local manque, fautifs = Opus.Manque(), Opus.AlerteNiveaux()
	c.manque:SetText((manque == "" and Opus.Vert("Groupe complet !") or (Opus.Normal("Il manque : ") .. manque))
		.. (#fautifs > 0 and ("   " .. Opus.Rouge(("Pas d'XP : monstres gris pour %s (%d niveaux d'écart ou plus)."):format(table.concat(fautifs, ", "), Opus.ECART_GRIS))) or ""))
	local invitations, annonce = Opus.MacroInvitations(), Opus.MacroAnnonce()
	c.inviter:SetAttribute("macrotext", invitations)
	c.inviter:SetEnabled(invitations ~= "")
	c.annoncer:SetEnabled(annonce ~= nil)
	c:SetHeight(146)
	return 146
end

------------------------------------------------------------------------
-- « En ligne à ta portée »
------------------------------------------------------------------------

local function LigneCandidat (parent, largeur)
	local l = CreateFrame("Button", nil, parent)
	l:SetSize(largeur - 20, LIGNE_H)
	Opus.Survol(l)
	l.icone = l:CreateTexture(nil, "ARTWORK")
	l.icone:SetSize(16, 16) l.icone:SetPoint("LEFT", 4, 0)
	local function Texte (x, w, align)
		local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("LEFT", x, 0) t:SetWidth(w) t:SetJustifyH(align or "LEFT") t:SetWordWrap(false)
		return t
	end
	l.nom = Texte(26, 150)
	l.niveau = Texte(176, 24, "RIGHT")
	l.roles = Texte(210, 44)
	l.spe = Texte(256, 130)
	l.zone = Texte(390, 120)
	l.groupe = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.groupe:SetPoint("RIGHT", -6, 0) l.groupe:SetText(Opus.Vert("dans le groupe"))
	-- chuchoter : la ligne de discussion du jeu s'ouvre avec la proposition déjà écrite, à envoyer ou retoucher
	l.ecrire = Opus.Bouton(l, "Écrire", 56, function ()
		local m = l.m
		if not m then return end
		local avecMessage = ChatFrameUtil and ChatFrameUtil.SendTellWithMessage
		if avecMessage then
			local appel = function () avecMessage(m.nom, Opus.MessageProposition(m)) end
			if securecall then securecall(appel) else appel() end
		else
			Opus.Chuchoter(m.nom)
		end
	end, true)
	l.ecrire:SetPoint("RIGHT", -2, 0)
	Opus.Bulle(l.ecrire, "Écrire", function () return l.m and Opus.MessageProposition(l.m) end)
	-- proposer : une fenêtre s'ouvre chez lui (s'il a l'addon), sa réponse revient ici
	l.proposer = Opus.Bouton(l, "Proposer", 72, function () if l.m then Opus.Proposer(l.m) end end, true)
	l.proposer:SetPoint("RIGHT", l.ecrire, "LEFT", -4, 0)
	Opus.Bulle(l.proposer, "Proposer par l'addon", "Une fenêtre s'ouvre chez lui pour accepter ou refuser ; s'il accepte, il rejoint ton groupe et tu n'as plus qu'à l'inviter.")
	l:SetScript("OnClick", function (self) if self.m then Opus.AjouterAuGroupe(self.m) end end)
	Opus.Bulle(l, function (self) return self.m and self.m.nom end, function (self)
		local texte = {}
		if self.m and Opus.RisqueGris(self.m.niveau) then
			texte[#texte + 1] = Opus.Rouge(("Les monstres seraient gris pour lui (%d niveaux d'écart ou plus) : plus personne ne gagnerait d'XP."):format(Opus.ECART_GRIS))
		end
		texte[#texte + 1] = Opus.Gris("Clic : le placer dans le groupe.")
		return texte
	end)
	return l
end

local function RemplirCandidats (c, largeur)
	local liste = Candidats()
	local min, max, nom = Opus.Tranche()
	c.titre:SetText("En ligne à ta portée" .. Opus.Gris(("   niveaux %d à %d%s · %d"):format(min, max, nom and (" · " .. nom) or "", #liste)))
	for i, m in ipairs(liste) do
		local l = c.lignes[i] or LigneCandidat(c, largeur)
		c.lignes[i] = l
		l:ClearAllPoints() l:SetPoint("TOPLEFT", 10, -36 - (i - 1) * LIGNE_H)
		l.m = m
		l:Show()
		local atlas = m.classe and GetClassAtlas and GetClassAtlas(m.classe:lower())
		if atlas then l.icone:SetAtlas(atlas) end
		l.icone:SetShown(atlas ~= nil)
		l.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
		l.niveau:SetText(Opus.RisqueGris(m.niveau) and Opus.Rouge(m.niveau) or m.niveau)
		local roles = Opus.RolesDe(m.spe)
		l.roles:SetText(Opus.IconesRoles(table.concat(roles, ",")))
		l.spe:SetText(m.spe and (m.spe.arbre .. Opus.Gris("  " .. m.spe.points)) or Opus.Gris("spé inconnue"))
		l.zone:SetText(Opus.Gris(m.zone or ""))
		local place = Opus.DansLeGroupe(m.nom)
		l.groupe:SetShown(place ~= nil)
		l.ecrire:SetShown(not place)
		l.proposer:SetShown(not place and Opus.AAddon(m.nom))
	end
	for i = #liste + 1, #c.lignes do c.lignes[i]:Hide() end
	c.vide:SetShown(#liste == 0)
	local h = 36 + math.max(#liste * LIGNE_H, #liste == 0 and 24 or 0) + 10
	c:SetHeight(h)
	return h
end

------------------------------------------------------------------------
-- la page
------------------------------------------------------------------------

local function Rafraichir (cadre)
	-- on est soi-même dans son groupe, à la place de son rôle
	local moi = Opus.TrouverMembre(Opus.MonNom())
	if moi and not Opus.DansLeGroupe(moi.nom) then Opus.AjouterAuGroupe(moi) end
	local x = cadre.contenu
	local y = 0
	local function Placer (f, h) f:ClearAllPoints() f:SetPoint("TOPLEFT", 0, -y) y = y + h + ECART end

	Placer(x.groupe, RemplirGroupe(x.groupe))

	-- les envies de la guilde
	local donjons = Opus.DonjonsDemandes()
	local joueurs, n = {}, 0
	for _, e in ipairs(Opus.Envies()) do if not joueurs[e.par] then joueurs[e.par] = true n = n + 1 end end
	x.titreEnvies:SetText("Envies de donjon de la guilde" .. Opus.Gris(("   %d donjon(s) · %d joueur(s)"):format(#donjons, n)))
	x.titreEnvies:ClearAllPoints() x.titreEnvies:SetPoint("TOPLEFT", 4, -y - 4)
	y = y + 26
	x.videEnvies:SetShown(#donjons == 0)
	if #donjons == 0 then
		x.videEnvies:ClearAllPoints() x.videEnvies:SetPoint("TOPLEFT", 4, -y)
		y = y + 40
	end
	for i, g in ipairs(donjons) do
		local c = x.cartes[i] or Opus.CarteDonjon(x, x.largeur + 14)
		x.cartes[i] = c
		c:Show()
		Placer(c, Opus.RemplirCarteDonjon(c, g))
	end
	for i = #donjons + 1, #x.cartes do x.cartes[i]:Hide() end

	-- les membres en ligne à sa portée
	Placer(x.candidats, RemplirCandidats(x.candidats, x.largeur))

	-- la page défile dans une hauteur limitée
	local total = y
	local visible = math.min(total, VUE_MAX)
	x:SetHeight(math.max(total, 1))
	cadre.defile:SetHeight(visible)
	defile = math.max(0, math.min(defile, total - visible))
	cadre.defile:SetVerticalScroll(defile)
	cadre.ascenseur:Recaler(defile, total, visible)

	-- la bande du haut : son envie, et l'annonce de sa dernière envie en guilde
	local macro = Opus.MacroEnvie()
	cadre.annoncerEnvie:SetEnabled(macro ~= "")
	cadre.info:SetText(("%d en ligne à ta portée"):format(#Candidats()))
	return visible
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	-- la bande du haut : annoncer une envie
	-- le formulaire reprend le donjon visé dans « Ton groupe », s'il y en a un
	local nouveau = Opus.Bouton(barre, "J'ai besoin d'un donjon…", 200, function ()
		local d = Opus.groupe.donjon
		Opus.EditerEnvie(d and d.cle, "maintenant")
	end)
	nouveau:SetPoint("LEFT", 0, 0)
	cadre.annoncerEnvie = Opus.Bouton(barre, "Annoncer mon envie en /g", 180, function () Opus.PreRemplir(Opus.MacroEnvie()) end)
	Opus.Bulle(cadre.annoncerEnvie, "Annoncer mon envie en /g", { "Ta dernière envie de donjon, pour ceux qui ne regardent pas l'addon.",
		Opus.Gris("Le texte s'ouvre dans la discussion de guilde : relis-le, retouche-le, envoie-le.") })
	cadre.annoncerEnvie:SetPoint("LEFT", nouveau, "RIGHT", 8, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	-- la page, dans un cadre qui défile
	cadre.defile = CreateFrame("ScrollFrame", nil, cadre)
	cadre.defile:SetPoint("TOPLEFT") cadre.defile:SetWidth(largeur - 14) cadre.defile:SetHeight(VUE_MAX)
	local x = CreateFrame("Frame", nil, cadre.defile)
	x:SetWidth(largeur - 14) x:SetHeight(1)
	x.largeur = largeur - 14
	cadre.defile:SetScrollChild(x)
	cadre.contenu = x
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) defile = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", cadre.defile, "TOPRIGHT", 14, 0)
	cadre.ascenseur:SetPoint("BOTTOMRIGHT", cadre.defile, "BOTTOMRIGHT", 14, 0)

	x.groupe = CarteGroupe(x, x.largeur)
	x.titreEnvies = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.videEnvies = x:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	x.videEnvies:SetWidth(x.largeur - 8) x.videEnvies:SetJustifyH("LEFT")
	x.videEnvies:SetText("Aucune envie pour l'instant. Tu dois faire un donjon pour une quête ou un objet ? « J'ai besoin d'un donjon… » prévient la guilde, et chacun peut dire quand il est disponible.")
	x.cartes = {}
	x.candidats = CreateFrame("Frame", nil, x, "BackdropTemplate")
	x.candidats:SetWidth(x.largeur) Fond(x.candidats)
	x.candidats.titre = x.candidats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.candidats.titre:SetPoint("TOPLEFT", 12, -12)
	x.candidats.lignes = {}
	x.candidats.vide = x.candidats:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	x.candidats.vide:SetPoint("TOPLEFT", 14, -38)
	x.candidats.vide:SetText("Personne d'autre en ligne dans cette tranche de niveaux.")
end

-- /opus groupe, /opus envies : l'onglet Groupe, en haut de la page
function Opus.OuvrirGroupe ()
	defile = 0
	Opus.db.page = "groupe"
	Opus.Fenetre(true)
	Opus.Afficher("groupe")
end
Opus.OuvrirEnvies = Opus.OuvrirGroupe
Opus.Commande("groupe", "groupe", "former un groupe de donjon, et les envies de donjon de la guilde", function () Opus.OuvrirGroupe() end)

Opus.Page("groupe", "Groupe", Construire, Rafraichir, function (_, d) defile = math.max(0, defile - d * 60) end)
