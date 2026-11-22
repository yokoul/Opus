-- Fenetre.lua : la fenêtre /opus, faite des cadres natifs du client (comme SkillUp ou le Bestiaire) : cadre à
-- portrait (ButtonFrameTemplate) avec l'emblème d'Opus, onglets en bas (PanelTabButtonTemplate), contenu dans
-- l'encart (Inset), boutons aux couleurs d'Opus (ou rouges du client, au choix dans Réglages), polices et couleurs du jeu. Chaque page vit dans son
-- fichier (Page*.lua) ; ses réglages (période, préréglage) vont dans la bande au-dessus de l'encart.
local _, Opus = ...

Opus.LARGEUR = 720
local MARGE = 10                -- marge intérieure de l'encart
local HAUTEUR_MIN = 180         -- une page presque vide garde une fenêtre de taille raisonnable
local HAUT_ENCART = 60
local BAS_ENCART = PANEL_INSET_BOTTOM_OFFSET or 4   -- sans la barre de boutons du bas, dont Opus n'a pas l'usage
local f
local pages, ordre = {}, {}

------------------------------------------------------------------------
-- briques communes aux pages : rien de dessiné à la main, tout vient du client
------------------------------------------------------------------------

-- couleurs sémantiques du jeu
local function Teinte (couleur, s) return couleur and couleur:WrapTextInColorCode(s) or s end
function Opus.Normal (s) return Teinte(NORMAL_FONT_COLOR, s) end      -- or : titres, ce qui se clique
function Opus.Blanc (s) return Teinte(HIGHLIGHT_FONT_COLOR, s) end
function Opus.Gris (s) return Teinte(GRAY_FONT_COLOR, s) end
function Opus.Rouge (s) return Teinte(RED_FONT_COLOR, s) end
function Opus.Vert (s) return Teinte(GREEN_FONT_COLOR, s) end

function Opus.Couleur (classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

function Opus.Coche (taille)
	return CreateAtlasMarkup and CreateAtlasMarkup("common-icon-checkmark", taille or 14, taille or 14) or Opus.Vert("oui")
end

-- ce que l'infobulle peut afficher : une chaîne (ou une valeur secrète du jeu, qu'on passe telle quelle), un nombre
-- mis en texte ; tout le reste (table, booléen…) est écarté plutôt que de lever une erreur Lua chez le joueur
local function Affichable (v)
	if v == nil or v == false then return nil end
	if issecretvalue and issecretvalue(v) then return v end
	local genre = type(v)
	if genre == "string" then return v ~= "" and v or nil end
	if genre == "number" then return tostring(v) end
	return nil
end

-- infobulle : titre et texte (ou liste de lignes), fixes ou calculés à partir du cadre survolé
function Opus.Bulle (cadre, titre, texte)
	cadre:SetScript("OnEnter", function (self)
		local t = Affichable(type(titre) == "function" and titre(self) or titre)
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		-- garde-fou : un refus du client (retour d'un joueur, Guilde > Par voie / En ligne) cache la bulle au lieu
		-- d'afficher une erreur ; le refus est noté dans OpusDB.diagBulle (SavedVariables) pour comprendre la cause
		local ok, erreur = pcall(GameTooltip.SetText, GameTooltip, t, 1, 1, 1)
		if not ok then
			if Opus.db then Opus.db.diagBulle = { quand = time(), genre = type(t), erreur = tostring(erreur) } end
			GameTooltip:Hide()
			return
		end
		local l = type(texte) == "function" and texte(self) or texte
		local c = NORMAL_FONT_COLOR
		if type(l) == "table" then
			for _, ligne in ipairs(l) do
				ligne = Affichable(ligne)
				if ligne then GameTooltip:AddLine(ligne, c.r, c.g, c.b, true) end
			end
		else
			l = Affichable(l)
			if l then GameTooltip:AddLine(l, c.r, c.g, c.b, true) end
		end
		GameTooltip:Show()
	end)
	cadre:SetScript("OnLeave", GameTooltip_Hide)
end

-- bouton rouge du client ; petit = la taille des lignes de liste
-- Le style d'Opus, d'après les planches de marque : une teinte de fond (pétrole de la bannière, écarlate, ardoise…),
-- toujours le même filet doré des cadres, qui s'éclaire au survol, et le texte or. On garde le modèle du client pour
-- son comportement et on éteint ses textures (SetAlpha plutôt que Hide : le modèle les remontre à chaque état). La
-- teinte se choisit dans Réglages (« classique » garde le bouton rouge du jeu), au prochain /reload.
local BLANC = "Interface\\Buttons\\WHITE8X8"
-- par teinte : le fond au repos, au survol, à l'appui
Opus.TEINTES = {
	{ "petrole", "Pétrole (la bannière)", { 0.05, 0.16, 0.16 }, { 0.08, 0.24, 0.23 }, { 0.03, 0.10, 0.10 } },
	{ "ecarlate", "Écarlate noble", { 0.30, 0.04, 0.05 }, { 0.42, 0.07, 0.07 }, { 0.18, 0.02, 0.03 } },
	{ "vertdegris", "Vert de gris", { 0.10, 0.17, 0.14 }, { 0.15, 0.25, 0.20 }, { 0.06, 0.11, 0.09 } },
	{ "aubergine", "Aubergine", { 0.15, 0.08, 0.20 }, { 0.22, 0.12, 0.29 }, { 0.09, 0.05, 0.13 } },
	{ "ardoise", "Ardoise froide", { 0.13, 0.15, 0.18 }, { 0.19, 0.22, 0.26 }, { 0.08, 0.09, 0.11 } },
	{ "bronze", "Bronze fumé", { 0.17, 0.12, 0.07 }, { 0.25, 0.18, 0.10 }, { 0.10, 0.07, 0.04 } },
}
-- le filet doré, en dégradé (haut, bas) : plus clair en haut, comme un métal éclairé d'en haut
local FILETS = {
	normal = { { 0.86, 0.70, 0.38 }, { 0.45, 0.33, 0.15 } },
	survol = { { 1.00, 0.88, 0.55 }, { 0.70, 0.53, 0.24 } },
	appui = { { 0.55, 0.41, 0.18 }, { 0.80, 0.63, 0.30 } },
	eteint = { { 0.38, 0.35, 0.30 }, { 0.22, 0.20, 0.18 } },
}

local function Teinte ()
	local choix = Opus.db and Opus.db.styleBoutons
	for _, t in ipairs(Opus.TEINTES) do if t[1] == choix then return t end end
	return Opus.TEINTES[1]
end

-- un dégradé vertical (bas, haut) ; SetGradient prend des couleurs depuis Dragonflight, SetGradientAlpha avant
local function Degrade (tex, bas, haut, a)
	if CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bas[1], bas[2], bas[3], a), CreateColor(haut[1], haut[2], haut[3], a)) then return end
	if tex.SetGradientAlpha then tex:SetGradientAlpha("VERTICAL", bas[1], bas[2], bas[3], a, haut[1], haut[2], haut[3], a) return end
	tex:SetVertexColor((bas[1] + haut[1]) / 2, (bas[2] + haut[2]) / 2, (bas[3] + haut[3]) / 2, a)
end

local function Eclaircir (c, k) return { math.min(1, c[1] * k + 0.02), math.min(1, c[2] * k + 0.02), math.min(1, c[3] * k + 0.02) } end

local function Teinter (b, etat)
	etat = b:IsEnabled() and etat or "eteint"
	local t = Teinte()
	local fond = etat == "survol" and t[4] or etat == "appui" and t[5] or t[3]
	if etat == "eteint" then fond = { 0.09, 0.09, 0.09 } end
	-- le fond bombé : clair en haut, sombre en bas ; enfoncé, l'inverse
	if etat == "appui" then Degrade(b.opusFond, Eclaircir(fond, 1.3), Eclaircir(fond, 0.6), 0.97)
	else Degrade(b.opusFond, Eclaircir(fond, 0.55), Eclaircir(fond, 1.7), 0.97) end
	local l = FILETS[etat]
	Degrade(b.opusFilet[3], l[2], l[1], 1) Degrade(b.opusFilet[4], l[2], l[1], 1)
	b.opusFilet[1]:SetVertexColor(l[1][1], l[1][2], l[1][3], 1)
	b.opusFilet[2]:SetVertexColor(l[2][1], l[2][2], l[2][3], 1)
	-- le biseau : lumière en haut, ombre en bas (inversés à l'appui)
	local enfonce = etat == "appui"
	b.opusLumiere:SetAlpha(enfonce and 0 or etat == "eteint" and 0.06 or 0.22)
	b.opusOmbre:SetAlpha(enfonce and 0.15 or 0.45)
	b.opusLueur:SetShown(etat == "survol")
end

local function Ligne (b, couche, sous)
	local l = b:CreateTexture(nil, couche, nil, sous)
	l:SetTexture(BLANC)
	return l
end

function Opus.HabillerBouton (b)
	-- par défaut le bouton du jeu : sa texture usée va avec le reste de l'interface, nos aplats détonnent
	if not Opus.db or (Opus.db.styleBoutons or "classique") == "classique" then return b end
	for _, r in ipairs { b:GetRegions() } do
		if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
	end
	for _, f in ipairs { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" } do
		local t = b[f] and b[f](b)
		if t then t:SetAlpha(0) end
	end
	-- l'ombre portée, un pixel sous le bouton et à droite
	local ombre = Ligne(b, "BACKGROUND", 5)
	ombre:SetPoint("TOPLEFT", 1, -1) ombre:SetPoint("BOTTOMRIGHT", 1, -2)
	ombre:SetVertexColor(0, 0, 0, 0.55)
	b.opusFond = Ligne(b, "BACKGROUND", 7)
	b.opusFond:SetPoint("TOPLEFT", 1, -1) b.opusFond:SetPoint("BOTTOMRIGHT", -1, 1)
	-- la lueur dorée au survol, ajoutée par-dessus le fond
	b.opusLueur = Ligne(b, "BORDER", 1)
	b.opusLueur:SetPoint("TOPLEFT", 1, -1) b.opusLueur:SetPoint("BOTTOMRIGHT", -1, 1)
	b.opusLueur:SetBlendMode("ADD")
	Degrade(b.opusLueur, { 0, 0, 0 }, { 0.30, 0.22, 0.08 }, 1)
	b.opusLueur:Hide()
	-- le biseau intérieur : un liseré clair sous le filet du haut, un sombre au-dessus de celui du bas
	b.opusLumiere = Ligne(b, "BORDER", 6)
	b.opusLumiere:SetPoint("TOPLEFT", 2, -2) b.opusLumiere:SetPoint("TOPRIGHT", -2, -2) b.opusLumiere:SetHeight(1)
	b.opusLumiere:SetVertexColor(1, 0.92, 0.70, 1)
	b.opusOmbre = Ligne(b, "BORDER", 6)
	b.opusOmbre:SetPoint("BOTTOMLEFT", 2, 2) b.opusOmbre:SetPoint("BOTTOMRIGHT", -2, 2) b.opusOmbre:SetHeight(1)
	b.opusOmbre:SetVertexColor(0, 0, 0, 1)
	-- le filet doré : haut, bas, gauche, droite
	b.opusFilet = {}
	for _, cote in ipairs { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } } do
		local l = Ligne(b, "BORDER", 7)
		l:SetPoint(cote[1]) l:SetPoint(cote[2])
		if cote[3] then l:SetHeight(1) else l:SetWidth(1) end
		b.opusFilet[#b.opusFilet + 1] = l
	end
	if b.SetNormalFontObject then
		b:SetNormalFontObject(GameFontNormalSmall)
		b:SetHighlightFontObject(GameFontHighlightSmall)
		b:SetDisabledFontObject(GameFontDisableSmall)
	end
	-- le texte, gravé : une ombre nette sous les lettres
	local texte = b.GetFontString and b:GetFontString()
	if texte and texte.SetShadowOffset then texte:SetShadowOffset(1, -1) texte:SetShadowColor(0, 0, 0, 0.9) end
	if b.SetPushedTextOffset then b:SetPushedTextOffset(1, -1) end
	b:HookScript("OnEnter", function (self) Teinter(self, "survol") end)
	b:HookScript("OnLeave", function (self) Teinter(self, "normal") end)
	b:HookScript("OnMouseDown", function (self) Teinter(self, "appui") end)
	b:HookScript("OnMouseUp", function (self) Teinter(self, self:IsMouseOver() and "survol" or "normal") end)
	b:HookScript("OnEnable", function (self) Teinter(self, "normal") end)
	b:HookScript("OnDisable", function (self) Teinter(self, "eteint") end)
	Teinter(b, "normal")
	return b
end

function Opus.Bouton (parent, texte, largeur, clic, petit)
	local b = CreateFrame("Button", nil, parent, petit and "SharedButtonExtraSmallTemplate" or "SharedButtonSmallTemplate")
	b:SetSize(largeur, petit and 20 or 24)
	b:SetText(texte)
	if clic then b:SetScript("OnClick", clic) end
	return Opus.HabillerBouton(b)
end

-- menu déroulant du client, à choix unique : choix = { { valeur, libellé }, … }
function Opus.Menu (parent, largeur, choix, lire, ecrire)
	local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	d:SetWidth(largeur)
	d:SetupMenu(function (_, racine)
		for _, c in ipairs(choix) do
			racine:CreateRadio(c[2], function () return lire() == c[1] end, function () ecrire(c[1]) end)
		end
	end)
	return d
end

-- les vues d'une page, en onglets dans son bandeau (ceux du haut du client, comme les macros), posés sur un filet doré
-- qui court jusqu'au bord : on les distingue des onglets de navigation du bas. choix = { { valeur, libellé }, … } ;
-- o:Maj() montre la vue choisie (à appeler au rafraîchissement)
local nOnglets = 0
function Opus.Onglets (barre, choix, lire, ecrire)
	local o = CreateFrame("Frame", nil, barre)
	o:SetPoint("BOTTOMLEFT", 0, -4) o:SetPoint("BOTTOMRIGHT", 0, -4) o:SetHeight(24)
	o.filet = o:CreateTexture(nil, "BACKGROUND")
	o.filet:SetHeight(1)
	o.filet:SetPoint("BOTTOMRIGHT", 0, 1)
	o.filet:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.45)
	o.boutons = {}
	local precedent
	for _, c in ipairs(choix) do
		nOnglets = nOnglets + 1
		local nom = "OpusVue" .. nOnglets
		local ok, b = pcall(CreateFrame, "Button", nom, o, "TabButtonTemplate")
		if not ok then b = CreateFrame("Button", nom, o, "PanelTopTabButtonTemplate") end
		b.valeur = c[1]
		b:SetText(c[2])
		PanelTemplates_TabResize(b, 0)
		if precedent then b:SetPoint("BOTTOMLEFT", precedent, "BOTTOMRIGHT", -2, 0) else b:SetPoint("BOTTOMLEFT", 0, 0) end
		b:SetScript("OnClick", function (self)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			ecrire(self.valeur)
		end)
		o.boutons[#o.boutons + 1] = b
		precedent = b
	end
	o.filet:SetPoint("BOTTOMLEFT", precedent, "BOTTOMRIGHT", 0, 1)
	function o:Maj ()
		for _, b in ipairs(self.boutons) do
			if b.valeur == lire() then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
		end
	end
	return o
end

-- ascenseur natif (MinimalScrollBar) pour une liste paginée à la main : maj(decalage, total, visibles) le recale,
-- defiler(nouveauDecalage) est appelé quand le joueur le tire
function Opus.Ascenseur (parent, defiler)
	local s = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	local interne = false
	s:RegisterCallback("OnScroll", function (_, pourcent)
		if interne or not s.total or s.total <= s.visibles then return end
		defiler(math.floor(pourcent * (s.total - s.visibles) + 0.5))
	end, s)
	function s:Recaler (decalage, total, visibles)
		self.total, self.visibles = total, visibles
		self:SetShown(total > visibles)
		if total <= visibles then return end
		interne = true
		self:SetVisibleExtentPercentage(visibles / total)
		self:SetPanExtentPercentage(1 / (total - visibles))
		self:SetScrollPercentage(decalage / (total - visibles), true)
		interne = false
	end
	return s
end

-- surbrillance native d'une ligne de liste au survol
function Opus.Survol (ligne)
	local h = ligne:CreateTexture(nil, "HIGHLIGHT")
	h:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	h:SetBlendMode("ADD")
	h:SetAllPoints()
	h:SetAlpha(0.5)
end

-- titre de section : texte doré, filet discret jusqu'au bord (comme les en-têtes du journal d'aventure)
function Opus.Section (parent, police)
	local s = parent:CreateFontString(nil, "OVERLAY", police or "GameFontNormal")
	s:SetJustifyH("LEFT")
	return s
end

------------------------------------------------------------------------
-- pages
------------------------------------------------------------------------

-- construire(contenu, barre) une fois ; rafraichir(contenu) renvoie la hauteur utile ; molette(contenu, delta)
function Opus.Page (cle, titre, construire, rafraichir, molette)
	pages[cle] = { titre = titre, construire = construire, rafraichir = rafraichir, molette = molette }
	ordre[#ordre + 1] = cle
end

local function Active ()
	return pages[Opus.db.page] and Opus.db.page or ordre[1]
end

-- la page des essais porte des boutons sécurisés : rien ne bouge en combat
local function Rafraichir ()
	if not f or not f:IsShown() or InCombatLockdown() then return end
	-- chaque page a sa hauteur ; la fenêtre est ancrée par le haut, donc seul le bas bouge d'un onglet à l'autre
	local p = pages[Active()]
	local h = math.max(HAUTEUR_MIN, p.rafraichir(p.contenu) or HAUTEUR_MIN)
	f:SetHeight(HAUT_ENCART + MARGE + h + MARGE + BAS_ENCART)
end
Opus.Rafraichir = Rafraichir

function Opus.Afficher (cle)
	if InCombatLockdown() or not f then return end
	Opus.db.page = cle
	for i, k in ipairs(ordre) do
		local p = pages[k]
		p.contenu:SetShown(k == cle)
		p.barre:SetShown(k == cle)
		if k == cle then PanelTemplates_SetTab(f, i) end
	end
	Rafraichir()
end

local function Construire ()
	f = CreateFrame("Frame", "OpusFenetre", UIParent, "ButtonFrameTemplate")
	f:SetSize(Opus.LARGEUR, 400)
	ButtonFrameTemplate_HideButtonBar(f)
	-- ancrée par son coin haut gauche (position retenue) : changer de hauteur ne la fait pas sauter
	local pos = Opus.db.fenetre
	if pos.x then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y) else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function (self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		pos.x, pos.y = self:GetLeft(), self:GetTop()
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
	end)
	f:SetFrameStrata("HIGH")
	tinsert(UISpecialFrames, "OpusFenetre")
	f:SetTitle(GetGuildInfo("player") or "Opus")
	f:SetPortraitToAsset("Interface\\AddOns\\Opus\\Media\\Embleme")

	for i, cle in ipairs(ordre) do
		local p = pages[cle]
		-- la bande sous le titre, pour les réglages de la page
		p.barre = CreateFrame("Frame", nil, f)
		p.barre:SetPoint("TOPLEFT", 64, -28)
		p.barre:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -12, -HAUT_ENCART + 2)
		-- le contenu, dans l'encart
		p.contenu = CreateFrame("Frame", nil, f.Inset)
		p.contenu:SetPoint("TOPLEFT", MARGE, -MARGE)
		p.contenu:SetPoint("TOPRIGHT", -MARGE, -MARGE)
		p.contenu:SetHeight(1)
		p.construire(p.contenu, p.barre)
		p.contenu:Hide()
		p.barre:Hide()

		local onglet = CreateFrame("Button", "OpusFenetreTab" .. i, f, "PanelTabButtonTemplate")
		onglet:SetID(i)
		onglet:SetText(p.titre)
		onglet:SetScript("OnClick", function ()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Opus.Afficher(cle)
		end)
		PanelTemplates_TabResize(onglet, 0)
		if i == 1 then onglet:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2) end
	end
	PanelTemplates_SetNumTabs(f, #ordre)    -- place les onglets suivants à la suite du premier

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function (_, d)
		local p = pages[Active()]
		if p.molette then p.molette(p.contenu, d) Rafraichir() end
	end)
	f:SetScript("OnShow", function ()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		Opus.DemanderListe()
		Rafraichir()
	end)
	f:SetScript("OnHide", function () PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end)
	f:Hide()
end

-- /opus : ouvre ou ferme ; ouvrir = true pour seulement ouvrir (sur la page Opus.db.page)
function Opus.Fenetre (ouvrir)
	if not IsInGuild() then Opus.Msg("tu n'es pas en guilde.") return end
	if InCombatLockdown() then Opus.Msg("pas en combat.") return end
	if not f then Construire() end
	if f:IsShown() and not ouvrir then f:Hide() return end
	f:Show()
	Opus.Afficher(Active())
end

Opus.Ecoute("GUILD_ROSTER_UPDATE", Rafraichir)
-- l'entrée en combat laisse encore modifier les cadres sécurisés : c'est le moment de fermer
Opus.Ecoute("PLAYER_REGEN_DISABLED", function () if f then f:Hide() end end)
