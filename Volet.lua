-- Volet.lua : le volet latéral du butin, en démonstration (données factices) pour essayer en jeu les polices, les
-- textures et la taille avant de le brancher sur le butin. Au bord gauche de l'écran, une languette porte un signe
-- (gemme pâle : rien ; gemme or : des objets circulent ; rubis : à toi d'agir) ; une banderole en sort quand une
-- décision attend, et le volet glisse par-dessus les cadres de raid. Il se ferme à l'entrée en combat.
-- /opus volet : montrer ou cacher la démonstration ; /opus volet aide pour le reste.
local _, Opus = ...

local Volet = {}
Opus.Volet = Volet

local MEDIA = "Interface\\AddOns\\Opus\\Media\\Volet\\"
local POLICES = "Interface\\AddOns\\Opus\\Media\\Polices\\"
local BLANC8 = "Interface\\Buttons\\WHITE8X8"

------------------------------------------------------------------------
-- la charte : couleurs et polices
------------------------------------------------------------------------

local function Hex (h) return tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 end
local C = {
	encre = { Hex("#0d0a06") }, cuir = { Hex("#1a140d") }, orSombre = { Hex("#6e4a1a") }, ["or"] = { Hex("#d9a44d") },
	orVif = { Hex("#f3d58a") }, parchemin = { Hex("#f1e6cf") }, pale = { Hex("#cfbf9c") }, poussiere = { Hex("#9b8865") },
	braise = { Hex("#e8603a") }, braiseTexte = { Hex("#ff8a5c") }, braiseBord = { Hex("#7a3420") },
	acier = { Hex("#cfd4dc") }, mousse = { Hex("#9fd67f") }, cendre = { Hex("#5a5348") }, encreTexte = { Hex("#2a1d0e") },
}

-- Cinzel pour les titres, onglets, boutons et étiquettes ; PT Sans Narrow pour le reste (celle de Gargul et d'ElvUI).
-- Si un fichier manque, la police du jeu prend le relais et /opus volet aide le dit.
local polices = {}
local manquantes = {}
local function Police (nom, fichier, taille)
	local f = CreateFont("OpusVolet" .. nom)
	-- SetFont dit false quand le fichier ne se charge pas (les clients plus anciens ne disent rien)
	if f:SetFont(POLICES .. fichier, taille, "") == false then
		f:SetFont(STANDARD_TEXT_FONT, taille, "")
		manquantes[fichier] = true
	end
	polices[nom] = f
end
Police("Titre", "Cinzel-Bold.ttf", 16)
Police("Etiquette", "Cinzel-SemiBold.ttf", 10)
Police("Bouton", "Cinzel-SemiBold.ttf", 11)
Police("Texte", "PTSansNarrow.ttf", 14)
Police("Nom", "PTSansNarrow.ttf", 15)
Police("Petit", "PTSansNarrow.ttf", 13)
Police("Chiffre", "PTSansNarrow.ttf", 18)

local function Texte (parent, police, couleur, couche)
	local t = parent:CreateFontString(nil, couche or "OVERLAY")
	t:SetFontObject(polices[police])
	if couleur then t:SetTextColor(couleur[1], couleur[2], couleur[3]) end
	t:SetJustifyH("LEFT") t:SetWordWrap(false)
	return t
end

local function Aplat (parent, couleur, alpha, couche)
	local t = parent:CreateTexture(nil, couche or "ARTWORK")
	t:SetTexture(BLANC8) t:SetVertexColor(couleur[1], couleur[2], couleur[3], alpha or 1)
	return t
end

local function Image (parent, fichier, l, h, couche)
	local t = parent:CreateTexture(nil, couche or "ARTWORK")
	t:SetTexture(MEDIA .. fichier) t:SetSize(l, h)
	return t
end

------------------------------------------------------------------------
-- neuf parts : les coins gardent leur taille, les bords et le centre s'étirent
------------------------------------------------------------------------

-- f : le cadre ; fichier, tw, th : la texture et sa taille ; mx, my : la marge des coins dans la texture ;
-- e : leur taille à l'écran ; eg : celle du bord gauche (0 : pas de bord gauche, collé au bord de l'écran).
local function NeufParts (f, fichier, tw, th, mx, my, e, eg)
	eg = eg or e
	local u, v = mx / tw, my / th
	local U = { { 0, u }, { u, 1 - u }, { 1 - u, 1 } }
	local V = { { 0, v }, { v, 1 - v }, { 1 - v, 1 } }
	local X = { { "LEFT", 0, "LEFT", eg }, { "LEFT", eg, "RIGHT", -e }, { "RIGHT", -e, "RIGHT", 0 } }
	local Y = { { "TOP", 0, "TOP", -e }, { "TOP", -e, "BOTTOM", e }, { "BOTTOM", e, "BOTTOM", 0 } }
	for j = 1, 3 do
		for i = (eg == 0 and 2 or 1), 3 do
			local t = f:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(MEDIA .. fichier)
			t:SetTexCoord(U[i][1], U[i][2], V[j][1], V[j][2])
			t:SetPoint("TOPLEFT", f, Y[j][1] .. X[i][1], X[i][2], Y[j][2])
			t:SetPoint("BOTTOMRIGHT", f, Y[j][3] .. X[i][3], X[i][4], Y[j][4])
		end
	end
end

------------------------------------------------------------------------
-- boutons, étiquettes, signes
------------------------------------------------------------------------

-- L'action principale : un filet or et un dégradé léger, à la manière d'Auberdine. Une seule par ligne.
local function BoutonPrincipal (parent, texte, clic)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ edgeFile = BLANC8, edgeSize = 1 })
	b:SetBackdropBorderColor(C["or"][1], C["or"][2], C["or"][3], 1)
	b.fond = b:CreateTexture(nil, "BACKGROUND")
	b.fond:SetPoint("TOPLEFT", 1, -1) b.fond:SetPoint("BOTTOMRIGHT", -1, 1)
	b.fond:SetTexture(BLANC8)
	local haut, bas = { 0.95, 0.84, 0.54, 0.20 }, { 0.43, 0.29, 0.10, 0.30 }
	if CreateColor and not pcall(b.fond.SetGradient, b.fond, "VERTICAL", CreateColor(unpack(bas)), CreateColor(unpack(haut))) then
		b.fond:SetVertexColor(0.6, 0.45, 0.2, 0.25)
	end
	b.reflet = Aplat(b, C.orVif, 0.25) b.reflet:SetHeight(1)
	b.reflet:SetPoint("TOPLEFT", 1, -1) b.reflet:SetPoint("TOPRIGHT", -1, -1)
	b.texte = Texte(b, "Bouton", C.orVif) b.texte:SetPoint("CENTER", 0, 0) b.texte:SetText(texte)
	b.texte:SetShadowColor(0, 0, 0, 1) b.texte:SetShadowOffset(1, -1)
	b:SetSize(math.max(96, b.texte:GetStringWidth() + 36), 30)
	b:SetHighlightTexture(BLANC8) b:GetHighlightTexture():SetVertexColor(C.orVif[1], C.orVif[2], C.orVif[3], 0.10)
	b:SetScript("OnClick", clic)
	return b
end

-- Les autres actions : le mot seul, souligné d'un filet or.
local function BoutonSecond (parent, texte, clic)
	local b = CreateFrame("Button", nil, parent)
	b.texte = Texte(b, "Bouton", { Hex("#e7d09a") }) b.texte:SetPoint("CENTER", 0, 1) b.texte:SetText(texte)
	b:SetSize(b.texte:GetStringWidth() + 6, 30)
	b.filet = Aplat(b, C["or"], 0.4) b.filet:SetHeight(1)
	b.filet:SetPoint("BOTTOMLEFT", 0, 4) b.filet:SetPoint("BOTTOMRIGHT", 0, 4)
	b:SetScript("OnEnter", function (self) self.texte:SetTextColor(C.orVif[1], C.orVif[2], C.orVif[3]) end)
	b:SetScript("OnLeave", function (self) self.texte:SetTextColor(Hex("#e7d09a")) end)
	b:SetScript("OnClick", clic)
	return b
end

-- Les quatre signes, partout dans le volet : rubis (à toi d'agir), sablier (on attend quelqu'un), coche (tranché) ;
-- rien du tout pour ce qui ne te concerne pas.
local SIGNES = { toi = "Rubis", attente = "Sablier", rendu = "Coche" }

-- L'étiquette d'état : petites capitales en Cinzel, un filet de la couleur du sens, et son signe devant.
local function Etiquette (parent, texte, sens)
	local e = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	e:SetBackdrop({ edgeFile = BLANC8, edgeSize = 1 })
	local bord, couleur = C.orSombre, C["or"]
	if sens == "toi" then bord, couleur = C.braiseBord, C.braiseTexte
	elseif sens == "attente" then bord, couleur = { Hex("#5a606a") }, C.acier end
	e:SetBackdropBorderColor(bord[1], bord[2], bord[3], 1)
	local x = 6
	if SIGNES[sens] then
		local s = Image(e, SIGNES[sens] .. ".tga", 13, 13) s:SetPoint("LEFT", 4, 0)
		x = 20
	end
	e.texte = Texte(e, "Etiquette", couleur) e.texte:SetPoint("LEFT", x, 0) e.texte:SetText(texte)
	e:SetSize(e.texte:GetStringWidth() + x + 7, 19)
	return e
end

local function Cadre (parent, icone, taille)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(taille, taille)
	c.icone = c:CreateTexture(nil, "ARTWORK")
	c.icone:SetPoint("TOPLEFT", taille * 0.14, -taille * 0.14) c.icone:SetPoint("BOTTOMRIGHT", -taille * 0.14, taille * 0.14)
	c.icone:SetTexture(icone) c.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.cadre = Image(c, "CadreFer.tga", taille, taille, "OVERLAY") c.cadre:SetPoint("CENTER")
	return c
end

-- couleurs de classe et de qualité du jeu
local function Classe (nom, classe)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	return c and ("|c" .. c.colorStr .. nom .. "|r") or nom
end
local function Qualite (n)
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[n]
	if q then return q.r, q.g, q.b end
	return 0.64, 0.21, 0.93
end

------------------------------------------------------------------------
-- les données de la démonstration
------------------------------------------------------------------------

local DEMO = {
	titre = "Butin", lieu = "Cœur du Magma · Garr",
	appel = {
		nom = "Anneau d'obsidienne", icone = "Interface\\Icons\\INV_Jewelry_Ring_15", qualite = 4,
		resume = "Hors liste · |cff9fd67f+6 %|r pour toi · tu passerais en tête",
		duree = 30,
	},
	lignes = {
		{ nom = "Ceinture de braises", icone = "Interface\\Icons\\INV_Belt_13", qualite = 4,
		  sous = Classe("Seliane", "DRUID") .. " ou " .. Classe("Vorthas", "WARLOCK") .. " · 5 sur 9 ont voté", etiquette = "VOTER", sens = "toi" },
		{ nom = "Gantelets de flammèche", icone = "Interface\\Icons\\INV_Gauntlets_19", qualite = 4,
		  sous = Classe("Brannok", "WARRIOR") .. " · liste 1 sur 2", etiquette = "DÉLAI 0:48", sens = "attente" },
		{ nom = "Fragment de cœur ardent", icone = "Interface\\Icons\\INV_Misc_Gem_Ruby_01", qualite = 4,
		  sous = "remis à " .. Classe("Seliane", "DRUID"), sens = "rendu", pale = 0.55 },
		{ nom = "Jambières de lave", icone = "Interface\\Icons\\INV_Pants_04", qualite = 4,
		  sous = "plaque · ne te concerne pas", pale = 0.4 },
	},
	liste = {
		"|cffa335eeBottes de l'arcaniste|r · rang 1 · Baron Geddon",
		"|cffa335eeTalisman d'éphémère|r · rang 3 · Ragnaros",
	},
}

------------------------------------------------------------------------
-- la languette et la banderole
------------------------------------------------------------------------

local languette, banderole, volet
local etat = "toi"                      -- repos, cours ou toi
local reponse                           -- ce que le joueur a répondu à l'appel de la démonstration

local function Reglages ()
	OpusDB.volet = OpusDB.volet or {}
	return OpusDB.volet
end

local function PoserLanguette ()
	if not languette then return end
	local l = languette
	l.gemme:SetShown(etat ~= "toi") l.rubis:SetShown(etat == "toi")
	l.gemme:SetDesaturated(etat == "repos") l.gemme:SetAlpha(etat == "repos" and 0.5 or 1)
	if etat == "toi" then l.compte:SetText("2") l.compte:SetTextColor(C.braiseTexte[1], C.braiseTexte[2], C.braiseTexte[3])
	elseif etat == "cours" then l.compte:SetText("4") l.compte:SetTextColor(C.orVif[1], C.orVif[2], C.orVif[3])
	else l.compte:SetText("") end
	l.fleche:SetShown(volet and volet:IsShown())
end

local function OuvrirVolet (ouvrir)
	if ouvrir == nil then ouvrir = not volet:IsShown() end
	if ouvrir and InCombatLockdown() then Opus.Msg("le volet reste fermé en combat.") return end
	volet:SetShown(ouvrir)
	if ouvrir then banderole:Hide() end
	languette:ClearAllPoints()
	if ouvrir then languette:SetPoint("TOPLEFT", volet, "TOPRIGHT", -2, -66)
	else languette:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, Reglages().y or -260) end
	PoserLanguette()
end

local function FinAppel (texte)
	banderole:SetScript("OnUpdate", nil)
	banderole:Hide()
	if texte then reponse = texte Opus.Msg(texte) end
	if volet and volet.Remplir then volet:Remplir() end
end

local function CreerLanguette ()
	local l = CreateFrame("Button", "OpusVoletLanguette", UIParent)
	l:SetSize(30, 128) l:SetFrameStrata("HIGH") l:SetClampedToScreen(true)
	NeufParts(l, "Panneau.tga", 512, 256, 42, 39, 10, 0)
	l.gemme = Image(l, "Gemme.tga", 18, 36) l.gemme:SetPoint("CENTER", 0, 8)
	l.rubis = Image(l, "Rubis.tga", 24, 24) l.rubis:SetPoint("CENTER", 0, 10)
	l.compte = Texte(l, "Titre") l.compte:SetPoint("TOP", l, "CENTER", 0, -14) l.compte:SetJustifyH("CENTER")
	l.fleche = l:CreateTexture(nil, "OVERLAY") l.fleche:SetSize(12, 12) l.fleche:SetPoint("BOTTOM", 0, 14)
	l.fleche:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	l:RegisterForClicks("LeftButtonUp")
	l:SetScript("OnClick", function () OuvrirVolet() end)
	-- maj + glisser : monter ou descendre la languette le long du bord
	l:SetMovable(true) l:RegisterForDrag("LeftButton")
	l:SetScript("OnDragStart", function (self) if IsShiftKeyDown() and not volet:IsShown() then self:StartMoving() end end)
	l:SetScript("OnDragStop", function (self)
		self:StopMovingOrSizing()
		local haut = self:GetTop() - UIParent:GetTop()
		Reglages().y = math.floor(haut + 0.5)
		self:ClearAllPoints() self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, Reglages().y)
	end)
	l:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Opus · butin")
		GameTooltip:AddLine(etat == "toi" and "Une décision t'attend." or etat == "cours" and "Des objets circulent, rien pour toi." or "Rien en cours.", 1, 1, 1)
		GameTooltip:AddLine("Clic : ouvrir le volet. Maj + glisser : le déplacer.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	l:SetScript("OnLeave", GameTooltip_Hide)
	languette = l
end

local function CreerBanderole ()
	local b = CreateFrame("Frame", nil, UIParent)
	b:SetSize(330, 112) b:SetFrameStrata("HIGH")
	b:SetPoint("TOPLEFT", languette, "TOPRIGHT", 2, -18)
	NeufParts(b, "Panneau.tga", 512, 256, 42, 39, 18)
	local a = DEMO.appel
	local objet = CreateFrame("Button", nil, b)
	objet:SetPoint("TOPLEFT", 16, -16) objet:SetPoint("RIGHT", -16, 0) objet:SetHeight(36)
	objet.cadre = Cadre(objet, a.icone, 36) objet.cadre:SetPoint("LEFT")
	objet.nom = Texte(objet, "Nom") objet.nom:SetPoint("TOPLEFT", 46, -1) objet.nom:SetText(a.nom)
	objet.nom:SetTextColor(Qualite(a.qualite))
	objet.sous = Texte(objet, "Texte", C.pale) objet.sous:SetPoint("BOTTOMLEFT", 46, 1) objet.sous:SetText(a.resume)
	objet:SetScript("OnClick", function () OuvrirVolet(true) end)
	b.oui = BoutonPrincipal(b, "JE LE VEUX", function () FinAppel("démonstration : tu t'es déclaré pour l'Anneau d'obsidienne.") end)
	b.oui:SetPoint("TOPLEFT", objet, "BOTTOMLEFT", 0, -9)
	b.non = BoutonSecond(b, "PASSER", function () FinAppel("démonstration : tu passes l'Anneau d'obsidienne.") end)
	b.non:SetPoint("LEFT", b.oui, "RIGHT", 14, 0)
	b.temps = Texte(b, "Titre", C.acier) b.temps:SetPoint("TOPRIGHT", objet, "BOTTOMRIGHT", 0, -15) b.temps:SetJustifyH("RIGHT")
	b.barre = Aplat(b, C.encre, 0.6) b.barre:SetHeight(2)
	b.barre:SetPoint("BOTTOMLEFT", 16, 14) b.barre:SetPoint("BOTTOMRIGHT", -16, 14)
	b.reste = Aplat(b, C.acier, 1) b.reste:SetHeight(2) b.reste:SetPoint("LEFT", b.barre, "LEFT")
	b:Hide()
	banderole = b
end

local function LancerAppel ()
	if volet:IsShown() then OuvrirVolet(false) end
	reponse = nil
	local fin, duree = GetTime() + DEMO.appel.duree, DEMO.appel.duree
	local largeur = banderole.barre:GetWidth()
	banderole:SetScript("OnUpdate", function (self)
		local reste = fin - GetTime()
		if reste <= 0 then FinAppel("démonstration : sans réponse, tu passes l'Anneau d'obsidienne.") return end
		self.temps:SetText(string.format("%d:%02d", math.floor(reste / 60), math.floor(reste % 60)))
		self.reste:SetWidth(math.max(1, (largeur > 0 and largeur or 298) * reste / duree))
	end)
	banderole:Show()
	if Reglages().son ~= false then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
end

------------------------------------------------------------------------
-- le volet
------------------------------------------------------------------------

local LARGEUR, HAUTEUR = 392, 624
local INTERIEUR = LARGEUR - 14 - 20     -- la largeur utile, entre les bords du cuir

-- Une ligne du registre : gravée (un filet clair dessus, un filet noir dessous), liseré braise quand c'est à toi.
local function Ligne (parent, d, haut)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(INTERIEUR, 50)
	f:SetPoint("TOPLEFT", 0, haut)
	f.dessus = Aplat(f, C.orVif, 0.08) f.dessus:SetHeight(1) f.dessus:SetPoint("TOPLEFT") f.dessus:SetPoint("TOPRIGHT")
	f.dessous = Aplat(f, C.encre, 0.8) f.dessous:SetHeight(1) f.dessous:SetPoint("BOTTOMLEFT") f.dessous:SetPoint("BOTTOMRIGHT")
	if d.sens == "toi" then
		f.lisere = Aplat(f, C.braise, 1) f.lisere:SetWidth(3) f.lisere:SetPoint("TOPLEFT", 0, -1) f.lisere:SetPoint("BOTTOMLEFT", 0, 1)
	end
	f.cadre = Cadre(f, d.icone, 36) f.cadre:SetPoint("LEFT", 8, 0)
	f.nom = Texte(f, "Nom") f.nom:SetPoint("TOPLEFT", 52, -8) f.nom:SetText(d.nom) f.nom:SetTextColor(Qualite(d.qualite))
	f.sous = Texte(f, "Texte", C.pale) f.sous:SetPoint("BOTTOMLEFT", 52, 8) f.sous:SetText(d.sous)
	if d.etiquette then
		f.etiquette = Etiquette(f, d.etiquette, d.sens) f.etiquette:SetPoint("RIGHT", -6, 0)
		f.nom:SetPoint("TOPRIGHT", -(f.etiquette:GetWidth() + 12), -8)
	elseif d.sens then
		f.signe = Image(f, SIGNES[d.sens] .. ".tga", 14, 14) f.signe:SetPoint("RIGHT", -8, 0)
	end
	if d.pale then f:SetAlpha(d.pale) end
	return f
end

-- La ligne dépliée de l'appel : trois faits, puis la zone d'action encadrée de braise.
local function LigneAppel (parent, haut)
	local a = DEMO.appel
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(INTERIEUR, 214)
	f:SetPoint("TOPLEFT", 0, haut)
	f.fond = Aplat(f, C.encre, 0.55, "BACKGROUND") f.fond:SetAllPoints()
	f.dessus = Aplat(f, C.orVif, 0.16) f.dessus:SetHeight(1) f.dessus:SetPoint("TOPLEFT") f.dessus:SetPoint("TOPRIGHT")
	f.lisere = Aplat(f, C.braise, 1) f.lisere:SetWidth(3) f.lisere:SetPoint("TOPLEFT", 0, -1) f.lisere:SetPoint("BOTTOMLEFT", 0, 1)
	f.cadre = Cadre(f, a.icone, 36) f.cadre:SetPoint("TOPLEFT", 8, -7)
	f.nom = Texte(f, "Nom") f.nom:SetPoint("TOPLEFT", 52, -9) f.nom:SetText(a.nom) f.nom:SetTextColor(Qualite(a.qualite))
	f.sous = Texte(f, "Texte", C.pale) f.sous:SetPoint("TOPLEFT", 52, -28) f.sous:SetText("Hors liste · Suicide King")
	f.etiquette = Etiquette(f, "À TOI", "toi") f.etiquette:SetPoint("TOPRIGHT", -6, -15)

	f.phrase = Texte(f, "Texte", C.parchemin) f.phrase:SetPoint("TOPLEFT", 10, -54) f.phrase:SetPoint("TOPRIGHT", -8, -54)
	f.phrase:SetWordWrap(true)
	f.phrase:SetText("Si tu te déclares, tu passes en tête : " .. Classe("Vorthas", "WARLOCK") .. " et " .. Classe("Brannok", "WARRIOR") .. " sont derrière toi.")

	-- trois faits, séparés par des filets
	local faits = { { "POUR TOI", "+6 %", C.mousse }, { "REMPLACE", "|cff0070ddBague de l'aube|r" }, { "TON RANG SK", "2 sur 9" } }
	local l3 = (INTERIEUR - 16) / 3
	local haut3 = Aplat(f, C["or"], 0.22) haut3:SetHeight(1) haut3:SetPoint("TOPLEFT", 8, -92) haut3:SetPoint("TOPRIGHT", -8, -92)
	local bas3 = Aplat(f, C["or"], 0.22) bas3:SetHeight(1) bas3:SetPoint("TOPLEFT", 8, -134) bas3:SetPoint("TOPRIGHT", -8, -134)
	for i, fait in ipairs(faits) do
		local x = 8 + (i - 1) * l3
		local lib = Texte(f, "Etiquette", C.poussiere) lib:SetPoint("TOPLEFT", x + 4, -98) lib:SetText(fait[1])
		local val = Texte(f, i == 2 and "Texte" or "Chiffre", fait[3] or C.parchemin) val:SetPoint("TOPLEFT", x + 4, -112) val:SetText(fait[2])
		if i > 1 then local s = Aplat(f, C["or"], 0.22) s:SetWidth(1) s:SetPoint("TOPLEFT", x, -92) s:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, -134) end
	end

	-- la zone d'action : c'est là qu'on agit
	local z = CreateFrame("Frame", nil, f, "BackdropTemplate")
	z:SetPoint("TOPLEFT", 8, -142) z:SetPoint("TOPRIGHT", -8, -142) z:SetHeight(64)
	z:SetBackdrop({ bgFile = BLANC8, edgeFile = BLANC8, edgeSize = 1 })
	z:SetBackdropColor(C.braise[1], C.braise[2], C.braise[3], 0.08)
	z:SetBackdropBorderColor(C.braiseBord[1], C.braiseBord[2], C.braiseBord[3], 1)
	local rubis = Image(z, "Rubis.tga", 16, 16) rubis:SetPoint("TOPLEFT", 8, -6)
	z.titre = Texte(z, "Etiquette", C.braiseTexte) z.titre:SetPoint("LEFT", rubis, "RIGHT", 6, 0) z.titre:SetText("À TOI DE DÉCIDER")
	z.temps = Texte(z, "Texte", C.parchemin) z.temps:SetPoint("TOPRIGHT", -8, -6) z.temps:SetJustifyH("RIGHT")
	z.oui = BoutonPrincipal(z, "JE LE VEUX", function () reponse = "pris" Opus.Msg("démonstration : tu t'es déclaré.") volet:Remplir() end)
	z.oui:SetPoint("BOTTOMLEFT", 8, 6)
	z.non = BoutonSecond(z, "PASSER", function () reponse = "passe" Opus.Msg("démonstration : tu passes.") volet:Remplir() end)
	z.non:SetPoint("LEFT", z.oui, "RIGHT", 14, 0)
	z.note = Texte(z, "Petit", C.poussiere) z.note:SetPoint("BOTTOMRIGHT", -8, 12) z.note:SetJustifyH("RIGHT") z.note:SetText("sans réponse : passe")
	z.rendu = Texte(z, "Texte", C.mousse) z.rendu:SetPoint("BOTTOMLEFT", 30, 14)
	f.zone = z
	return f
end

local function CreerVolet ()
	local v = CreateFrame("Frame", "OpusVolet", UIParent)
	v:SetSize(LARGEUR, HAUTEUR) v:SetFrameStrata("HIGH") v:SetToplevel(true) v:EnableMouse(true)
	v:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
	NeufParts(v, "Cuir.tga", 256, 512, 18, 15, 20, 14)
	local c = CreateFrame("Frame", nil, v)            -- le contenu, en retrait du bord du cuir
	c:SetPoint("TOPLEFT", 14, -20) c:SetPoint("BOTTOMRIGHT", -20, 20)

	-- en-tête : l'emblème, le titre, ce qui t'attend
	local emb = c:CreateTexture(nil, "ARTWORK") emb:SetTexture("Interface\\AddOns\\Opus\\Media\\Embleme")
	emb:SetSize(40, 40) emb:SetPoint("TOPLEFT", 2, 0)
	local titre = Texte(c, "Titre", C.orVif) titre:SetPoint("TOPLEFT", 52, -2) titre:SetText(string.upper(DEMO.titre))
	local lieu = Texte(c, "Texte", C.pale) lieu:SetPoint("TOPLEFT", 52, -22) lieu:SetText(DEMO.lieu)
	v.attend = Texte(c, "Texte", C.braiseTexte) v.attend:SetPoint("TOPRIGHT", -2, -12) v.attend:SetJustifyH("RIGHT")

	-- les onglets : cartouches de l'atlas d'Auberdine, parchemin pour l'onglet ouvert, fer pour les autres
	v.onglets = {}
	local noms = { "OBJETS", "MA LISTE", "CE SOIR" }
	local lo = (INTERIEUR - 8) / 3
	for i, nom in ipairs(noms) do
		local o = CreateFrame("Button", nil, c)
		o:SetSize(lo, 26) o:SetPoint("TOPLEFT", (i - 1) * (lo + 4), -50)
		o.ouvert = CreateFrame("Frame", nil, o) o.ouvert:SetAllPoints() NeufParts(o.ouvert, "OngletOuvert.tga", 256, 128, 14, 14, 6)
		o.ferme = CreateFrame("Frame", nil, o) o.ferme:SetAllPoints() NeufParts(o.ferme, "Onglet.tga", 256, 128, 14, 14, 6)
		o.texte = Texte(o, "Etiquette") o.texte:SetPoint("CENTER", 0, 0) o.texte:SetText(nom)
		o:SetScript("OnClick", function () v.onglet = i v:Remplir() end)
		v.onglets[i] = o
	end
	local sep = c:CreateTexture(nil, "ARTWORK") sep:SetTexture(MEDIA .. "Separateur.tga")
	sep:SetPoint("TOPLEFT", -4, -78) sep:SetPoint("TOPRIGHT", 4, -78) sep:SetHeight(14)

	-- le registre
	local r = CreateFrame("Frame", nil, c)
	r:SetPoint("TOPLEFT", 0, -96) r:SetPoint("TOPRIGHT", 0, -96) r:SetHeight(400)
	v.appel = LigneAppel(r, 0)
	local y = -216
	for _, d in ipairs(DEMO.lignes) do Ligne(r, d, y) y = y - 50 end
	v.registre = r
	v.ailleurs = Texte(c, "Texte", C.poussiere) v.ailleurs:SetPoint("TOPLEFT", 8, -110)
	v.ailleurs:SetText("Démonstration : seul l'onglet Objets est rempli.")

	-- en pied : ce qui reste à tomber sur ta liste
	local pied = Aplat(c, C["or"], 0.22) pied:SetHeight(1) pied:SetPoint("BOTTOMLEFT", 0, 56) pied:SetPoint("BOTTOMRIGHT", 0, 56)
	local lib = Texte(c, "Etiquette", C.poussiere) lib:SetPoint("BOTTOMLEFT", 6, 40) lib:SetText("SUR TA LISTE, ENCORE À TOMBER")
	for i, t in ipairs(DEMO.liste) do
		local s = Texte(c, "Texte", C.pale) s:SetPoint("BOTTOMLEFT", 6, 40 - i * 18) s:SetText(t)
	end

	v.onglet = 1
	v.Remplir = function (self)
		for i, o in ipairs(self.onglets) do
			o.ouvert:SetShown(i == self.onglet) o.ferme:SetShown(i ~= self.onglet)
			if i == self.onglet then o.texte:SetTextColor(C.encreTexte[1], C.encreTexte[2], C.encreTexte[3])
			else o.texte:SetTextColor(C.pale[1], C.pale[2], C.pale[3]) end
		end
		self.registre:SetShown(self.onglet == 1) self.ailleurs:SetShown(self.onglet ~= 1)
		local z = self.appel.zone
		local attend = reponse and 1 or 2
		self.attend:SetText(attend .. " pour toi")
		z.oui:SetShown(not reponse) z.non:SetShown(not reponse) z.note:SetShown(not reponse)
		z.temps:SetShown(not reponse)
		if reponse then
			z.titre:SetText("C'EST NOTÉ") z.titre:SetTextColor(C.mousse[1], C.mousse[2], C.mousse[3])
			z.rendu:SetText(reponse == "passe" and "Tu passes." or "Tu es déclaré, résultat à la fin du tour.")
		else
			z.titre:SetText("À TOI DE DÉCIDER") z.titre:SetTextColor(C.braiseTexte[1], C.braiseTexte[2], C.braiseTexte[3])
			z.rendu:SetText("")
		end
	end
	-- le décompte de la zone d'action tourne en boucle, pour l'essai
	local debut = GetTime()
	v:SetScript("OnUpdate", function (self)
		local reste = 30 - ((GetTime() - debut) % 30)
		self.appel.zone.temps:SetText("encore |cfff1e6cf" .. string.format("%d:%02d", math.floor(reste / 60), math.floor(reste % 60)) .. "|r")
	end)
	v:SetScript("OnShow", function (self) self:Remplir() end)
	v:Hide()
	volet = v
end

------------------------------------------------------------------------
-- mise en route et commandes
------------------------------------------------------------------------

local function Creer ()
	if languette then return end
	CreerLanguette()
	CreerBanderole()
	CreerVolet()
	languette:SetFrameLevel(volet:GetFrameLevel() + 10)
	languette:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, Reglages().y or -260)
	local e = Reglages().echelle or 1
	languette:SetScale(e) banderole:SetScale(e) volet:SetScale(e)
	PoserLanguette()
end

local function Montrer (oui)
	Creer()
	languette:SetShown(oui)
	if not oui then volet:Hide() FinAppel() end
	Reglages().demo = oui or nil
end

-- le volet se ferme à l'entrée en combat ; la languette et la banderole restent
Opus.Ecoute("PLAYER_REGEN_DISABLED", function ()
	if volet and volet:IsShown() then OuvrirVolet(false) end
end)
Opus.Ecoute("PLAYER_LOGIN", function ()
	if OpusDB and OpusDB.volet and OpusDB.volet.demo then Montrer(true) end
end)

local AIDE = {
	"|cffffd100/opus volet|r — montrer ou cacher la démonstration (la languette au bord gauche)",
	"|cffffd100/opus volet appel|r — faire sortir la banderole d'un appel (30 s)",
	"|cffffd100/opus volet etat repos|cours|toi|r — le signe de la languette",
	"|cffffd100/opus volet echelle 0.8 à 1.4|r — la taille du volet, de la languette et de la banderole",
	"|cffffd100/opus volet son|r — le son de l'appel, oui ou non",
}

Opus.Commande("volet", "volet [aide]", "le volet latéral du butin, en démonstration", function (texte)
	local mot, reste = (texte or ""):match("^%s*(%S*)%s*(.-)%s*$")
	mot = (mot or ""):lower()
	if mot == "" then
		Creer()
		Montrer(not languette:IsShown())
		Opus.Msg(languette:IsShown() and "démonstration du volet : la languette est au bord gauche (/opus volet aide)." or "démonstration du volet cachée.")
	elseif mot == "appel" then
		Montrer(true) etat = "toi" PoserLanguette() LancerAppel()
	elseif mot == "etat" and (reste == "repos" or reste == "cours" or reste == "toi") then
		Montrer(true) etat = reste PoserLanguette()
	elseif mot == "echelle" and tonumber(reste) then
		local e = math.max(0.8, math.min(1.4, tonumber(reste)))
		Reglages().echelle = e
		Creer() languette:SetScale(e) banderole:SetScale(e) volet:SetScale(e)
		Opus.Msg("échelle du volet : " .. e)
	elseif mot == "son" then
		Reglages().son = (Reglages().son == false)
		Opus.Msg("son de l'appel : " .. (Reglages().son and "oui" or "non"))
	else
		Opus.Msg("le volet latéral, en démonstration :")
		for _, l in ipairs(AIDE) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
		local liste = {}
		for f in pairs(manquantes) do liste[#liste + 1] = f end
		if #liste > 0 then Opus.Msg("polices introuvables, police du jeu à la place : " .. table.concat(liste, ", ")) end
	end
end)
