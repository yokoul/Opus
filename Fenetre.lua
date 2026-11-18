-- Fenetre.lua : la fenêtre /opus, faite des cadres natifs du client (comme SkillUp ou le Bestiaire) : cadre à
-- portrait (ButtonFrameTemplate) avec l'emblème d'Opus, onglets en bas (PanelTabButtonTemplate), contenu dans
-- l'encart (Inset), boutons rouges du client (SharedButton*), polices et couleurs du jeu. Chaque page vit dans son
-- fichier (Page*.lua) ; ses réglages (période, préréglage) vont dans la bande au-dessus de l'encart.
local _, Opus = ...

Opus.LARGEUR = 720
local MARGE = 10                -- marge intérieure de l'encart
local HAUT_ENCART, BAS_ENCART = 60, 26
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

-- infobulle : titre et texte (ou liste de lignes), fixes ou calculés à partir du cadre survolé
function Opus.Bulle (cadre, titre, texte)
	cadre:SetScript("OnEnter", function (self)
		local t = type(titre) == "function" and titre(self) or titre
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(t, 1, 1, 1)
		local l = type(texte) == "function" and texte(self) or texte
		if type(l) == "table" then
			for _, ligne in ipairs(l) do GameTooltip:AddLine(ligne, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
		elseif l then
			GameTooltip:AddLine(l, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		end
		GameTooltip:Show()
	end)
	cadre:SetScript("OnLeave", GameTooltip_Hide)
end

-- bouton rouge du client ; petit = la taille des lignes de liste
function Opus.Bouton (parent, texte, largeur, clic, petit)
	local b = CreateFrame("Button", nil, parent, petit and "SharedButtonExtraSmallTemplate" or "SharedButtonSmallTemplate")
	b:SetSize(largeur, petit and 20 or 24)
	b:SetText(texte)
	if clic then b:SetScript("OnClick", clic) end
	return b
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
	local p = pages[Active()]
	f:SetHeight(HAUT_ENCART + MARGE + (p.rafraichir(p.contenu) or 200) + MARGE + BAS_ENCART)
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
	f:SetSize(Opus.LARGEUR, 300)
	f:SetPoint("CENTER")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("HIGH")
	tinsert(UISpecialFrames, "OpusFenetre")
	f:SetTitle("Opus — " .. (GetGuildInfo("player") or "guilde"))
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
