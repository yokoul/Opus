-- Fenetre.lua : la fenêtre /opus (contrôle de la grille, membres à l'essai)
local _, Opus = ...

local LIGNES, HAUTEUR = 12, 24
local LARGEUR = 680
local f, lignes, decalage = nil, {}, 0

local function Couleur (classe)
	local c = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
	return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

local function Bouton (parent, texte, largeur, clic)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(largeur, 22)
	b:SetText(texte)
	b:SetScript("OnClick", clic)
	return b
end

-- Promouvoir est réservé à l'interface de Blizzard, mais pas la commande /gpromote : un bouton sécurisé qui
-- l'exécute comme une macro, sur un vrai clic, passe. Un cadre sécurisé ne se modifie pas en combat : la fenêtre
-- se ferme quand il commence, et ne se met pas à jour pendant.
local function BoutonPromo (parent)
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
	b:SetSize(118, 22)
	b:RegisterForClicks("AnyUp", "AnyDown")   -- le modèle ne retient que le sens réglé par ActionButtonUseKeyDown
	b:SetAttribute("type", "macro")
	b:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Promouvoir vers " .. self.cible)
		GameTooltip:AddLine(("Un clic fait monter d'un grade (/gpromote) : %d clic(s) pour atteindre %s."):format(self.crans, self.cible), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function Rafraichir ()
	if not f or not f:IsShown() or InCombatLockdown() then return end
	f.reglage:SetText("Référence : |cffffd100" .. Opus.REGLAGES[Opus.db.reglage] .. "|r")

	local liste = Opus.Essais()
	f.vide:SetShown(#liste == 0)
	f:SetHeight(130 + math.max(1, math.min(#liste, LIGNES)) * HAUTEUR)
	decalage = math.max(0, math.min(decalage, #liste - LIGNES))
	for i = 1, LIGNES do
		local l, m = lignes[i], liste[i + decalage]
		l:SetShown(m ~= nil)
		if m then
			l.m = m
			l.nom:SetText(Couleur(m.classe) .. m.nom .. "|r")
			l.grade:SetText(m.nomGrade)
			if m.jours then
				l.etat:SetText(("%d j sur %d"):format(m.jours, m.duree) .. (m.echu and "  |cffff6060échu|r" or "")
					.. (m.source == "vu" and "  |cffaaaaaa(non noté)|r" or ""))
			else
				l.etat:SetText("|cffaaaaaadate inconnue|r")
			end
			l.dater:SetShown(m.source ~= "note")
			local sorties = Opus.SORTIES[m.nomGrade] or {}
			for k = 1, 2 do
				local b, cible = l.promo[k], sorties[k]
				b:SetShown(cible ~= nil)
				if cible then
					b.cible, b.crans = cible, m.grade - Opus.RangDe(cible)
					b:SetText((m.echu and "|cff60ff60" or "") .. cible)
					b:SetAttribute("macrotext", "/gpromote " .. m.complet)
				end
			end
		end
	end
end
Opus.Rafraichir = Rafraichir

local function Construire ()
	f = CreateFrame("Frame", "OpusFenetre", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(LARGEUR, 130 + HAUTEUR)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "OpusFenetre")
	f.TitleText:SetText("Opus — guilde")

	-- grille
	f.reglage = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.reglage:SetPoint("TOPLEFT", 16, -34)
	local controle = Bouton(f, "Contrôler", 110, function () Opus.Rapport() end)
	controle:SetPoint("TOPLEFT", 14, -54)
	local fichePhase = Bouton(f, "Fiche : phase", 130, function () Opus.Fiche("phase") end)
	fichePhase:SetPoint("LEFT", controle, "RIGHT", 8, 0)
	local ficheRaids = Bouton(f, "Fiche : raids", 130, function () Opus.Fiche("raids") end)
	ficheRaids:SetPoint("LEFT", fichePhase, "RIGHT", 8, 0)

	-- essais
	local titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titre:SetPoint("TOPLEFT", 16, -88)
	titre:SetText("Membres à l'essai")
	f.vide = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.vide:SetPoint("TOPLEFT", 16, -112)
	f.vide:SetText("Aucun Apprenti ni Aspirant pour l'instant.")

	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, f)
		l:SetSize(LARGEUR - 30, HAUTEUR)
		l:SetPoint("TOPLEFT", 14, -104 - (i - 1) * HAUTEUR)
		l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		l.nom:SetPoint("LEFT", 2, 0) l.nom:SetWidth(110) l.nom:SetJustifyH("LEFT")
		l.grade = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.grade:SetPoint("LEFT", 114, 0) l.grade:SetWidth(70) l.grade:SetJustifyH("LEFT")
		l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.etat:SetPoint("LEFT", 186, 0) l.etat:SetWidth(150) l.etat:SetJustifyH("LEFT")
		l.dater = Bouton(l, "Dater", 60, function () Opus.Dater(l.m) end)
		l.dater:SetPoint("LEFT", 340, 0)
		l.dater:SetScript("OnEnter", function (self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Dater l'essai")
			GameTooltip:AddLine("Retient la date (aujourd'hui si elle est inconnue) et prépare la note d'officier à coller.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		l.dater:SetScript("OnLeave", GameTooltip_Hide)
		l.promo = {}
		for k = 1, 2 do
			l.promo[k] = BoutonPromo(l)
			l.promo[k]:SetPoint("LEFT", 406 + (k - 1) * 122, 0)
		end
		lignes[i] = l
	end
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function (_, d) decalage = decalage - d Rafraichir() end)
	f:SetScript("OnShow", function () Opus.DemanderListe() Rafraichir() end)
	f:Hide()
end

function Opus.Fenetre ()
	if not IsInGuild() then Opus.Msg("tu n'es pas en guilde.") return end
	if InCombatLockdown() then Opus.Msg("pas en combat.") return end
	if not f then Construire() end
	f:SetShown(not f:IsShown())
	if f:IsShown() then Rafraichir() end
end

Opus.Ecoute("GUILD_ROSTER_UPDATE", Rafraichir)
-- l'entrée en combat laisse encore modifier les cadres sécurisés : c'est le moment de fermer
Opus.Ecoute("PLAYER_REGEN_DISABLED", function () if f then f:Hide() end end)
