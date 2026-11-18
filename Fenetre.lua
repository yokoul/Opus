-- Fenetre.lua : la fenêtre /opus et ses onglets ; chaque page vit dans son fichier (Page*.lua)
local _, Opus = ...

Opus.LARGEUR = 720
local HAUT = 62                 -- début des pages, sous les onglets
local f
local pages, ordre = {}, {}

------------------------------------------------------------------------
-- briques communes aux pages
------------------------------------------------------------------------

function Opus.Couleur (classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

-- infobulle : titre et texte, fixes ou calculés à partir du cadre survolé
function Opus.Bulle (cadre, titre, texte)
	cadre:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(titre) == "function" and titre(self) or titre)
		local t = type(texte) == "function" and texte(self) or texte
		if type(t) == "table" then
			for _, ligne in ipairs(t) do GameTooltip:AddLine(ligne, 1, 1, 1, true) end
		elseif t then
			GameTooltip:AddLine(t, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	cadre:SetScript("OnLeave", GameTooltip_Hide)
end

function Opus.Bouton (parent, texte, largeur, clic)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(largeur, 22)
	b:SetText(texte)
	b:SetScript("OnClick", clic)
	return b
end

-- bouton d'un groupe où un seul est choisi (onglets, périodes) : le choisi reste en surbrillance
function Opus.Choisir (boutons, choisi)
	for _, b in ipairs(boutons) do
		if b == choisi then b:LockHighlight() b:GetFontString():SetTextColor(1, 1, 1)
		else b:UnlockHighlight() b:GetFontString():SetTextColor(1, 0.82, 0) end
	end
end

-- fond d'une ligne de tableau, une sur deux un peu plus claire
function Opus.FondLigne (ligne, i)
	local fond = ligne:CreateTexture(nil, "BACKGROUND")
	fond:SetAllPoints()
	fond:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0.02)
	return fond
end

------------------------------------------------------------------------
-- pages
------------------------------------------------------------------------

-- construire(cadre) une fois ; rafraichir(cadre) renvoie la hauteur utile ; molette(cadre, delta) facultatif
function Opus.Page (cle, titre, construire, rafraichir, molette)
	pages[cle] = { titre = titre, construire = construire, rafraichir = rafraichir, molette = molette }
	ordre[#ordre + 1] = cle
end

local function Active ()
	return pages[Opus.db.page] and Opus.db.page or ordre[1]
end

-- les pages des essais portent des boutons sécurisés : rien ne bouge en combat
local function Rafraichir ()
	if not f or not f:IsShown() or InCombatLockdown() then return end
	local p = pages[Active()]
	f:SetHeight(HAUT + (p.rafraichir(p.cadre) or 200) + 16)
end
Opus.Rafraichir = Rafraichir

function Opus.Afficher (cle)
	if InCombatLockdown() or not f then return end
	Opus.db.page = cle
	for k, p in pairs(pages) do p.cadre:SetShown(k == cle) end
	Opus.Choisir(f.onglets, pages[cle].onglet)
	Rafraichir()
end

local function Construire ()
	f = CreateFrame("Frame", "OpusFenetre", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(Opus.LARGEUR, 300)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "OpusFenetre")
	f.TitleText:SetText("Opus — guilde")

	f.onglets = {}
	for i, cle in ipairs(ordre) do
		local p = pages[cle]
		p.onglet = Opus.Bouton(f, p.titre, 120, function () Opus.Afficher(cle) end)
		p.onglet:SetPoint("TOPLEFT", 14 + (i - 1) * 124, -30)
		f.onglets[i] = p.onglet
		p.cadre = CreateFrame("Frame", nil, f)
		p.cadre:SetPoint("TOPLEFT", 14, -HAUT)
		p.cadre:SetPoint("TOPRIGHT", -14, -HAUT)
		p.cadre:SetHeight(1)
		p.construire(p.cadre)
		p.cadre:Hide()
	end
	local filet = f:CreateTexture(nil, "ARTWORK")
	filet:SetColorTexture(1, 0.82, 0, 0.25)
	filet:SetPoint("TOPLEFT", 14, -HAUT + 6)
	filet:SetPoint("TOPRIGHT", -14, -HAUT + 6)
	filet:SetHeight(1)

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function (_, d)
		local p = pages[Active()]
		if p.molette then p.molette(p.cadre, d) Rafraichir() end
	end)
	f:SetScript("OnShow", function () Opus.DemanderListe() Rafraichir() end)
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
