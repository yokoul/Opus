-- PageEssais.lua : les membres à l'essai, en deux blocs (Apprentis, Aspirants), et leurs promotions
local _, Opus = ...

local LIGNES, HAUTEUR = 14, 24
local lignes, decalage = {}, 0

-- Promouvoir est réservé à l'interface de Blizzard, mais pas la commande /gpromote : un bouton sécurisé qui
-- l'exécute comme une macro, sur un vrai clic, passe. Un cadre sécurisé ne se modifie pas en combat : la fenêtre
-- se ferme quand il commence, et ne se met pas à jour pendant.
function Opus.BoutonSecurise (parent, largeur, bulle)
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, SharedButtonExtraSmallTemplate")
	b:SetSize(largeur, 20)
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
	local b = Opus.BoutonSecurise(parent, 114, function (self)
		GameTooltip:SetText("Promouvoir vers " .. self.cible)
		GameTooltip:AddLine(("Un clic fait monter d'un grade (/gpromote) : %d clic(s) pour atteindre %s. Le membre reste dans la liste jusque-là."):format(self.crans, self.cible), 1, 1, 1, true)
	end)
	-- après l'action sécurisée : on retient la montée (PostClick ne touche pas à l'action elle-même)
	b:SetScript("PostClick", function (self) Opus.Monter(self.m, self.cible) end)
	return b
end

local function BoutonAnnuler (parent)
	return Opus.BoutonSecurise(parent, 66, function (self)
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
	l.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
	l.grade:SetText(m.montee and Opus.Normal(m.nomGrade) or m.nomGrade)
	if m.jours then
		l.etat:SetText(("%d j sur %d"):format(m.jours, m.duree) .. (m.echu and ("  " .. Opus.Rouge("échu")) or "")
			.. (m.source == "vu" and ("  " .. Opus.Gris("(non noté)")) or ""))
	else
		l.etat:SetText(Opus.Gris("date inconnue"))
	end
	l.dater:SetShown(m.source ~= "note" and not m.montee)
	l.annuler:SetShown(m.montee ~= nil)
	if m.montee then
		l.etat:SetText(Opus.Normal("en route vers " .. m.montee.cible))
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
			b:SetText(m.echu and Opus.Vert(cible) or cible)
			b:SetAttribute("macrotext", "/gpromote " .. m.complet)
		end
	end
end

local function Rafraichir (cadre)
	local elements = Elements()
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
	-- le résumé, dans la bande sous le titre
	local n, echus, montees = 0, 0, 0
	for _, e in ipairs(elements) do
		if e.nom then
			n = n + 1
			if e.echu and not e.montee then echus = echus + 1 end
			if e.montee then montees = montees + 1 end
		end
	end
	cadre.resume:SetText(("%s à l'essai"):format(Opus.Blanc(n))
		.. (echus > 0 and (" · " .. Opus.Vert(echus .. " à promouvoir")) or "")
		.. (montees > 0 and (" · " .. Opus.Normal(montees .. " en route")) or ""))
	return math.min(#elements, LIGNES) * HAUTEUR
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	cadre.resume = barre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	cadre.resume:SetPoint("LEFT", 0, 0)
	local aide = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	aide:SetPoint("RIGHT", 0, 0)
	aide:SetText("Promotions : un clic = un grade · Dater : prépare la note d'officier")
	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -(i - 1) * HAUTEUR)
		l.titre = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		l.titre:SetPoint("LEFT", 2, 0) l.titre:SetJustifyH("LEFT")
		l.voie = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.voie:SetPoint("LEFT", l.titre, "RIGHT", 12, 0) l.voie:SetJustifyH("LEFT")
		l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		l.nom:SetPoint("LEFT", 14, 0) l.nom:SetWidth(130) l.nom:SetJustifyH("LEFT")
		l.grade = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.grade:SetPoint("LEFT", 146, 0) l.grade:SetWidth(80) l.grade:SetJustifyH("LEFT")
		l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.etat:SetPoint("LEFT", 228, 0) l.etat:SetWidth(150) l.etat:SetJustifyH("LEFT")
		l.dater = Opus.Bouton(l, "Dater", 66, function () Opus.Dater(l.m) end, true)
		l.dater:SetPoint("LEFT", 384, 0)
		Opus.Bulle(l.dater, "Dater l'essai", "Retient la date (aujourd'hui si elle est inconnue) et prépare la note d'officier à coller.")
		l.annuler = BoutonAnnuler(l)
		l.annuler:SetPoint("LEFT", 384, 0)
		l.promo = {}
		for k = 1, 2 do
			l.promo[k] = BoutonPromo(l)
			l.promo[k]:SetPoint("LEFT", 456 + (k - 1) * 120, 0)
		end
		lignes[i] = l
	end
end

Opus.Page("essais", "Essais", Construire, Rafraichir, function (_, d) decalage = decalage - d end)
