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
	b.Poser = function (self, t) self.texte:SetText(t) self:SetSize(math.max(96, self.texte:GetStringWidth() + 36), 30) end
	b:Poser(texte)
	b:SetHighlightTexture(BLANC8) b:GetHighlightTexture():SetVertexColor(C.orVif[1], C.orVif[2], C.orVif[3], 0.10)
	b:SetScript("OnClick", clic)
	return b
end

-- Les autres actions : le mot seul, souligné d'un filet or.
local function BoutonSecond (parent, texte, clic)
	local b = CreateFrame("Button", nil, parent)
	b.texte = Texte(b, "Bouton", { Hex("#e7d09a") }) b.texte:SetPoint("CENTER", 0, 1) b.texte:SetText(texte)
	b.Poser = function (self, t) self.texte:SetText(t) self:SetSize(self.texte:GetStringWidth() + 6, 30) end
	b:Poser(texte)
	b.filet = Aplat(b, C["or"], 0.4) b.filet:SetHeight(1)
	b.filet:SetPoint("BOTTOMLEFT", 0, 4) b.filet:SetPoint("BOTTOMRIGHT", 0, 4)
	b:SetScript("OnEnter", function (self) self.texte:SetTextColor(C.orVif[1], C.orVif[2], C.orVif[3]) end)
	b:SetScript("OnLeave", function (self) self.texte:SetTextColor(Hex("#e7d09a")) end)
	b:SetScript("OnClick", clic)
	return b
end

-- Un nom à choisir (le vote) : le nom à la couleur de sa classe, dans un cadre sombre à filet or.
local function BoutonNom (parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ bgFile = BLANC8, edgeFile = BLANC8, edgeSize = 1 })
	b:SetBackdropColor(0, 0, 0, 0.35) b:SetBackdropBorderColor(C.orSombre[1], C.orSombre[2], C.orSombre[3], 1)
	b.texte = Texte(b, "Nom") b.texte:SetPoint("CENTER", 0, 0)
	b.Poser = function (self, t) self.texte:SetText(t) self:SetSize(math.max(64, self.texte:GetStringWidth() + 22), 30) end
	b:SetScript("OnEnter", function (self) self:SetBackdropBorderColor(C["or"][1], C["or"][2], C["or"][3], 1) end)
	b:SetScript("OnLeave", function (self) self:SetBackdropBorderColor(C.orSombre[1], C.orSombre[2], C.orSombre[3], 1) end)
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
	elseif sens == "attente" then bord, couleur = { Hex("#5a606a") }, C.acier
	elseif sens == "cendre" then bord, couleur = C.cendre, C.poussiere end
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
-- les objets : ce client range ces fonctions dans C_Item (comme ButinGroupe.lua)
local InfoObjet = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local InfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local IconeObjet = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local Demander = C_Item and C_Item.RequestLoadItemDataByID
local function Icone (id, chemin)
	-- l'icône se lit sans attendre le serveur (GetItemInfoInstant), le nom non
	local icone = id and ((InfoInstant and select(5, InfoInstant(id))) or (IconeObjet and IconeObjet(id)))
	return icone or chemin or "Interface\\Icons\\INV_Misc_QuestionMark"
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
		nom = "Anneau d'obsidienne", icone = Icone(19147), qualite = 4,
		resume = "Suicide King · tu es 2e de la liste",
		duree = 30,
	},
	lignes = {
		{ nom = "Ceinture de braises", icone = Icone(19137), qualite = 4,
		  sous = Classe("Seliane", "DRUID") .. " ou " .. Classe("Vorthas", "WARLOCK") .. " · 5 sur 9 ont voté", etiquette = "VOTER", sens = "toi" },
		{ nom = "Gantelets de flammèche", icone = Icone(19143), qualite = 4,
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
-- les appels : ce qui attend le joueur, et ce qu'on lui dit
------------------------------------------------------------------------

-- Un appel, c'est une banderole possible :
--   genre "decision" : à toi de choisir avant la fin (boutons, ou les noms des candidats) ;
--   genre "info"     : ça te concerne et tu dois le comprendre (objet proposé, objection, vote en cours), sans bouton ;
--   genre "resultat" : ce qui vient d'être tranché, quelques secondes.
-- { id, genre, objet = { nom, icone, qualite }, sous, detail, fin, duree, boutons = { { texte, clic, principal } },
--   candidats = { { nom, classe, clic } }, sansReponse = texte (et fonction auSansReponse), apres }
-- Une seule banderole à la fois : les décisions d'abord (celle qui finit le plus tôt), puis les infos, puis les résultats.
local appels = {}
local Demo = {}                         -- la démonstration (en bas du fichier)
local montre                            -- l'appel dans la banderole
local languette, banderole, volet
local etatForce                         -- /opus volet etat : le signe imposé, pour l'essai
local reponse                           -- la réponse du joueur au Suicide King de la démonstration
local derniereDecision                  -- pour refermer le volet non épinglé, un moment après
local GLISSE = 0.2                      -- la durée d'une entrée ou d'une sortie

local function Reglages ()
	OpusDB.volet = OpusDB.volet or {}
	return OpusDB.volet
end

local LARGEUR, HAUTEUR = 392, 624
local DECALAGE = 66                     -- la languette, sous le haut du volet ouvert
local LARGEUR_B = 340                   -- la banderole

local function PourToi ()
	local n = 0
	for _, a in pairs(appels) do if a.genre == "decision" and not a.clos then n = n + 1 end end
	return n
end
local function Etat ()
	if etatForce then return etatForce end
	if PourToi() > 0 then return "toi" end
	for _, a in pairs(appels) do if not a.clos then return "cours" end end
	return "repos"
end

------------------------------------------------------------------------
-- glisser : la banderole et le volet entrent et sortent par le bord
------------------------------------------------------------------------

local glissements = {}                  -- [cadre] = { de, a, debut, fini }
local moteur = CreateFrame("Frame")
local Placer

local function Lisse (t) return 1 - (1 - t) * (1 - t) end
moteur:SetScript("OnUpdate", function ()
	local now = GetTime()
	local bouge = next(glissements) ~= nil
	for f, g in pairs(glissements) do
		local t = math.min(1, (now - g.debut) / GLISSE)
		f.decal = g.de + (g.a - g.de) * Lisse(t)
		if t >= 1 then glissements[f] = nil if g.fini then g.fini() end end
	end
	-- un appel arrivé au bout de son temps tombe de lui-même, montré ou non
	for id, a in pairs(appels) do
		if a.fin and not a.clos and now >= a.fin then
			if a.genre ~= "decision" then Volet.Retirer(id)
			else
				if a.auSansReponse then a.auSansReponse() end
				Volet.Clore(id, a.sansReponse or "Temps écoulé.")
			end
		end
	end
	if languette and (bouge or languette.enDrag) then Placer() end
	-- le volet non épinglé se referme un moment après la dernière décision, s'il ne reste rien pour toi
	if volet and volet:IsShown() and not volet.sortant and derniereDecision and not Reglages().epingle
		and GetTime() - derniereDecision > 6 and PourToi() == 0 and not volet:IsMouseOver() then
		derniereDecision = nil
		Volet.Ouvrir(false)
	end
end)

local function Glisser (f, sortir, largeur, fini)
	if sortir then f:Show() end
	glissements[f] = { de = f.decal or (sortir and -largeur or 0), a = sortir and 0 or -largeur, debut = GetTime(),
		fini = function () if not sortir then f:Hide() end if fini then fini() end end }
end

-- La languette garde sa hauteur (glissée à la souris) ; ouvert, le volet se cale sur elle sans sortir de l'écran.
function Placer ()
	local y = Reglages().y or -260
	local hauteurEcran = UIParent:GetHeight() * UIParent:GetEffectiveScale() / languette:GetEffectiveScale()
	y = math.max(-(hauteurEcran - languette:GetHeight()), math.min(0, y))
	local dv = volet:IsShown() and (LARGEUR + (volet.decal or 0)) or 0
	local haut = math.max(-(hauteurEcran - HAUTEUR), math.min(0, y + DECALAGE))
	volet:ClearAllPoints() volet:SetPoint("TOPLEFT", UIParent, "TOPLEFT", volet.decal or 0, haut)
	languette:ClearAllPoints() languette:SetPoint("TOPLEFT", UIParent, "TOPLEFT", math.max(0, dv - 2), y)
	banderole:ClearAllPoints() banderole:SetPoint("TOPLEFT", languette, "TOPRIGHT", 2 + (banderole.decal or 0), -14)
end

local function PoserLanguette ()
	if not languette then return end
	local l, etat = languette, Etat()
	l.gemme:SetShown(etat ~= "toi") l.rubis:SetShown(etat == "toi")
	l.gemme:SetDesaturated(etat == "repos") l.gemme:SetAlpha(etat == "repos" and 0.5 or 1)
	local n = 0
	for _, a in pairs(appels) do if not a.clos then n = n + 1 end end
	if etat == "toi" then l.compte:SetText(etatForce and 2 or PourToi()) l.compte:SetTextColor(C.braiseTexte[1], C.braiseTexte[2], C.braiseTexte[3])
	elseif etat == "cours" then l.compte:SetText(etatForce and 4 or n) l.compte:SetTextColor(C.orVif[1], C.orVif[2], C.orVif[3])
	else l.compte:SetText("") end
	local ouvert = volet and volet:IsShown() and not volet.sortant
	l.fleche:SetTexture(ouvert and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	-- le rubis bat doucement tant qu'une décision attend et que le volet est fermé
	if etat == "toi" and not ouvert then l.pouls:Play() else l.pouls:Stop() l.rubis:SetAlpha(1) end
	if volet and volet.Remplir and volet:IsShown() then volet:Remplir() end
end

local Choisir

-- Le volet ne s'ouvre jamais tout seul : un clic sur la languette ou sur l'objet de la banderole.
function Volet.Ouvrir (ouvrir)
	if ouvrir == nil then ouvrir = not volet:IsShown() or volet.sortant end
	if ouvrir and InCombatLockdown() and not Reglages().epingle then Opus.Msg("le volet reste fermé en combat.") return end
	volet.sortant = not ouvrir or nil
	if ouvrir then
		if not volet:IsShown() then volet.decal = -LARGEUR end
		Glisser(volet, true, LARGEUR)
		if banderole:IsShown() then Glisser(banderole, false, LARGEUR_B) end
	else
		Glisser(volet, false, LARGEUR, function () volet.sortant = nil Choisir() end)
	end
	PoserLanguette()
end

------------------------------------------------------------------------
-- la banderole
------------------------------------------------------------------------

local function Temps (s) return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end

local function Rang (a)
	local r = a.genre == "decision" and 0 or a.genre == "info" and 1e6 or 2e6
	return r + (a.fin or 1e5)
end

-- ce que la banderole montre, mis en page selon l'appel
local function Remplir (a)
	local b = banderole
	b.appel = a
	b.objet.cadre.icone:SetTexture(a.objet.icone)
	b.objet.nom:SetText(a.objet.nom) b.objet.nom:SetTextColor(Qualite(a.objet.qualite or 4))
	b.objet.sous:SetText(a.sous or "")
	local y = -16 - 36
	b.detail:SetShown(a.detail ~= nil)
	if a.detail then
		b.detail:SetText(a.detail)
		b.detail:ClearAllPoints() b.detail:SetPoint("TOPLEFT", 16, y - 8) b.detail:SetWidth(LARGEUR_B - 32)
		y = y - 8 - b.detail:GetStringHeight()
	end
	-- les actions : les boutons, ou les noms des candidats
	b.prim:Hide() b.sec:Hide()
	for _, n in ipairs(b.noms) do n:Hide() end
	local x, actions = 16, false
	if not a.clos and a.boutons then
		for _, bt in ipairs(a.boutons) do
			local w = bt.principal and b.prim or b.sec
			w:Poser(bt.texte) w:SetScript("OnClick", bt.clic)
			w:ClearAllPoints() w:SetPoint("TOPLEFT", x, y - 10) w:Show()
			x = x + w:GetWidth() + 14 actions = true
		end
	elseif not a.clos and a.candidats then
		for i, c in ipairs(a.candidats) do
			local w = b.noms[i]
			if w then
				w:Poser(Classe(c.nom, c.classe)) w:SetScript("OnClick", c.clic)
				w:ClearAllPoints() w:SetPoint("TOPLEFT", x, y - 10) w:Show()
				x = x + w:GetWidth() + 6 actions = true
			end
		end
	end
	-- une fois clos : la réponse, à la place des actions
	b.rendu:SetShown(a.clos ~= nil)
	if a.clos then
		b.rendu:SetText(a.clos) b.rendu:ClearAllPoints() b.rendu:SetPoint("TOPLEFT", 16, y - 10)
		y = y - 10 - 20
	elseif actions then
		y = y - 10 - 30
	end
	-- le temps : au bout de la rangée des actions, ou seul au-dessus de la barre
	local compte = a.fin ~= nil and not a.clos and a.genre ~= "resultat"
	b.temps:ClearAllPoints()
	if actions then b.temps:SetPoint("RIGHT", b, "TOPRIGHT", -16, y + 20)
	elseif compte then b.temps:SetPoint("BOTTOMRIGHT", -16, 20) y = y - 22 end
	b.temps:SetShown(compte)
	b.barre:SetShown(compte and a.duree ~= nil) b.reste:SetShown(b.barre:IsShown())
	-- le liseré gauche dit le genre : braise pour une décision, or pour une info, rien pour un résultat
	b.lisere:SetShown(a.genre ~= "resultat")
	local c = a.genre == "decision" and C.braise or C["or"]
	b.lisere:SetVertexColor(c[1], c[2], c[3], 1)
	b:SetHeight(-y + 24)
end

-- Choisir l'appel à montrer, et faire entrer, changer ou sortir la banderole.
function Choisir ()
	if not banderole then return end
	local meilleur
	for _, a in pairs(appels) do
		if not a.clos and (not meilleur or Rang(a) < Rang(meilleur)) then meilleur = a end
	end
	if montre and montre.clos then return end      -- la réponse reste lisible, puis l'appel s'en va
	local ouvert = volet:IsShown() and not volet.sortant
	if not meilleur or ouvert then
		montre = nil
		if banderole:IsShown() and not glissements[banderole] then Glisser(banderole, false, LARGEUR_B) end
		PoserLanguette()
		return
	end
	montre = meilleur
	Remplir(meilleur)
	local g = glissements[banderole]
	if not banderole:IsShown() or (g and g.a < 0) then
		if not banderole:IsShown() then banderole.decal = -LARGEUR_B end
		Glisser(banderole, true, LARGEUR_B)
	end
	-- un son, une fois, quand une décision se montre pour la première fois
	if meilleur.genre == "decision" and not meilleur.sonne then
		meilleur.sonne = true
		if Reglages().son ~= false then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
	end
	PoserLanguette()
end

-- Un appel arrive, ou change (même id) : il prend sa place dans la file.
function Volet.Appeler (a)
	appels[a.id] = a
	if montre and montre.id == a.id then montre = a Remplir(a) end
	if a.genre == "resultat" and not a.fin then a.fin = GetTime() + 6 end
	Choisir()
end

-- C'est décidé (ici, au chat, par la fin du temps ou par les officiers) : la réponse reste deux secondes, puis
-- la banderole rentre ou passe à l'appel suivant.
function Volet.Clore (id, texte)
	local a = appels[id]
	if not a or a.clos then return end
	a.clos = texte or "C'est noté."
	if a.genre == "decision" then derniereDecision = GetTime() end
	if montre == a then
		Remplir(a)
		C_Timer.After(2, function ()
			if appels[id] == a then appels[id] = nil end
			if montre == a then montre = nil end
			Choisir()
		end)
	else
		appels[id] = nil
		Choisir()
	end
	PoserLanguette()
end

function Volet.Retirer (id)
	if appels[id] == montre then montre = nil end
	appels[id] = nil
	Choisir()
end

------------------------------------------------------------------------
-- création de la languette et de la banderole
------------------------------------------------------------------------

local function CreerLanguette ()
	local l = CreateFrame("Button", "OpusVoletLanguette", UIParent)
	l:SetSize(30, 128) l:SetFrameStrata("HIGH") l:SetClampedToScreen(true)
	NeufParts(l, "Panneau.tga", 512, 256, 42, 39, 10, 0)
	-- une ombre portée vers l'écran, peinte en dégradé, pour détacher la languette du décor
	l.ombre = l:CreateTexture(nil, "BACKGROUND", nil, -8)
	l.ombre:SetPoint("TOPLEFT", l, "TOPRIGHT", -3, -6) l.ombre:SetPoint("BOTTOMLEFT", l, "BOTTOMRIGHT", -3, 6) l.ombre:SetWidth(10)
	l.ombre:SetTexture(BLANC8)
	if not (CreateColor and pcall(l.ombre.SetGradient, l.ombre, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))) then
		l.ombre:SetVertexColor(0, 0, 0, 0.3)
	end
	-- le contenu se centre sur le cuir, pas sur la languette entière (le bord ouvragé de droite en mange une part)
	local cx = -2
	l.gemme = Image(l, "Gemme.tga", 18, 36) l.gemme:SetPoint("CENTER", cx, 12)
	l.rubis = Image(l, "Rubis.tga", 24, 24) l.rubis:SetPoint("CENTER", cx, 14)
	l.compte = Texte(l, "Titre") l.compte:SetPoint("TOP", l, "CENTER", cx, -8) l.compte:SetJustifyH("CENTER")
	l.fleche = l:CreateTexture(nil, "OVERLAY") l.fleche:SetSize(14, 14) l.fleche:SetPoint("BOTTOM", cx, 12)
	l.fleche:SetVertexColor(C["or"][1], C["or"][2], C["or"][3])
	l.pouls = l.rubis:CreateAnimationGroup() l.pouls:SetLooping("BOUNCE")
	local a = l.pouls:CreateAnimation("Alpha") a:SetFromAlpha(1) a:SetToAlpha(0.55) a:SetDuration(0.9) a:SetSmoothing("IN_OUT")
	l:SetHighlightTexture(BLANC8)
	local h = l:GetHighlightTexture() h:ClearAllPoints() h:SetPoint("TOPLEFT", 0, -6) h:SetPoint("BOTTOMRIGHT", -8, 6)
	h:SetVertexColor(C.orVif[1], C.orVif[2], C.orVif[3], 0.07)
	l:RegisterForClicks("LeftButtonUp")
	l:SetScript("OnClick", function (self)
		if self.glisse then self.glisse = nil return end
		Volet.Ouvrir()
	end)
	-- glisser : monter ou descendre la languette le long du bord (le volet ouvert la suit)
	l:RegisterForDrag("LeftButton")
	l:SetScript("OnDragStart", function (self)
		self.glisse, self.enDrag = true, true
		local _, depart = GetCursorPosition()
		local y0 = Reglages().y or -260
		self:SetScript("OnUpdate", function (s)
			local _, y = GetCursorPosition()
			Reglages().y = y0 + (y - depart) / s:GetEffectiveScale()
		end)
	end)
	l:SetScript("OnDragStop", function (self)
		self:SetScript("OnUpdate", nil)
		Reglages().y = math.floor((Reglages().y or -260) + 0.5)
		Placer() self.enDrag = nil
	end)
	l:SetScript("OnEnter", function (self)
		local etat = Etat()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Opus · butin")
		GameTooltip:AddLine(etat == "toi" and "Une décision t'attend." or etat == "cours" and "Des objets circulent, rien pour toi." or "Rien en cours.", 1, 1, 1)
		GameTooltip:AddLine("Clic : ouvrir le volet. Glisser : la monter ou la descendre.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	l:SetScript("OnLeave", GameTooltip_Hide)
	languette = l
end

local function CreerBanderole ()
	local b = CreateFrame("Frame", nil, UIParent)
	b:SetSize(LARGEUR_B, 112) b:SetFrameStrata("HIGH")
	NeufParts(b, "Panneau.tga", 512, 256, 42, 39, 18)
	b.lisere = Aplat(b, C.braise, 1) b.lisere:SetWidth(3) b.lisere:SetPoint("TOPLEFT", 6, -14) b.lisere:SetPoint("BOTTOMLEFT", 6, 14)
	local objet = CreateFrame("Button", nil, b)
	objet:SetPoint("TOPLEFT", 16, -16) objet:SetPoint("TOPRIGHT", -16, -16) objet:SetHeight(36)
	objet.cadre = Cadre(objet, nil, 36) objet.cadre:SetPoint("LEFT")
	objet.nom = Texte(objet, "Nom") objet.nom:SetPoint("TOPLEFT", 46, -1) objet.nom:SetPoint("TOPRIGHT", 0, -1)
	objet.sous = Texte(objet, "Texte", C.pale) objet.sous:SetPoint("BOTTOMLEFT", 46, 1) objet.sous:SetPoint("BOTTOMRIGHT", 0, 1)
	objet:SetScript("OnClick", function () Volet.Ouvrir(true) end)
	objet:SetScript("OnEnter", function (self)
		local a = b.appel
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(a and a.objet.nom or "")
		for _, l in ipairs(a and a.explication or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
		GameTooltip:AddLine("Clic : ouvrir le volet.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	objet:SetScript("OnLeave", GameTooltip_Hide)
	b.objet = objet
	b.detail = Texte(b, "Texte", C.parchemin) b.detail:SetWordWrap(true)
	b.prim = BoutonPrincipal(b, "", nil)
	b.sec = BoutonSecond(b, "", nil)
	b.noms = { BoutonNom(b), BoutonNom(b), BoutonNom(b) }
	b.rendu = Texte(b, "Nom", C.pale)
	b.temps = Texte(b, "Titre", C.acier) b.temps:SetJustifyH("RIGHT")
	b.barre = Aplat(b, C.encre, 0.6) b.barre:SetHeight(2)
	b.barre:SetPoint("BOTTOMLEFT", 16, 14) b.barre:SetPoint("BOTTOMRIGHT", -16, 14)
	b.reste = Aplat(b, C.acier, 1) b.reste:SetHeight(2) b.reste:SetPoint("LEFT", b.barre, "LEFT")
	-- le temps qui reste ; à zéro, la décision tombe d'elle-même (« sans réponse : … »)
	b:SetScript("OnUpdate", function (self)
		local a = self.appel
		if not a or a.clos or not a.fin then return end
		local reste = math.max(0, a.fin - GetTime())
		self.temps:SetText(Temps(reste))
		if a.duree then self.reste:SetWidth(math.max(1, (LARGEUR_B - 32) * reste / a.duree)) end
	end)
	b:Hide()
	banderole = b
end

------------------------------------------------------------------------
-- le volet
------------------------------------------------------------------------

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
	f.declare = Etiquette(f, "DÉCLARÉ", "attente") f.declare:SetPoint("TOPRIGHT", -6, -15)
	f.passe = Etiquette(f, "PASSÉ", "cendre") f.passe:SetPoint("TOPRIGHT", -6, -15)

	f.phrase = Texte(f, "Texte", C.parchemin) f.phrase:SetPoint("TOPLEFT", 10, -54) f.phrase:SetPoint("TOPRIGHT", -8, -54)
	f.phrase:SetWordWrap(true)
	f.phrase:SetText("Si tu te déclares, tu passes en tête : " .. Classe("Vorthas", "WARLOCK") .. " et " .. Classe("Brannok", "WARRIOR") .. " sont derrière toi.")

	-- trois faits, séparés par des filets
	local faits = { { "GAIN (PAWN)", "+6 %", C.mousse }, { "REMPLACE", "|cff0070ddBague de l'aube|r" }, { "TON RANG SK", "2 sur 9" } }
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
	z.signe = Image(z, "Rubis.tga", 16, 16) z.signe:SetPoint("TOPLEFT", 8, -6)
	z.titre = Texte(z, "Etiquette", C.braiseTexte) z.titre:SetPoint("TOPLEFT", 30, -9) z.titre:SetText("À TOI DE DÉCIDER")
	z.temps = Texte(z, "Texte", C.parchemin) z.temps:SetPoint("TOPRIGHT", -8, -6) z.temps:SetJustifyH("RIGHT")
	z.oui = BoutonPrincipal(z, "JE LE VEUX", function () Demo.Repondre("pris") end)
	z.oui:SetPoint("BOTTOMLEFT", 8, 6)
	z.non = BoutonSecond(z, "PASSER", function () Demo.Repondre("passe") end)
	z.non:SetPoint("LEFT", z.oui, "RIGHT", 14, 0)
	z.note = Texte(z, "Petit", C.poussiere) z.note:SetPoint("BOTTOMRIGHT", -8, 12) z.note:SetJustifyH("RIGHT") z.note:SetText("sans réponse : passe")
	z.rendu = Texte(z, "Texte", C.mousse) z.rendu:SetPoint("BOTTOMLEFT", 30, 14)
	f.zone = z
	return f
end

local function CreerVolet ()
	local v = CreateFrame("Frame", "OpusVolet", UIParent)
	v:SetSize(LARGEUR, HAUTEUR) v:SetFrameStrata("HIGH") v:SetToplevel(true) v:EnableMouse(true)
	NeufParts(v, "Cuir.tga", 256, 512, 18, 15, 20, 14)
	local c = CreateFrame("Frame", nil, v)            -- le contenu, en retrait du bord du cuir
	c:SetPoint("TOPLEFT", 14, -20) c:SetPoint("BOTTOMRIGHT", -20, 20)

	-- en-tête : l'emblème, le titre, ce qui t'attend
	local emb = c:CreateTexture(nil, "ARTWORK") emb:SetTexture("Interface\\AddOns\\Opus\\Media\\Embleme")
	emb:SetSize(40, 40) emb:SetPoint("TOPLEFT", 2, 0)
	local titre = Texte(c, "Titre", C.orVif) titre:SetPoint("TOPLEFT", 52, -2) titre:SetText(string.upper(DEMO.titre))
	v.lieu = Texte(c, "Texte", C.pale) v.lieu:SetPoint("TOPLEFT", 52, -22) v.lieu:SetText(DEMO.lieu)
	-- l'épingle : le volet reste ouvert (même en combat) tant qu'elle est mise
	local ep = CreateFrame("Button", nil, c)
	ep:SetSize(20, 20) ep:SetPoint("TOPRIGHT", -2, -2)
	ep.image = ep:CreateTexture(nil, "ARTWORK") ep.image:SetAllPoints()
	ep:SetHighlightTexture(BLANC8) ep:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
	ep.Poser = function (self)
		local mise = Reglages().epingle
		self.image:SetTexture(mise and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
		self.image:SetAlpha(mise and 1 or 0.6)
	end
	ep:SetScript("OnClick", function (self) Reglages().epingle = not Reglages().epingle or nil self:Poser() end)
	ep:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Reglages().epingle and "Épinglé : le volet reste ouvert." or "Épingler : garder le volet ouvert, même en combat.")
		GameTooltip:Show()
	end)
	ep:SetScript("OnLeave", GameTooltip_Hide)
	ep:Poser()
	v.attend = Texte(c, "Texte", C.braiseTexte) v.attend:SetPoint("TOPRIGHT", -2, -26) v.attend:SetJustifyH("RIGHT")

	-- les onglets : cartouches de l'atlas d'Auberdine, parchemin pour l'onglet ouvert, fer pour les autres
	v.onglets = {}
	local noms = { "OBJETS", "MA LISTE", "CE SOIR" }
	local lo = (INTERIEUR - 8) / 3
	for i, nom in ipairs(noms) do
		local o = CreateFrame("Button", nil, c)
		o:SetSize(lo, 26) o:SetPoint("TOPLEFT", (i - 1) * (lo + 4), -50)
		o.ouvert = CreateFrame("Frame", nil, o) o.ouvert:SetAllPoints() NeufParts(o.ouvert, "OngletOuvert.tga", 256, 128, 14, 14, 6)
		o.ferme = CreateFrame("Frame", nil, o) o.ferme:SetAllPoints() NeufParts(o.ferme, "Onglet.tga", 256, 128, 14, 14, 6)
		o.dessus = CreateFrame("Frame", nil, o) o.dessus:SetAllPoints() o.dessus:SetFrameLevel(o:GetFrameLevel() + 3)
		o.texte = Texte(o.dessus, "Etiquette") o.texte:SetPoint("CENTER", 0, 0) o.texte:SetText(nom)
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
	-- le registre en direct : les annonces du maître du butin (plus bas, « le butin en direct »)
	v.direct = CreateFrame("Frame", nil, c)
	v.direct:SetPoint("TOPLEFT", 0, -96) v.direct:SetPoint("BOTTOMRIGHT", 0, 0)
	v.direct.lignes = {}
	v.direct.vide = Texte(v.direct, "Texte", C.poussiere) v.direct.vide:SetPoint("TOPLEFT", 8, -14)
	v.direct.vide:SetText("Rien en cours. Les annonces du maître du butin arrivent ici.")
	v.direct.plus = Texte(v.direct, "Petit", C.poussiere) v.direct.plus:SetPoint("BOTTOMLEFT", 8, 2)
	v.ailleurs = Texte(c, "Texte", C.poussiere) v.ailleurs:SetPoint("TOPLEFT", 8, -110)
	v.ailleurs:SetText("Démonstration : seul l'onglet Objets est rempli.")

	-- en pied : ce qui reste à tomber sur ta liste
	v.pied = CreateFrame("Frame", nil, c) v.pied:SetAllPoints()
	local pied = Aplat(v.pied, C["or"], 0.22) pied:SetHeight(1) pied:SetPoint("BOTTOMLEFT", 0, 56) pied:SetPoint("BOTTOMRIGHT", 0, 56)
	local lib = Texte(v.pied, "Etiquette", C.poussiere) lib:SetPoint("BOTTOMLEFT", 6, 40) lib:SetText("SUR TA LISTE, ENCORE À TOMBER")
	for i, t in ipairs(DEMO.liste) do
		local s = Texte(v.pied, "Texte", C.pale) s:SetPoint("BOTTOMLEFT", 6, 40 - i * 18) s:SetText(t)
	end

	v.onglet = 1
	v.Remplir = function (self)
		for i, o in ipairs(self.onglets) do
			o.ouvert:SetShown(i == self.onglet) o.ferme:SetShown(i ~= self.onglet)
			if i == self.onglet then o.texte:SetTextColor(C.encreTexte[1], C.encreTexte[2], C.encreTexte[3])
			else o.texte:SetTextColor(C.pale[1], C.pale[2], C.pale[3]) end
		end
		-- la démonstration montre son registre figé ; sinon, le butin en direct
		local demo = Demo.actif
		self.registre:SetShown(demo and self.onglet == 1) self.pied:SetShown(demo)
		self.direct:SetShown(not demo and self.onglet == 1)
		self.ailleurs:SetShown(self.onglet ~= 1)
		self.ailleurs:SetText(demo and "Démonstration : seul l'onglet Objets est rempli." or "Bientôt : ta liste et la soirée, ici.")
		self.lieu:SetText(demo and DEMO.lieu or (GetRealZoneText and GetRealZoneText() or ""))
		if not demo then
			local n = PourToi()
			self.attend:SetText(n > 0 and (n .. " pour toi") or "")
			if Volet.RemplirDirect then Volet.RemplirDirect(self.direct) end
			return
		end
		local z = self.appel.zone
		local n = PourToi()
		self.attend:SetText(n > 0 and (n .. " pour toi") or "")
		local a = self.appel
		a.lisere:SetShown(not reponse)
		a.etiquette:SetShown(not reponse) a.declare:SetShown(reponse == "pris") a.passe:SetShown(reponse == "passe")
		z.oui:SetShown(not reponse) z.non:SetShown(not reponse) z.note:SetShown(not reponse)
		z.temps:Show()
		-- après la réponse, la zone se calme : sablier d'acier si tu es déclaré (on attend la fin du tour),
		-- cendre si tu passes ; le vert reste pour ce qui est tranché
		if reponse == "pris" then
			z:SetBackdropColor(0, 0, 0, 0.25) z:SetBackdropBorderColor(Hex("#5a606a"))
			z.signe:SetTexture(MEDIA .. "Sablier.tga") z.signe:Show()
			z.titre:SetText("TU ES DÉCLARÉ") z.titre:SetTextColor(C.acier[1], C.acier[2], C.acier[3])
			z.rendu:SetText("Résultat à la fin du tour.") z.rendu:SetTextColor(C.pale[1], C.pale[2], C.pale[3])
		elseif reponse == "passe" then
			z:SetBackdropColor(0, 0, 0, 0.25) z:SetBackdropBorderColor(C.cendre[1], C.cendre[2], C.cendre[3])
			z.signe:Hide()
			z.titre:SetText("TU PASSES") z.titre:SetTextColor(C.poussiere[1], C.poussiere[2], C.poussiere[3])
			z.rendu:SetText("")
		else
			z:SetBackdropColor(C.braise[1], C.braise[2], C.braise[3], 0.08) z:SetBackdropBorderColor(C.braiseBord[1], C.braiseBord[2], C.braiseBord[3])
			z.signe:SetTexture(MEDIA .. "Rubis.tga") z.signe:Show()
			z.titre:SetText("À TOI DE DÉCIDER") z.titre:SetTextColor(C.braiseTexte[1], C.braiseTexte[2], C.braiseTexte[3])
			z.rendu:SetText("")
		end
	end
	-- le décompte de la zone d'action : celui de l'appel du Suicide King, s'il court
	v:SetScript("OnUpdate", function (self)
		local a = appels.sk
		local reste = a and a.fin and not a.clos and (a.fin - GetTime())
		self.appel.zone.temps:SetText(reste and reste > 0 and ("encore |cfff1e6cf" .. Temps(reste) .. "|r") or "")
	end)
	v:SetScript("OnShow", function (self) self:Remplir() end)
	v:Hide()
	volet = v
end

------------------------------------------------------------------------
-- le butin en direct : les annonces du maître du butin (RaidVote.lua) deviennent des lignes du volet et, quand elles
-- te concernent, des banderoles
------------------------------------------------------------------------

local Raid = Opus.Raid
local TRAINE = 600                      -- la languette reste dix minutes après la dernière annonce
local finAnnonces                       -- quand la dernière annonce s'est finie
local deplie                            -- la ligne dépliée du volet
local TOI_ = "|cffff8a5ctoi|r"

local function Signe (nom) return "|T" .. MEDIA .. nom .. ":14:14|t " end
local function Cle (a) return "r" .. a.ml .. "#" .. a.n end
local function Moi () return Raid.MonNom() end
local function Chrono (a) return a.fin and Temps(math.max(0, a.fin - GetTime())) or "" end
local function Nom (nom)
	if not nom or nom == "" then return "?" end
	if nom == Moi() then return TOI_ end
	local _, classe = UnitClass(nom)
	return classe and Classe(nom, classe) or nom
end
local function Noms (liste, max)
	local t = {}
	for k, n in ipairs(liste or {}) do if k <= (max or 4) then t[#t + 1] = Nom(n) end end
	if #(liste or {}) > (max or 4) then t[#t + 1] = "+" .. (#liste - (max or 4)) end
	return table.concat(t, " · ")
end
local function Contient (liste, nom) for _, n in ipairs(liste or {}) do if n == nom then return true end end end

local function ObjetDe (a)
	local nom, _, qualite = InfoObjet(a.id)
	-- pas encore connu de ce client : on le demande au serveur, le nom arrive au rafraîchissement suivant
	if not nom and Demander then pcall(Demander, a.id) end
	return { nom = nom or (a.lien and a.lien:match("%[(.-)%]")) or ("objet " .. a.id), icone = Icone(a.id), qualite = qualite or 4 }
end

-- ta place dans la liste Suicide King (l'instantané de la soirée, s'il est là)
local function RangSK (nom)
	local liste = Raid.ListeSK and Raid.ListeSK() or {}
	for k, n in ipairs(liste) do if n == nom then return k, #liste end end
end
local function Ordinal (k) return k == 1 and "1er" or (k .. "e") end

-- Répondre au maître du butin : par message d'addon, sinon dans le canal raid.
local function Envoyer (a, mot, chat, quoi)
	if not Raid.Repondre(mot, a.n, quoi) and IsInGroup() then SendChatMessage(chat, IsInRaid() and "RAID" or "PARTY") end
	Raid.RafraichirVote()
end

-- Ce qu'une annonce devient pour toi : sa ligne (sous, étiquette), et son appel s'il te concerne.
-- d = { sous, etiquette = { texte, sens }, appel = {…} ou nil, clos = texte (la banderole montre la réponse puis rentre),
--       explication, concerne }
local function Decrire (a)
	local moi = Moi()
	local objet = ObjetDe(a)
	local d = { objet = objet }
	local temps = a.fin and (a.etat == "delai" or a.etat == "vote" or a.etat == "sk")
	local function Appel (genre, t)
		t.genre, t.objet = genre, objet
		if temps and not t.fin then t.fin, t.duree = a.fin, a.duree end
		d.appel = t
	end
	local autres = {}
	for _, n in ipairs(a.etat == "vote" and a.choix or a.candidats or {}) do
		-- les autres candidats présents : on ne laisse pas un objet à un absent
		if n ~= moi and (not IsInGroup() or UnitInRaid(n) or UnitInParty(n)) then autres[#autres + 1] = n end
	end
	-- « Le laisser » : les autres candidats, un clic sur un nom
	local function Laisser (t)
		if #autres == 0 then return end
		t.boutons = t.boutons or {}
		table.insert(t.boutons, { texte = "LE LAISSER", clic = function () a.laisser = true Raid.RafraichirVote() end })
	end
	if a.laisser and (a.etat == "delai" or a.etat == "vote") and not a.laisse then
		local c = {}
		for k, n in ipairs(autres) do
			if k <= 3 then c[#c + 1] = { nom = n, classe = select(2, UnitClass(n)), clic = function ()
				a.laisse = n Envoyer(a, "L", "!laisse " .. a.n .. " " .. n, n) end } end
		end
		d.sous, d.etiquette = "Le laisser à qui ?", { "À TOI", "toi" }
		d.explication = { "Tu renonces à l'objet : il va à qui tu choisis.", "Sans choix avant la fin, tu le gardes." }
		Appel("decision", { sous = d.sous, candidats = c, explication = d.explication,
			sansReponse = "Tu le gardes.", auSansReponse = function () a.laisser = nil end })
		return d
	end
	if a.laisse then
		d.sous, d.etiquette, d.clos = Signe("Sablier") .. "Laissé à " .. Nom(a.laisse), { "LAISSÉ", "attente" }, "Laissé à " .. Nom(a.laisse) .. "."
		return d
	end

	if a.etat == "delai" then
		d.etiquette = { "DÉLAI " .. Chrono(a), "attente" }
		if a.propose == moi then
			d.sous = "|cffff8a5cProposé à toi|r · sans objection, il est à toi"
			d.etiquette = { "PROPOSÉ", "toi" }
			d.explication = { "Tu l'as en liste : il t'est proposé.", "S'il n'y a pas d'objection avant la fin du délai, il est à toi.",
				"Tu peux aussi le laisser à un autre candidat." }
			local t = { sous = "|cffff8a5cProposé à toi|r", detail = "Sans objection, il est à toi", explication = d.explication }
			Laisser(t) Appel("info", t)
		elseif a.candidat then
			d.sous = "Proposé à " .. Nom(a.propose) .. " · tu es candidat"
			d.explication = { "Tu l'as aussi en liste ; le calcul le propose à " .. (a.propose or "?") .. ".",
				"Si tu penses le mériter plus, objecte avant la fin du délai : les présents voteront." }
			local t = { sous = "Proposé à " .. Nom(a.propose) .. " · tu es candidat", explication = d.explication }
			if not a.objecte then
				t.boutons = { { texte = "OBJECTER", clic = function () a.objecte = true Envoyer(a, "O", "!objection " .. a.n) end } }
			else t.detail = Signe("Sablier") .. "Ton objection est partie" end
			Appel("info", t)
		else
			d.sous = "Proposé à " .. Nom(a.propose)
		end
	elseif a.etat == "vote" then
		local entre = "Entre " .. Noms(a.choix, 3)
		local objection = "Objection de " .. Nom(a.auteur)
		d.explication = { (a.auteur or "?") .. " objecte" .. (a.motif and (" : « " .. a.motif .. " »") or "") .. ".",
			"Les présents qui ne l'ont pas en liste votent entre les candidats ; sans quorum, la proposition tient." }
		if Contient(a.choix, moi) or a.candidat or a.propose == moi then
			d.sous, d.etiquette = objection .. " · vote", { "VOTE " .. Chrono(a), "attente" }
			local t = { sous = (a.propose == moi and "|cffff8a5cÀ toi|r · " or "") .. objection, detail = entre, explication = d.explication }
			if Contient(a.choix, moi) then Laisser(t) end
			Appel("info", t)
		elseif a.monVote then
			d.sous, d.etiquette = "Ta voix : " .. Nom(a.monVote), { "VOTÉ", "attente" }
			Appel("info", { sous = Signe("Sablier") .. "Ta voix : " .. Nom(a.monVote), detail = entre, explication = d.explication })
		else
			d.sous, d.etiquette = objection .. " · à toi de voter", { "VOTER", "toi" }
			local c = {}
			for _, n in ipairs(a.choix or {}) do
				c[#c + 1] = { nom = n, classe = select(2, UnitClass(n)), clic = function () a.monVote = n Envoyer(a, "B", "!vote " .. a.n .. " " .. n, n) end }
			end
			local t = { sous = "Vote · " .. objection, explication = d.explication, sansReponse = "Sans ta voix, le vote continue." }
			if #c <= 3 then t.candidats = c
			else t.boutons = { { texte = "VOTER…", principal = true, clic = function () deplie = Cle(a) Volet.Ouvrir(true) end } } end
			Appel("decision", t)
		end
	elseif a.etat == "sk" then
		local k, total = RangSK(moi)
		local place = k and ("tu es " .. Ordinal(k) .. " de la liste") or "tu es hors liste"
		d.explication = { "Personne de présent ne l'a en liste : il se joue au Suicide King.",
			"Parmi les déclarés, le mieux placé dans la liste l'emporte, puis passe en bas." }
		if Raid.GainPawn and Raid.Comparer then
			local _, classe = UnitClass("player")
			local ok, g = pcall(function () return Raid.GainPawn(Raid.Comparer(moi, a.id), a.id, a.lien, classe) end)
			if not ok then g = nil end
			if g and g.vide then table.insert(d.explication, "Pour toi : l'emplacement est vide (" .. (g.spe or "") .. ").")
			elseif g and g.pct then table.insert(d.explication, string.format("Pour toi : %+d %% selon Pawn (%s).", math.floor(g.pct + 0.5), g.spe or "")) end
		end
		local tete = a.declares and #a.declares > 0 and ("En tête : " .. Noms(a.declares, 3)) or "Personne de déclaré"
		if a.passe then
			d.sous, d.etiquette, d.clos = "Tu passes", { "PASSÉ", "cendre" }, "Tu passes."
		elseif a.veut then
			d.sous, d.etiquette = Signe("Sablier") .. "Déclaré · " .. place, { "DÉCLARÉ", "attente" }
			Appel("info", { sous = Signe("Sablier") .. "|cffcfd4dcDéclaré|r · résultat à la fin", detail = tete, explication = d.explication })
		else
			d.sous, d.etiquette = "Suicide King · " .. place, { "À TOI", "toi" }
			Appel("decision", { sous = "Suicide King · " .. place, detail = a.declares and #a.declares > 0 and ("Déjà déclaré : " .. Noms(a.declares, 3)) or nil, explication = d.explication,
				boutons = { { texte = "JE LE VEUX", principal = true, clic = function () a.veut = true Envoyer(a, "W", "!sk " .. a.n) end },
				            { texte = "PASSER", clic = function () a.passe = true Envoyer(a, "X", "!passe " .. a.n) end } },
				sansReponse = "Sans réponse : tu passes." })
		end
	elseif a.etat == "trancher" then
		d.sous, d.etiquette = "Égalité au vote · les officiers tranchent", { "OFFICIERS", "attente" }
		if a.candidat or Contient(a.choix, moi) or a.propose == moi then
			Appel("info", { sous = Signe("Sablier") .. "Égalité · les officiers tranchent", explication = { "Le vote n'a pas départagé les candidats : les officiers décident, avec un motif." } })
		end
	else
		-- tranché : attribué, désenchanté, banque
		local qui = a.attributaire
		local pourquoi = a.avant == "delai" and "sans objection" or a.avant == "vote" and "après le vote" or a.avant == "sk" and "Suicide King"
			or a.avant == "trancher" and "décision des officiers" or nil
		if a.etat == "attribue" then
			d.sous = Signe("Coche") .. "À " .. Nom(qui) .. (pourquoi and (" · " .. pourquoi) or "")
			d.etiquette = { qui == moi and "À TOI" or "ATTRIBUÉ", "rendu" }
		elseif a.etat == "de" then d.sous, d.etiquette = "Désenchanté" .. (qui and qui ~= "" and (" par " .. Nom(qui)) or ""), { "DÉSENCHANTÉ", "cendre" }
		else d.sous, d.etiquette = "Pour la banque de guilde", { "BANQUE", "cendre" } end
		local concerne = a.propose == moi or a.candidat or a.veut or a.monVote or a.objecte or qui == moi
		if concerne and a.finie and GetTime() - a.finie < 8 then
			Appel("resultat", { sous = d.sous, fin = a.finie + 8,
				explication = qui == moi and { "Le maître du butin te le remet : depuis le corps, ou par échange." } or nil })
		end
	end
	return d
end

-- l'ordre des lignes : ce qui t'attend, ce qui te concerne, ce qui court, puis le tranché (le plus récent d'abord)
local function Poids (a, d)
	if d.appel and d.appel.genre == "decision" then return 0 end
	if d.appel then return 1 end
	if a.etat == "delai" or a.etat == "vote" or a.etat == "sk" or a.etat == "trancher" then return 2 end
	return 3
end

local descriptions = {}                 -- [clé] = d, refaites à chaque rafraîchissement

-- Les annonces → les appels. Un appel qui disparaît en laissant une réponse (« Tu passes ») la montre deux secondes.
function Volet.Synchroniser ()
	if Reglages().ancien then return end
	local maintenant = GetTime()
	-- les annonces tranchées s'effacent après la traîne
	for k = #Raid.annonces, 1, -1 do
		local a = Raid.annonces[k]
		if a.finie and maintenant - a.finie > TRAINE then table.remove(Raid.annonces, k) end
	end
	if #Raid.annonces > 0 then Volet.Creer() end
	local enCours = false
	for _, a in ipairs(Raid.annonces) do if not a.finie then enCours = true end end
	if enCours then finAnnonces = nil elseif #Raid.annonces > 0 and not finAnnonces then finAnnonces = maintenant end
	-- une vraie annonce met fin à la démonstration
	if #Raid.annonces > 0 and Demo.actif then
		Demo.actif = nil Demo.generation = (Demo.generation or 0) + 1
		for id in pairs(appels) do if id:sub(1, 1) ~= "r" then appels[id] = nil end end
		montre = nil
	end
	local vus = {}
	wipe(descriptions)
	for _, a in ipairs(Raid.annonces) do
		local cle = Cle(a)
		local d = Decrire(a)
		descriptions[cle] = d
		local ancien = appels[cle]
		if d.appel then
			vus[cle] = true
			if not (ancien and ancien.clos) then
				d.appel.id = cle
				if ancien then d.appel.sonne = ancien.sonne end
				Volet.Appeler(d.appel)
			end
		elseif d.clos and ancien then
			vus[cle] = true
			if not ancien.clos then Volet.Clore(cle, d.clos) end
		end
	end
	for id, ap in pairs(appels) do
		if id:sub(1, 1) == "r" and not vus[id] and not ap.clos then Volet.Retirer(id) end
	end
	-- la languette : là tant qu'il y a du butin, et dix minutes après
	local voulue = Reglages().demo or #Raid.annonces > 0
	if voulue then
		Volet.Creer()
		if not languette:IsShown() then languette:Show() end
	elseif languette and languette:IsShown() and not Reglages().demo then
		languette:Hide() volet:Hide() banderole:Hide()
	end
	PoserLanguette()
end

-- le registre du volet, en direct
local HAUT_LIGNE = 50
local function LigneDirecte (r, k)
	if r.lignes[k] then return r.lignes[k] end
	local f = CreateFrame("Button", nil, r)
	f:SetWidth(INTERIEUR)
	f.fond = Aplat(f, C.encre, 0.55, "BACKGROUND") f.fond:SetAllPoints()
	f.dessus = Aplat(f, C.orVif, 0.08) f.dessus:SetHeight(1) f.dessus:SetPoint("TOPLEFT") f.dessus:SetPoint("TOPRIGHT")
	f.dessous = Aplat(f, C.encre, 0.8) f.dessous:SetHeight(1) f.dessous:SetPoint("BOTTOMLEFT") f.dessous:SetPoint("BOTTOMRIGHT")
	f.lisere = Aplat(f, C.braise, 1) f.lisere:SetWidth(3) f.lisere:SetPoint("TOPLEFT", 0, -1) f.lisere:SetPoint("BOTTOMLEFT", 0, 1)
	f.cadre = Cadre(f, nil, 36) f.cadre:SetPoint("TOPLEFT", 8, -7)
	f.nom = Texte(f, "Nom") f.nom:SetPoint("TOPLEFT", 52, -8)
	f.sous = Texte(f, "Texte", C.pale) f.sous:SetPoint("TOPLEFT", 52, -27) f.sous:SetPoint("TOPRIGHT", -8, -27)
	f.etiquettes = {}
	f.detail = Texte(f, "Texte", C.parchemin) f.detail:SetWordWrap(true) f.detail:SetWidth(INTERIEUR - 18)
	f.detail:SetPoint("TOPLEFT", 10, -HAUT_LIGNE - 2)
	f.prim = BoutonPrincipal(f, "", nil) f.sec = BoutonSecond(f, "", nil)
	f.noms = { BoutonNom(f), BoutonNom(f), BoutonNom(f), BoutonNom(f) }
	f:SetScript("OnClick", function (self)
		deplie = deplie ~= self.cle and self.cle or nil
		volet:Remplir()
	end)
	r.lignes[k] = f
	return f
end

-- une étiquette par texte et sens, faite une fois puis réutilisée
local function EtiquetteDe (f, texte, sens)
	local cle = sens .. "|" .. texte:gsub("%d", "0")
	local e = f.etiquettes[cle]
	if not e then e = Etiquette(f, texte, sens) e:SetPoint("TOPRIGHT", -6, -15) f.etiquettes[cle] = e end
	e.texte:SetText(texte)
	return e
end

function Volet.RemplirDirect (r)
	local liste = {}
	for _, a in ipairs(Raid.annonces) do
		local d = descriptions[Cle(a)] or Decrire(a)
		liste[#liste + 1] = { a = a, d = d, p = Poids(a, d) }
	end
	table.sort(liste, function (x, y) if x.p ~= y.p then return x.p < y.p end return x.a.n > y.a.n end)
	-- sans choix du joueur, la première ligne qui t'attend est dépliée
	local cles = {}
	for _, e in ipairs(liste) do cles[Cle(e.a)] = true end
	if deplie and not cles[deplie] then deplie = nil end
	if not deplie and liste[1] and liste[1].p == 0 then deplie = Cle(liste[1].a) end
	for _, f in ipairs(r.lignes) do f:Hide() end
	r.vide:SetShown(#liste == 0)
	local y, place, caches = 0, r:GetHeight() - 16, 0
	for k, e in ipairs(liste) do
		local a, d = e.a, e.d
		local f = LigneDirecte(r, k)
		f.cle = Cle(a)
		f.cadre.icone:SetTexture(d.objet.icone)
		f.nom:SetText(d.objet.nom) f.nom:SetTextColor(Qualite(d.objet.qualite))
		f.sous:SetText(d.sous or "")
		for _, et in pairs(f.etiquettes) do et:Hide() end
		if d.etiquette then
			local et = EtiquetteDe(f, d.etiquette[1], d.etiquette[2]) et:Show()
			f.nom:SetPoint("TOPRIGHT", -(et:GetWidth() + 12), -8)
		end
		f.lisere:SetShown(e.p == 0)
		f.fond:SetShown(f.cle == deplie)
		f:SetAlpha(e.p == 3 and 0.6 or 1)
		-- dépliée : l'explication en clair, et les mêmes actions que la banderole
		local h = HAUT_LIGNE
		f.detail:Hide() f.prim:Hide() f.sec:Hide()
		for _, n in ipairs(f.noms) do n:Hide() end
		if f.cle == deplie then
			local texte = table.concat(d.explication or {}, "\n")
			if d.appel and d.appel.detail then texte = d.appel.detail .. (texte ~= "" and ("\n" .. texte) or "") end
			if texte ~= "" then f.detail:SetText(texte) f.detail:Show() h = h + 6 + f.detail:GetStringHeight() end
			local ap = d.appel
			local x = 10
			if ap and ap.boutons then
				for _, bt in ipairs(ap.boutons) do
					local w = bt.principal and f.prim or f.sec
					w:Poser(bt.texte) w:SetScript("OnClick", bt.clic) w:ClearAllPoints() w:SetPoint("TOPLEFT", x, -h - 8) w:Show()
					x = x + w:GetWidth() + 14
				end
			end
			if ap and ap.candidats then
				for i, c in ipairs(ap.candidats) do
					local w = f.noms[i]
					if w then w:Poser(Classe(c.nom, c.classe)) w:SetScript("OnClick", c.clic) w:ClearAllPoints() w:SetPoint("TOPLEFT", x, -h - 8) w:Show() x = x + w:GetWidth() + 6 end
				end
			end
			if x > 10 then h = h + 8 + 30 end
			h = h + 10
		end
		f:SetHeight(h)
		if y + h > place then caches = caches + 1
		else f:ClearAllPoints() f:SetPoint("TOPLEFT", 0, -y) f:Show() y = y + h end
	end
	r.plus:SetShown(caches > 0)
	r.plus:SetText(caches > 0 and ("et " .. caches .. " de plus, plus anciens") or "")
end

-- La fenêtre des annonces d'avant (RaidVote.lua) laisse la place au volet ; /opus volet ancien la rend.
local AncienRafraichir = Raid.RafraichirVote
local dernierAvis = 0
Raid.RafraichirVote = function ()
	if OpusDB and OpusDB.volet and OpusDB.volet.ancien then return AncienRafraichir() end
	-- pendant les essais : une erreur du volet se dit dans le chat (une fois par minute), avec sa ligne
	local ok, err = xpcall(Volet.Synchroniser, function (e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 3, 0) or "") end)
	if not ok and GetTime() - dernierAvis > 60 then
		dernierAvis = GetTime()
		Opus.Msg("|cffff5a5aerreur du volet|r : " .. tostring(err):gsub("Interface\\AddOns\\Opus\\", ""))
	end
end

-- la traîne : sans annonce depuis dix minutes, la languette s'en va (sauf si on l'a montrée à la main)
C_Timer.NewTicker(5, function ()
	if finAnnonces and GetTime() - finAnnonces > TRAINE and #Raid.annonces > 0 then
		for k = #Raid.annonces, 1, -1 do if Raid.annonces[k].finie then table.remove(Raid.annonces, k) end end
		finAnnonces = nil
		Volet.Synchroniser()
	end
end)

------------------------------------------------------------------------
-- mise en route
------------------------------------------------------------------------

local function Creer ()
	if languette then return end
	CreerLanguette()
	CreerBanderole()
	CreerVolet()
	languette:SetFrameLevel(volet:GetFrameLevel() + 10)
	banderole:SetFrameLevel(languette:GetFrameLevel() - 5)   -- la banderole sort de derrière la languette
	local e = Reglages().echelle or 1
	languette:SetScale(e) banderole:SetScale(e) volet:SetScale(e)
	Placer()
	PoserLanguette()
end
Volet.Creer = Creer

local function Montrer (oui)
	Creer()
	languette:SetShown(oui)
	if not oui then
		Demo.generation, Demo.actif = (Demo.generation or 0) + 1, nil
		wipe(appels) montre = nil
		volet:Hide() banderole:Hide() volet.decal, banderole.decal = nil, nil
		Placer()
	end
	Reglages().demo = oui or nil
	PoserLanguette()
end

-- le volet se ferme à l'entrée en combat, sauf s'il est épinglé ; la languette et la banderole restent
Opus.Ecoute("PLAYER_REGEN_DISABLED", function ()
	if volet and volet:IsShown() and not Reglages().epingle then Volet.Ouvrir(false) end
end)
Opus.Ecoute("PLAYER_LOGIN", function ()
	if OpusDB and OpusDB.volet and OpusDB.volet.demo then Montrer(true) end
end)

------------------------------------------------------------------------
-- la démonstration : un Suicide King, un vote, un objet proposé qui rencontre une objection
------------------------------------------------------------------------

-- Règle d'écriture des banderoles : un coup d'œil suffit. Une ligne d'état (un signe, trois ou quatre mots, le
-- temps), au plus une ligne de noms ; l'explication complète se lit au survol de l'objet, ou dans le volet.
local function Signe (nom) return "|T" .. MEDIA .. nom .. ":14:14|t " end
local TOI = "|cffff8a5ctoi|r"

local function Objet (n) return n == 1 and DEMO.appel or DEMO.lignes[n - 1] end
local function Plus (g, t, f) C_Timer.After(t, function () if Demo.generation == g then f() end end) end

-- Suicide King : après « Je le veux », la banderole reste et suit le tour (le temps, qui s'est déclaré, qui
-- est en tête) jusqu'au résultat ; « Passer » la referme.
function Demo.Repondre (r)
	local a = appels.sk
	if not a or a.clos then return end
	reponse = r
	if r == "passe" then Volet.Clore("sk", "Tu passes.") return end
	local g = Demo.generation
	local function Suivi (declares)
		Volet.Appeler({ id = "sk", genre = "info", objet = a.objet, fin = a.fin, duree = a.duree,
			sous = Signe("Sablier") .. "|cffcfd4dcDéclaré|r · résultat à la fin",
			detail = "En tête : " .. declares,
			explication = { "Suicide King : parmi les déclarés, le mieux placé dans la liste l'emporte, puis descend en bas de la liste.",
			                "Tu es 2e de la liste. La liste complète est dans le volet." } })
	end
	Suivi(Classe("Vorthas", "WARLOCK") .. " (1) · " .. TOI .. " (2)")
	Plus(g, 4, function () if appels.sk and appels.sk.genre == "info" then Suivi(Classe("Vorthas", "WARLOCK") .. " (1) · " .. TOI .. " (2) · " .. Classe("Brannok", "WARRIOR") .. " (5)") end end)
	-- à la fin du tour : le résultat
	Plus(g, a.fin - GetTime(), function ()
		Volet.Retirer("sk")
		Volet.Appeler({ id = "ressk", genre = "resultat", objet = a.objet,
			sous = Signe("Coche") .. "À " .. Classe("Vorthas", "WARLOCK") .. " · 1er de la liste", fin = GetTime() + 6 })
	end)
end
function Demo.SK (duree)
	reponse = nil
	Volet.Appeler({ id = "sk", genre = "decision", objet = Objet(1), fin = GetTime() + duree, duree = duree,
		sous = "Suicide King · tu es 2e de la liste",
		boutons = { { texte = "JE LE VEUX", principal = true, clic = function () Demo.Repondre("pris") end },
		            { texte = "PASSER", clic = function () Demo.Repondre("passe") end } },
		explication = { "Personne ne l'a en liste : il se joue au Suicide King.", "Tu es 2e de la liste ; déclare-toi si tu le veux.", "Pour toi, c'est un gain de 6 % selon Pawn, face à la Bague de l'aube." },
		sansReponse = "Sans réponse : tu passes.", auSansReponse = function () reponse = "passe" end })
end

-- le vote : les noms, directement ; après ta voix, la banderole suit le décompte
function Demo.Vote (duree)
	local g, o = Demo.generation, Objet(2)
	local fin = GetTime() + duree
	local function Voter (nom)
		Volet.Appeler({ id = "vote", genre = "info", objet = o, fin = fin, duree = duree,
			sous = Signe("Sablier") .. "Ta voix : " .. nom .. " · 6 sur 9" })
		Plus(g, fin - GetTime(), function ()
			Volet.Retirer("vote")
			Volet.Appeler({ id = "resvote", genre = "resultat", objet = o,
				sous = Signe("Coche") .. "À " .. Classe("Seliane", "DRUID") .. " · 6 voix contre 3", fin = GetTime() + 6 })
		end)
	end
	Volet.Appeler({ id = "vote", genre = "decision", objet = o, fin = fin, duree = duree,
		sous = "Vote · à qui la donner ?",
		candidats = { { nom = "Seliane", classe = "DRUID", clic = function () Voter(Classe("Seliane", "DRUID")) end },
		              { nom = "Vorthas", classe = "WARLOCK", clic = function () Voter(Classe("Vorthas", "WARLOCK")) end } },
		explication = { "Vorthas a objecté à la proposition faite à Seliane.", "Votent les présents qui n'ont pas l'objet en liste ; un clic sur un nom." },
		sansReponse = "Sans ta voix, le vote continue." })
end

-- l'objet proposé : toujours lisible, et on peut le laisser à un autre à tout moment
function Demo.Proposition ()
	local g, o = Demo.generation, Objet(3)
	local laisse, enChoix
	local function Laisser (nom)
		laisse = true
		Volet.Retirer("prop")
		Volet.Appeler({ id = "resprop", genre = "resultat", objet = o, sous = Signe("Coche") .. "Laissé à " .. nom, fin = GetTime() + 5 })
	end
	local function Choix ()
		enChoix = true
		Volet.Appeler({ id = "prop", genre = "decision", objet = o, fin = GetTime() + 20, duree = 20,
			sous = "Le laisser à qui ?",
			candidats = { { nom = "Vorthas", classe = "WARLOCK", clic = function () Laisser(Classe("Vorthas", "WARLOCK")) end },
			              { nom = "Brannok", classe = "WARRIOR", clic = function () Laisser(Classe("Brannok", "WARRIOR")) end } },
			explication = { "Tu renonces à l'objet ; il va à qui tu choisis parmi ceux qui le veulent." },
			sansReponse = "Tu le gardes." })
	end
	local function Proposee (sous, detail, duree, explication)
		Volet.Appeler({ id = "prop", genre = "info", objet = o, sous = sous, detail = detail, fin = GetTime() + duree, duree = duree,
			boutons = { { texte = "LE LAISSER", clic = Choix } }, explication = explication })
	end
	Proposee("|cffff8a5cProposé à toi|r · liste 1 sur 2", nil, 20,
		{ "Tu l'as en liste, au rang 1 : il t'est proposé.", "Sans objection avant la fin du délai, il est à toi." })
	Plus(g, 8, function ()
		if laisse or enChoix then return end
		Proposee(Signe("Sablier") .. "|cffff8a5cÀ toi|r · objection de " .. Classe("Vorthas", "WARLOCK"), "Vote à la fin du délai", 25,
			{ "Vorthas objecte : « elle a déjà reçu la Ceinture ce soir ».", "Sans retrait, les présents votent entre toi et lui.", "Tu peux aussi le lui laisser." })
	end)
	Plus(g, 33, function ()
		if laisse then return end
		Volet.Retirer("prop")
		Volet.Appeler({ id = "resprop", genre = "resultat", objet = o, sous = Signe("Coche") .. "|cffff8a5cÀ toi|r · 5 voix contre 3", fin = GetTime() + 8,
			explication = { "Le vote a confirmé la proposition. Le maître du butin te le remet." } })
	end)
end

function Demo.Tout ()
	Demo.generation, Demo.actif = (Demo.generation or 0) + 1, true
	local g = Demo.generation
	wipe(appels) montre = nil
	Demo.SK(25)
	Plus(g, 3, function () Demo.Vote(40) end)
	Plus(g, 5, Demo.Proposition)
end

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

local AIDE = {
	"|cffffd100/opus volet|r — montrer ou cacher la languette (au bord gauche, à glisser vers le haut ou le bas)",
	"|cffffd100/opus volet demo|r — un scénario : Suicide King, vote, objet proposé puis objection et résultat",
	"|cffffd100/opus volet appel|r — un appel au Suicide King seul (25 s)",
	"|cffffd100/opus volet etat repos|cours|toi|auto|r — imposer le signe de la languette, ou le rendre aux appels",
	"|cffffd100/opus volet echelle 0.8 à 1.4|r — la taille du volet, de la languette et de la banderole",
	"|cffffd100/opus volet son|r — le son d'une décision qui arrive, oui ou non",
	"|cffffd100/opus volet essai|r — de fausses annonces d'un maître du butin, par le vrai circuit (seul, hors groupe)",
	"|cffffd100/opus volet ancien|r — revenir à la fenêtre des annonces d'avant, ou au volet",
}

-- L'essai : un maître du butin imaginaire (« Essai ») annonce trois objets ; tes clics partent comme en raid (hors
-- groupe, nulle part), et la suite est jouée d'avance.
local function Essai ()
	local moi = Raid.MonNom()
	local g = (Demo.generation or 0) + 1
	Demo.generation, Demo.actif = g, nil
	for k = #Raid.annonces, 1, -1 do if Raid.annonces[k].ml == "Essai" then table.remove(Raid.annonces, k) end end
	local function Dire (t, c) C_Timer.After(t, function () if Demo.generation == g then Raid.RecevoirAnnonce("Essai", c) end end) end
	Dire(0, { "A", "1", "19143", moi, "40", moi .. ",Vorthas" })
	Dire(0, { "S", "2", "19147", "25" })
	Dire(3, { "A", "3", "19137", "Seliane", "8", "Seliane,Vorthas" })
	Dire(6, { "K", "2", "Vorthas" })
	Dire(11, { "V", "3", "30", "3", "8", "Vorthas", "Seliane,Vorthas,Brannok", "déjà servie ce soir" })
	Dire(14, { "V", "1", "25", "3", "8", "Vorthas", moi .. ",Vorthas", "elle a déjà reçu la Ceinture" })
	Dire(25, { "R", "2", "attribue", "Vorthas" })
	Dire(39, { "R", "1", "attribue", moi })
	Dire(41, { "R", "3", "attribue", "Seliane" })
end

Opus.Commande("volet", "volet [aide]", "le volet latéral du butin, en démonstration", function (texte)
	local mot, reste = (texte or ""):match("^%s*(%S*)%s*(.-)%s*$")
	mot = (mot or ""):lower()
	if mot == "" then
		Creer()
		Montrer(not languette:IsShown())
		Opus.Msg(languette:IsShown() and "la languette du volet est au bord gauche (/opus volet aide)." or "volet caché.")
	elseif mot == "demo" then
		Montrer(true) etatForce = nil Demo.Tout()
		Opus.Msg("démonstration : trois appels arrivent, une banderole à la fois (survole l'objet pour l'explication).")
	elseif mot == "appel" then
		Montrer(true) etatForce = nil Demo.generation, Demo.actif = (Demo.generation or 0) + 1, true Demo.SK(25)
	elseif mot == "etat" and (reste == "repos" or reste == "cours" or reste == "toi" or reste == "auto") then
		Montrer(true) etatForce = reste ~= "auto" and reste or nil PoserLanguette()
	elseif mot == "echelle" and tonumber(reste) then
		local e = math.max(0.8, math.min(1.4, tonumber(reste)))
		Reglages().echelle = e
		Creer() languette:SetScale(e) banderole:SetScale(e) volet:SetScale(e) Placer()
		Opus.Msg("échelle du volet : " .. e)
	elseif mot == "essai" then
		Essai()
		Opus.Msg("essai : trois annonces arrivent d'un maître du butin imaginaire.")
	elseif mot == "ancien" then
		Reglages().ancien = not Reglages().ancien or nil
		Opus.Msg(Reglages().ancien and "annonces : la fenêtre d'avant." or "annonces : le volet.")
		if not Reglages().ancien and languette then Volet.Synchroniser() end
	elseif mot == "son" then
		Reglages().son = (Reglages().son == false)
		Opus.Msg("son d'une décision : " .. (Reglages().son and "oui" or "non"))
	else
		Opus.Msg("le volet latéral, en démonstration :")
		for _, l in ipairs(AIDE) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
		local liste = {}
		for f in pairs(manquantes) do liste[#liste + 1] = f end
		if #liste > 0 then Opus.Msg("polices introuvables, police du jeu à la place : " .. table.concat(liste, ", ")) end
	end
end)
