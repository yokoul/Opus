-- PageGrades.lua : la grille des grades et droits (la feuille « Guilde Opus · Grades et droits »), comparée en direct
-- aux droits réels de la guilde. Chaque grade dit à quoi il correspond : son rôle, sa voie, et en infobulle ce qu'il fait.
local _, Opus = ...

local HAUTEUR, ENTETE = 30, 22
local lignes = {}
local function Oui () return Opus.Coche(14) end
local function Non () return GRAY_FONT_COLOR:WrapTextInColorCode("–") end

local DROITS = { "officier", "inviter", "promouvoir", "retrograder", "exclure", "reparer" }

-- colonnes : titre, x, largeur ; la première porte le grade, son rôle et sa voie
local COLONNES = {
	{ "Grade", 2, 150 },
	{ "Officier", 154, 46 }, { "Inviter", 202, 46 }, { "Promo.", 250, 46 }, { "Rétro.", 298, 46 }, { "Exclure", 346, 46 },
	{ "Répar.", 394, 46 }, { "Or / j", 442, 46 },
	{ "Chantier", 490, 66 }, { "Matériaux", 558, 66 }, { "Réserve", 626, 62 },
}

local VOIES = { Tour = "voie du Tour", Atelier = "voie de l'Atelier" }

local function Onglet (o)
	if not o.voir then return o.deposer and Opus.Gris("dépôt") or Non() end
	return (o.deposer and "dépôt" or "voir") .. (o.retraits > 0 and (" · " .. o.retraits .. "/j") or "")
end

local function Rafraichir (cadre)
	local avant = Opus.AvantRaids()
	cadre.phase:SetText(avant and (Opus.Normal("Avant les raids : ") .. Opus.RESTRICTION .. ".") or Opus.Vert("Raids ouverts : grille complète."))

	-- écarts avec les droits réels, s'ils se lisent (grades conformes à la grille)
	local ecarts, lisible = {}, false
	local conformes, soucis = Opus.GradesConformes()
	if conformes then
		local liste = Opus.Comparer()
		if liste then
			lisible = true
			for _, e in ipairs(liste) do ecarts[e.rang .. e.cle] = e end
		end
	end

	for rang = 1, #Opus.GRADES do
		local l, g = lignes[rang], Opus.GRADES[rang]
		l.grade = g
		l.nom:SetText(g.nom)
		l.role:SetText(g.role .. (g.voie and (" · " .. VOIES[g.voie]) or ""))
		if rang == 1 then
			l.cases[2]:SetText(Opus.Gris("tous les droits, non modifiables"))
			for c = 3, #COLONNES do l.cases[c]:SetText("") end
		else
			local a = Opus.Attendu(rang)
			for k, cle in ipairs(DROITS) do
				-- un droit différent en jeu : ce qu'il y a vraiment, en rouge (le détail au survol)
				local c, e = l.cases[k + 1], ecarts[rang .. cle]
				if e then c:SetText(Opus.Rouge(e.reel)) else c:SetText(a[cle] and Oui() or Non()) end
				c.ecart = e
			end
			-- avant les raids, réparations et or sont coupés : la valeur de la grille, en gris, entre parenthèses
			local cible = g.or_ or 0
			if avant and cible > 0 then
				l.cases[8]:SetText(Opus.Gris("(" .. cible .. " po)"))
			else
				l.cases[8]:SetText(a.or_ > 0 and (a.or_ .. " po") or Non())
			end
			for t = 1, 3 do l.cases[8 + t]:SetText(Onglet(a.onglets[t])) end
		end
	end

	local n = 0
	for _ in pairs(ecarts) do n = n + 1 end
	if not conformes then
		cadre.etat:SetText(Opus.Rouge("Les grades en jeu ne correspondent pas à la grille : ") .. table.concat(soucis, " ; "))
	elseif not lisible then
		cadre.etat:SetText(Opus.Gris("Le jeu ne donne pas les droits des grades : rien n'est comparé."))
	elseif n == 0 then
		cadre.etat:SetText(Opus.Vert("Droits conformes à la grille."))
	else
		cadre.etat:SetText(Opus.Rouge(("%d droit(s) différent(s) en jeu"):format(n)) .. ", en rouge : survole-les.")
	end
	return ENTETE + #Opus.GRADES * HAUTEUR + 64
end

local function Bulle (self)
	local g, texte = self.grade, {}
	texte[#texte + 1] = g.role .. (g.voie and (" · " .. VOIES[g.voie]) or "")
	if g.desc then texte[#texte + 1] = g.desc end
	local sorties = Opus.SORTIES[g.nom]
	if sorties then
		texte[#texte + 1] = ("Essai de %d jours, puis %s."):format(Opus.db.dureeEssai[g.nom] or 14, table.concat(sorties, " ou "))
	end
	return texte
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	cadre.phase = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.phase:SetPoint("LEFT", 0, 0) cadre.phase:SetPoint("RIGHT", 0, 0) cadre.phase:SetJustifyH("LEFT")

	for c, col in ipairs(COLONNES) do
		local h = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", col[2], -4) h:SetWidth(col[3]) h:SetJustifyH(c == 1 and "LEFT" or "CENTER")
		h:SetText(col[1])
	end

	for rang = 1, #Opus.GRADES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -ENTETE - (rang - 1) * HAUTEUR)
		Opus.Survol(l)
		l:EnableMouse(true)
		Opus.Bulle(l, function (self) return self.grade.nom end, Bulle)
		-- le grade sur deux lignes : son nom, puis son rôle et sa voie
		l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		l.nom:SetPoint("TOPLEFT", 2, -3) l.nom:SetJustifyH("LEFT")
		l.role = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.role:SetPoint("TOPLEFT", l.nom, "BOTTOMLEFT", 0, -1) l.role:SetWidth(150) l.role:SetJustifyH("LEFT") l.role:SetWordWrap(false)
		l.cases = {}
		for c, col in ipairs(COLONNES) do
			if c > 1 then
				-- chaque case a son cadre : infobulle quand le droit réel diffère (texte en rouge)
				local case = CreateFrame("Frame", nil, l)
				case:SetPoint("LEFT", col[2], 0) case:SetSize(col[3], HAUTEUR - 2)
				local t = case:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				t:SetAllPoints() t:SetJustifyH("CENTER") t:SetWordWrap(false)
				case.SetText = function (_, s) t:SetText(s) end
				if c <= 7 then
					case:EnableMouse(true)
					case:SetScript("OnEnter", function (self)
						if not self.ecart then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:SetText(self.ecart.quoi)
						GameTooltip:AddLine(("En jeu : %s ; la grille dit : %s."):format(self.ecart.reel, self.ecart.attendu), 1, 1, 1, true)
						GameTooltip:AddLine("À corriger dans Guilde > Paramètres de guilde.", 0.7, 0.7, 0.7, true)
						GameTooltip:Show()
					end)
					case:SetScript("OnLeave", GameTooltip_Hide)
				end
				l.cases[c] = case
			end
		end
		lignes[rang] = l
	end
	-- « tous les droits » du Magister s'étend sur la ligne
	lignes[1].cases[2]:SetWidth(largeur - 160)

	local bas = -ENTETE - #Opus.GRADES * HAUTEUR
	cadre.etat = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.etat:SetPoint("TOPLEFT", 2, bas - 6) cadre.etat:SetWidth(largeur - 4) cadre.etat:SetJustifyH("LEFT")
	local note = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 2, bas - 24) note:SetWidth(largeur - 4) note:SetJustifyH("LEFT")
	note:SetText("Survole un grade pour son rôle. Seuls les droits se comparent : le plafond d'or et les onglets ne se lisent pas "
		.. "pour un addon, et un addon ne modifie pas les grades : tout se règle dans Guilde > Paramètres de guilde (/opus fiche "
		.. "l'écrit dans la discussion).")
end

Opus.Page("grades", "Grades", Construire, Rafraichir)
