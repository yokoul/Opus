-- Fenetre.lua : la fenêtre /opus (contrôle de la grille, membres à l'essai)
local _, Opus = ...

local LIGNES, HAUTEUR = 14, 24
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
local function BoutonSecurise (parent, largeur, bulle)
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
	b:SetSize(largeur, 22)
	b:RegisterForClicks("AnyUp", "AnyDown")   -- le modèle ne retient que le sens réglé par ActionButtonUseKeyDown
	b:SetAttribute("type", "macro")
	b:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		bulle(self)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function BoutonPromo (parent)
	local b = BoutonSecurise(parent, 118, function (self)
		GameTooltip:SetText("Promouvoir vers " .. self.cible)
		GameTooltip:AddLine(("Un clic fait monter d'un grade (/gpromote) : %d clic(s) pour atteindre %s. Le membre reste dans la liste jusque-là."):format(self.crans, self.cible), 1, 1, 1, true)
	end)
	-- après l'action sécurisée : on retient la montée (PostClick ne touche pas à l'action elle-même)
	b:SetScript("PostClick", function (self) Opus.Monter(self.m, self.cible) end)
	return b
end

local function BoutonAnnuler (parent)
	return BoutonSecurise(parent, 60, function (self)
		GameTooltip:SetText("Annuler la montée")
		GameTooltip:AddLine(("Un clic fait redescendre d'un grade (/gdemote), jusqu'à %s."):format(self.depuis), 1, 1, 1, true)
	end)
end

-- en-tête d'un bloc : « Aspirants · essai raid » et la voie, « Tour : vers Itinérant (raiders en rotation) ou … »
local function EnTete (nom)
	local g = Opus.GRADES[Opus.RangDe(nom)]
	local vers = {}
	for _, cible in ipairs(Opus.SORTIES[nom] or {}) do
		vers[#vers + 1] = cible .. " (" .. Opus.GRADES[Opus.RangDe(cible)].role:lower() .. ")"
	end
	return nom .. "s · essai " .. g.essai, "voie de " .. (g.voie == "Tour" and "la Tour" or "l'" .. g.voie) .. " : vers " .. table.concat(vers, " ou ")
end

-- les lignes affichées : pour chaque bloc, son en-tête puis ses membres (ou « personne »)
local function Elements ()
	local essais, elements = Opus.Essais(), {}
	for _, bloc in ipairs(Opus.BLOCS) do
		elements[#elements + 1] = { bloc = bloc }
		local n = 0
		for _, m in ipairs(essais) do
			if m.essai == bloc then elements[#elements + 1] = m n = n + 1 end
		end
		if n == 0 then elements[#elements + 1] = { vide = true } end
	end
	return elements
end

local function LigneMembre (l, m)
	l.m = m
	l.nom:SetText(Couleur(m.classe) .. m.nom .. "|r")
	l.grade:SetText(m.montee and ("|cffffd100" .. m.nomGrade .. "|r") or m.nomGrade)
	if m.jours then
		l.etat:SetText(("%d j sur %d"):format(m.jours, m.duree) .. (m.echu and "  |cffff6060échu|r" or "")
			.. (m.source == "vu" and "  |cffaaaaaa(non noté)|r" or ""))
	else
		l.etat:SetText("|cffaaaaaadate inconnue|r")
	end
	l.dater:SetShown(m.source ~= "note" and not m.montee)
	l.annuler:SetShown(m.montee ~= nil)
	if m.montee then
		l.etat:SetText("|cffffd100en route vers " .. m.montee.cible .. "|r")
		l.annuler.depuis = m.montee.depuis
		l.annuler:SetAttribute("macrotext", "/gdemote " .. m.complet)
	end
	-- pendant une montée, seul le grade visé reste proposé
	local sorties = m.montee and { m.montee.cible } or Opus.SORTIES[m.nomGrade] or {}
	for k = 1, 2 do
		local b, cible = l.promo[k], sorties[k]
		b:SetShown(cible ~= nil)
		if cible then
			b.m, b.cible, b.crans = m, cible, m.grade - Opus.RangDe(cible)
			b:SetText((m.echu and "|cff60ff60" or "") .. cible)
			b:SetAttribute("macrotext", "/gpromote " .. m.complet)
		end
	end
end

local function Rafraichir ()
	if not f or not f:IsShown() or InCombatLockdown() then return end
	f.reglage:SetText("Référence : |cffffd100" .. Opus.REGLAGES[Opus.db.reglage] .. "|r")

	local elements = Elements()
	f:SetHeight(110 + math.min(#elements, LIGNES) * HAUTEUR)
	decalage = math.max(0, math.min(decalage, #elements - LIGNES))
	for i = 1, LIGNES do
		local l, e = lignes[i], elements[i + decalage]
		l:SetShown(e ~= nil)
		if e then
			local membre = not (e.bloc or e.vide)
			for _, w in ipairs { l.nom, l.grade, l.etat } do w:SetShown(membre) end
			l.titre:SetShown(e.bloc ~= nil or e.vide)
			l.voie:SetShown(e.bloc ~= nil)
			if membre then
				LigneMembre(l, e)
			else
				l.dater:Hide() l.annuler:Hide() l.promo[1]:Hide() l.promo[2]:Hide()
				if e.bloc then
					local titre, voie = EnTete(e.bloc)
					l.titre:SetFontObject("GameFontNormal") l.titre:SetText(titre)
					l.voie:SetText(voie)
				else
					l.titre:SetFontObject("GameFontDisableSmall") l.titre:SetText("    personne pour l'instant")
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

	-- essais : un bloc par grade d'essai (Opus.BLOCS)
	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, f)
		l:SetSize(LARGEUR - 30, HAUTEUR)
		l:SetPoint("TOPLEFT", 14, -86 - (i - 1) * HAUTEUR)
		l.titre = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		l.titre:SetPoint("LEFT", 2, 0) l.titre:SetJustifyH("LEFT")
		l.voie = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.voie:SetPoint("LEFT", l.titre, "RIGHT", 12, 0) l.voie:SetJustifyH("LEFT")
		l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		l.nom:SetPoint("LEFT", 2, 0) l.nom:SetWidth(110) l.nom:SetJustifyH("LEFT")
		l.grade = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.grade:SetPoint("LEFT", 114, 0) l.grade:SetWidth(76) l.grade:SetJustifyH("LEFT")
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
		l.annuler = BoutonAnnuler(l)
		l.annuler:SetPoint("LEFT", 340, 0)
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
