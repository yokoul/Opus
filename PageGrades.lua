-- PageGrades.lua : la grille des grades et droits, comparée en direct aux droits réels de la guilde
local _, Opus = ...

local HAUTEUR, ENTETE = 22, 22
local lignes = {}
local function Oui () return Opus.Coche(14) end
local function Non () return GRAY_FONT_COLOR:WrapTextInColorCode("–") end

local DROITS = { "officier", "inviter", "promouvoir", "retrograder", "exclure", "reparer" }

-- colonnes : titre, x, largeur
local COLONNES = {
	{ "Grade", 2, 104 },
	{ "Officier", 108, 50 }, { "Inviter", 160, 50 }, { "Promo.", 212, 50 }, { "Rétro.", 264, 50 }, { "Exclure", 316, 50 },
	{ "Répar.", 368, 50 }, { "Or / j", 420, 50 },
	{ "Chantier", 474, 70 }, { "Matériaux", 546, 70 }, { "Réserve", 618, 70 },
}

local function Onglet (o)
	if not o.voir then return Non() end
	return (o.deposer and "dépôt" or "voir") .. (o.retraits > 0 and (" · " .. o.retraits .. "/j") or "")
end

local function Rafraichir (cadre)
	local reglage = Opus.db.reglage
	cadre.reglage:GenerateMenu()
	cadre.detail:SetText(Opus.REGLAGES[reglage])

	-- écarts avec les droits réels, s'ils se lisent (grades conformes à la grille)
	local ecarts, lisible = {}, false
	local conformes, soucis = Opus.GradesConformes()
	if conformes then
		local liste = Opus.Comparer(reglage)
		if liste then
			lisible = true
			for _, e in ipairs(liste) do ecarts[e.rang .. e.cle] = e end
		end
	end

	for rang = 1, #Opus.GRADES do
		local l, g = lignes[rang], Opus.GRADES[rang]
		l.grade = g
		l.cases[1]:SetText(g.nom)
		if rang == 1 then
			l.cases[2]:SetText(Opus.Gris("tous les droits, non modifiables"))
			for c = 3, #COLONNES do l.cases[c]:SetText("") end
		else
			local a = Opus.Attendu(rang, reglage)
			for k, cle in ipairs(DROITS) do
				local c, e = l.cases[k + 1], ecarts[rang .. cle]
				-- un droit différent en jeu : ce qu'il y a vraiment, en rouge (le détail au survol)
				if e then c:SetText(Opus.Rouge(e.reel == "oui" and "oui" or "non")) else c:SetText(a[cle] and Oui() or Non()) end
				c.ecart = e
			end
			l.cases[8]:SetText(a.or_ > 0 and (a.or_ .. " po") or Non())
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
	return ENTETE + #Opus.GRADES * HAUTEUR + 70
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	-- le préréglage de référence (aussi pour /opus controle), en menu du client
	cadre.reglage = Opus.Menu(barre, 150, { { "phase", "Phase actuelle" }, { "raids", "Raids ouverts" } },
		function () return Opus.db.reglage end,
		function (v) Opus.db.reglage = v Opus.Rafraichir() end)
	cadre.reglage:SetPoint("LEFT", 0, 0)
	cadre.detail = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.detail:SetPoint("LEFT", cadre.reglage, "RIGHT", 12, 0)

	for c, col in ipairs(COLONNES) do
		local h = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", col[2], -4) h:SetWidth(col[3]) h:SetJustifyH(c == 1 and "LEFT" or "CENTER")
		h:SetText(col[1])
	end

	for rang = 1, #Opus.GRADES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -ENTETE + 4 - (rang - 1) * HAUTEUR)
		Opus.Survol(l)
		l:EnableMouse(true)
		Opus.Bulle(l, function (self) return self.grade.nom end, function (self) return self.grade.role end)
		l.cases = {}
		for c, col in ipairs(COLONNES) do
			-- chaque case a son cadre : infobulle quand le droit réel diffère (texte en rouge)
			local case = CreateFrame("Frame", nil, l)
			case:SetPoint("LEFT", col[2], 0) case:SetSize(col[3], HAUTEUR - 2)
			local t = case:CreateFontString(nil, "OVERLAY", c == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
			t:SetAllPoints() t:SetJustifyH(c == 1 and "LEFT" or "CENTER") t:SetWordWrap(false)
			case.SetText = function (_, s) t:SetText(s) end
			if c >= 2 and c <= 7 then
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
		lignes[rang] = l
	end
	-- la première case (« tous les droits ») du Magister s'étend sur la ligne
	lignes[1].cases[2]:SetWidth(largeur - 110)
	lignes[1].cases[2]:SetPoint("LEFT", 108, 0)

	local bas = -ENTETE - #Opus.GRADES * HAUTEUR
	cadre.etat = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.etat:SetPoint("TOPLEFT", 2, bas - 2) cadre.etat:SetWidth(largeur - 4) cadre.etat:SetJustifyH("LEFT")
	local note = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 2, bas - 22) note:SetWidth(largeur - 4) note:SetJustifyH("LEFT")
	note:SetText("Seuls les droits se comparent : le plafond d'or et les onglets ne se lisent pas pour un addon. "
		.. "Un addon ne peut pas non plus modifier les grades : tout se règle dans Guilde > Paramètres de guilde. "
		.. "/opus fiche phase|raids écrit la fiche dans la discussion.")
end

Opus.Page("grades", "Grades", Construire, Rafraichir)
