-- PageGroupe.lua : l'onglet Groupe, une seule page qui défile. D'abord les envies de donjon de la guilde, une carte par
-- donjon (Envies.lua, EnviesVue.lua), qui invite elle-même ceux qui sont disponibles : c'est par là qu'un groupe se monte
-- (« J'ai besoin d'un donjon… »). Puis les membres en ligne à sa portée, pour le donjon choisi en tête du bloc (ou autour
-- de son niveau) : « Écrire » ouvre un chuchotement tout prêt, « Proposer » ouvre une fenêtre chez ceux qui ont l'addon
-- (Invitation.lua).
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
	l.groupe:SetPoint("RIGHT", -6, 0) l.groupe:SetText(Opus.Vert("dans ton groupe"))
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
	Opus.Bulle(l.proposer, "Proposer par l'addon", "Une fenêtre s'ouvre chez lui pour accepter ou refuser ; s'il accepte, tu n'as plus qu'à l'inviter.")
	Opus.Bulle(l, function (self) return self.m and self.m.nom end, function (self)
		if self.m and Opus.RisqueGris(self.m.niveau) then
			return Opus.Rouge(("Les monstres seraient gris pour lui (%d niveaux d'écart ou plus) : plus personne ne gagnerait d'XP."):format(Opus.ECART_GRIS))
		end
		return nil
	end)
	return l
end

local function RemplirCandidats (c, largeur)
	local liste = Candidats()
	local min, max, nom = Opus.Tranche()
	c.titre:SetText("En ligne à ta portée" .. Opus.Gris(("   niveaux %d à %d · %d"):format(min, max, #liste)))
	c.donjon:GenerateMenu()
	c.donjon:OverrideText(nom or "Autour de mon niveau (±3)")
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
		local place = UnitInParty(m.nom)
		l.groupe:SetShown(place)
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
	-- le formulaire reprend le donjon choisi pour « En ligne à ta portée », s'il y en a un
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

	x.titreEnvies = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.videEnvies = x:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	x.videEnvies:SetWidth(x.largeur - 8) x.videEnvies:SetJustifyH("LEFT")
	x.videEnvies:SetText("Aucune envie pour l'instant. Tu dois faire un donjon pour une quête ou un objet ? « J'ai besoin d'un donjon… » prévient la guilde, et chacun peut dire quand il est disponible.")
	x.cartes = {}
	x.candidats = CreateFrame("Frame", nil, x, "BackdropTemplate")
	x.candidats:SetWidth(x.largeur) Fond(x.candidats)
	x.candidats.titre = x.candidats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.candidats.titre:SetPoint("TOPLEFT", 12, -12)
	-- le donjon visé : sa tranche de niveaux décide des membres proposés (et le formulaire d'envie le reprend)
	local menu = CreateFrame("DropdownButton", nil, x.candidats, "WowStyle1DropdownTemplate")
	menu:SetWidth(250) menu:SetPoint("TOPRIGHT", -10, -6)
	menu:SetupMenu(function (_, racine)
		local function Choisi (d) return (Opus.groupe.donjon and Opus.groupe.donjon.cle) == (d and d.cle) end
		racine:CreateRadio("Autour de mon niveau (±3)", function () return Opus.groupe.donjon == nil end, function () Opus.ChoisirDonjon(nil) end)
		for _, d in ipairs(Opus.TousLesDonjons()) do
			local texte = ("%s  (%d-%d)"):format(d.nom, d.min, d.max)
			racine:CreateRadio(Opus.APortee(d) and texte or Opus.Gris(texte), function () return Choisi(d) end, function () Opus.ChoisirDonjon(d) end)
		end
	end)
	x.candidats.donjon = menu
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
Opus.Commande("groupe", "groupe", "les envies de donjon de la guilde, et les membres en ligne à ta portée", function () Opus.OuvrirGroupe() end)

Opus.Page("groupe", "Groupe", Construire, Rafraichir, function (_, d) defile = math.max(0, defile - d * 60) end)
