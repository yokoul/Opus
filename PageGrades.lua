-- PageGrades.lua : la grille des grades et droits, comparée en direct aux droits réels de la guilde
local _, Opus = ...

local HAUTEUR, ENTETE = 22, 60
local OUI = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local NON = "|cff666666–|r"
local reglages, lignes = {}, {}

local DROITS = { "officier", "inviter", "promouvoir", "retrograder", "exclure", "reparer" }

-- colonnes : titre, x, largeur
local COLONNES = {
	{ "Grade", 2, 104 },
	{ "Officier", 108, 50 }, { "Inviter", 160, 50 }, { "Promo.", 212, 50 }, { "Rétro.", 264, 50 }, { "Exclure", 316, 50 },
	{ "Répar.", 368, 50 }, { "Or / j", 420, 50 },
	{ "Chantier", 474, 70 }, { "Matériaux", 546, 70 }, { "Réserve", 618, 70 },
}

local function Onglet (o)
	if not o.voir then return NON end
	return (o.deposer and "dépôt" or "voir") .. (o.retraits > 0 and (" · " .. o.retraits .. "/j") or "")
end

local function Rafraichir (cadre)
	local reglage = Opus.db.reglage
	for _, b in ipairs(reglages) do
		if b.reglage == reglage then Opus.Choisir(reglages, b) end
	end
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
			l.cases[2]:SetText("|cffaaaaaatous les droits, non modifiables|r")
			for c = 3, #COLONNES do l.cases[c]:SetText("") end
		else
			local a = Opus.Attendu(rang, reglage)
			for k, cle in ipairs(DROITS) do
				local c, e = l.cases[k + 1], ecarts[rang .. cle]
				c:SetText(a[cle] and OUI or NON)
				c.fond:SetShown(e ~= nil)
				c.ecart = e
			end
			l.cases[8]:SetText(a.or_ > 0 and (a.or_ .. " po") or NON)
			for t = 1, 3 do l.cases[8 + t]:SetText(Onglet(a.onglets[t])) end
		end
	end

	local n = 0
	for _ in pairs(ecarts) do n = n + 1 end
	if not conformes then
		cadre.etat:SetText("|cffff6060Les grades en jeu ne correspondent pas à la grille :|r " .. table.concat(soucis, " ; "))
	elseif not lisible then
		cadre.etat:SetText("|cffaaaaaaLe jeu ne donne pas les droits des grades : rien n'est comparé.|r")
	elseif n == 0 then
		cadre.etat:SetText("|cff60ff60Droits conformes à la grille.|r")
	else
		cadre.etat:SetText(("|cffff6060%d droit(s) différent(s) en jeu|r, en rouge : survole-les."):format(n))
	end
	return ENTETE + #Opus.GRADES * HAUTEUR + 70
end

local function Construire (cadre)
	local largeur = Opus.LARGEUR - 28

	-- choix du préréglage : il devient la référence (aussi pour /opus controle)
	for i, r in ipairs { "phase", "raids" } do
		local b = Opus.Bouton(cadre, r == "phase" and "Phase actuelle" or "Raids ouverts", 130, function ()
			Opus.db.reglage = r
			Opus.Rafraichir()
		end)
		b.reglage = r
		b:SetPoint("TOPLEFT", (i - 1) * 134, 0)
		reglages[i] = b
	end
	cadre.detail = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.detail:SetPoint("LEFT", reglages[2], "RIGHT", 12, 0)

	for c, col in ipairs(COLONNES) do
		local h = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", col[2], -38) h:SetWidth(col[3]) h:SetJustifyH(c == 1 and "LEFT" or "CENTER")
		h:SetText(col[1])
	end

	for rang = 1, #Opus.GRADES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -ENTETE + 4 - (rang - 1) * HAUTEUR)
		Opus.FondLigne(l, rang)
		l:EnableMouse(true)
		Opus.Bulle(l, function (self) return self.grade.nom end, function (self) return self.grade.role end)
		l.cases = {}
		for c, col in ipairs(COLONNES) do
			-- chaque case a son cadre : fond rouge et infobulle quand le droit réel diffère
			local case = CreateFrame("Frame", nil, l)
			case:SetPoint("LEFT", col[2], 0) case:SetSize(col[3], HAUTEUR - 2)
			case.fond = case:CreateTexture(nil, "BACKGROUND", nil, 1)
			case.fond:SetAllPoints() case.fond:SetColorTexture(0.8, 0.1, 0.1, 0.45) case.fond:Hide()
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
