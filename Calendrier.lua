-- Calendrier.lua : les arrivées et départs de la guilde en calendrier, comme celui du jeu. Une case par jour, avec le
-- blason de classe de ceux qui arrivent (ligne verte) et de ceux qui partent (ligne rouge) ; un clic sur un jour en
-- donne le détail en dessous. Le journal de guilde n'est daté qu'à l'heure près (Journal.lua) : largement assez ici.
-- Le jeu ne donne plus la classe d'un membre parti : l'addon retient celle de chaque membre vu (Opus.db.classes).
local _, Opus = ...

local MOIS = { "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre" }
local JOURS = { "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche" }
local ARRIVEE = { join = true }
local DEPART = { quit = true, remove = true }
local CASE_H, ENTETE, DETAILS_MAX = 50, 44, 12
local INCONNU = "|TInterface\\Icons\\INV_Misc_QuestionMark:0|t"

local function Blason (nom, taille)
	local classe = Opus.db.classes[nom]
	local atlas = classe and GetClassAtlas and GetClassAtlas(classe:lower())
	return atlas and CreateAtlasMarkup(atlas, taille, taille) or INCONNU:gsub(":0|t", ":" .. taille .. "|t")
end

-- le lundi de la semaine du premier du mois, et le nombre de jours du mois
local function Mois (annee, mois)
	local premier = time({ year = annee, month = mois, day = 1, hour = 12 })
	local wday = tonumber(date("%w", premier))          -- 0 = dimanche
	local decale = (wday + 6) % 7                         -- jours avant le premier, depuis lundi
	local jours = tonumber(date("%d", time({ year = annee, month = mois + 1, day = 0, hour = 12 })))
	return premier - decale * 86400, jours
end

local function CleJour (t) return date("%Y-%m-%d", t) end

-- les arrivées et départs, par jour : [aaaa-mm-jj] = { arrivees = { e }, departs = { e } }
local function ParJour ()
	local jours = {}
	for _, e in ipairs(Opus.db.journal.evenements) do
		local sorte = ARRIVEE[e.q] and "arrivees" or DEPART[e.q] and "departs"
		if sorte then
			local cle = CleJour(e.t * 3600)
			jours[cle] = jours[cle] or { arrivees = {}, departs = {} }
			table.insert(jours[cle][sorte], e)
		end
	end
	for _, j in pairs(jours) do
		table.sort(j.arrivees, function (a, b) return a.t < b.t end)
		table.sort(j.departs, function (a, b) return a.t < b.t end)
	end
	return jours
end

local function Qui (e) return e.q == "remove" and e.b or e.a end

-- une ligne de blasons, sans déborder de la case : les premiers, puis « +N »
local function Ligne (liste, place, couleur)
	if #liste == 0 then return "" end
	local icones = {}
	local montres = #liste <= place and #liste or place - 1
	for i = 1, montres do icones[#icones + 1] = Blason(Qui(liste[i]), 14) end
	local reste = #liste - montres
	return table.concat(icones, "") .. (reste > 0 and couleur(" +" .. reste) or "")
end

function Opus.Calendrier (parent, largeur, ouvrirFiche)
	local c = CreateFrame("Frame", nil, parent)
	c:SetPoint("TOPLEFT") c:SetPoint("TOPRIGHT")
	local maintenant = date("*t")
	local annee, mois, choisi = maintenant.year, maintenant.month, nil

	local precedent = Opus.Bouton(c, "<", 28, function () mois = mois - 1 if mois < 1 then mois, annee = 12, annee - 1 end choisi = nil Opus.Rafraichir() end, true)
	precedent:SetPoint("TOPLEFT", 2, -2)
	c.titre = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.titre:SetPoint("LEFT", precedent, "RIGHT", 10, 0)
	local suivant = Opus.Bouton(c, ">", 28, function () mois = mois + 1 if mois > 12 then mois, annee = 1, annee + 1 end choisi = nil Opus.Rafraichir() end, true)
	suivant:SetPoint("LEFT", c.titre, "RIGHT", 10, 0)
	c.total = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.total:SetPoint("TOPRIGHT", -4, -6)

	local l = math.floor((largeur - 14) / 7)
	for i, nom in ipairs(JOURS) do
		local t = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		t:SetPoint("TOPLEFT", (i - 1) * l + 4, -28) t:SetText(nom:sub(1, 3):lower())
	end

	c.cases = {}
	for i = 1, 42 do
		local b = CreateFrame("Button", nil, c)
		b:SetSize(l - 2, CASE_H - 2)
		b:SetPoint("TOPLEFT", ((i - 1) % 7) * l, -(ENTETE + math.floor((i - 1) / 7) * CASE_H))
		b.fond = b:CreateTexture(nil, "BACKGROUND")
		b.fond:SetAllPoints()
		b.cadre = b:CreateTexture(nil, "BORDER")
		b.cadre:SetPoint("TOPLEFT", -1, 1) b.cadre:SetPoint("BOTTOMRIGHT", 1, -1)
		b.cadre:SetColorTexture(1, 0.82, 0, 0.6)
		b.fond:SetDrawLayer("ARTWORK")
		b.jour = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.jour:SetPoint("TOPRIGHT", -4, -3)
		b.arrivees = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.arrivees:SetPoint("TOPLEFT", 4, -16) b.arrivees:SetWordWrap(false)
		b.departs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.departs:SetPoint("TOPLEFT", 4, -32) b.departs:SetWordWrap(false)
		Opus.Survol(b)
		b:SetScript("OnClick", function (self) if self.cle then choisi = self.cle Opus.Rafraichir() end end)
		c.cases[i] = b
	end

	c.detailTitre = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.detailTitre:SetPoint("TOPLEFT", 4, -(ENTETE + 6 * CASE_H + 10))
	c.details = {}
	for i = 1, DETAILS_MAX do
		local d = CreateFrame("Button", nil, c)
		d:SetSize(largeur - 14, 20)
		d:SetPoint("TOPLEFT", 0, -(ENTETE + 6 * CASE_H + 10 + 20 + (i - 1) * 20))
		Opus.Survol(d)
		d.texte = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		d.texte:SetPoint("LEFT", 8, 0) d.texte:SetPoint("RIGHT", -8, 0) d.texte:SetJustifyH("LEFT") d.texte:SetWordWrap(false)
		d:SetScript("OnClick", function (self) if self.nom and Opus.TrouverMembre(self.nom) then ouvrirFiche(self.nom) end end)
		c.details[i] = d
	end

	-- renvoie la hauteur utile, et le texte du résumé du mois
	function c.Rafraichir ()
		local jours = ParJour()
		local debut, nbJours = Mois(annee, mois)
		local aujourdhui = CleJour(time())
		c.titre:SetText(MOIS[mois] .. " " .. annee)
		-- le jour choisi par défaut : aujourd'hui s'il s'y passe quelque chose, sinon le dernier jour animé du mois
		if not choisi then
			for jour = nbJours, 1, -1 do
				local cle = CleJour(time({ year = annee, month = mois, day = jour, hour = 12 }))
				if jours[cle] and cle <= aujourdhui then choisi = cle break end
			end
		end
		local arrivees, departs = 0, 0
		local derniereLigne = 0
		for i, b in ipairs(c.cases) do
			-- midi : un changement d'heure ne fait pas sauter de jour
			local t = debut + (i - 1) * 86400
			local d = date("*t", t)
			local dansLeMois = d.month == mois
			local cle = CleJour(t)
			local j = dansLeMois and jours[cle]
			b.cle = dansLeMois and cle or nil
			b:SetShown(dansLeMois)
			if dansLeMois then
				derniereLigne = math.floor((i - 1) / 7) + 1
				b.jour:SetText(cle == aujourdhui and Opus.Normal(d.day) or d.day)
				b.fond:SetColorTexture(cle == aujourdhui and 0.25 or 0.1, cle == aujourdhui and 0.2 or 0.1, 0.05, 0.6)
				b.cadre:SetShown(cle == choisi)
				local place = math.floor((l - 12) / 15)
				b.arrivees:SetText(j and Ligne(j.arrivees, place, Opus.Vert) or "")
				b.departs:SetText(j and Ligne(j.departs, place, Opus.Rouge) or "")
				if j then arrivees, departs = arrivees + #j.arrivees, departs + #j.departs end
			end
		end
		c.total:SetText(Opus.Vert("+" .. arrivees .. " arrivée(s)") .. Opus.Gris("  ·  ") .. Opus.Rouge("-" .. departs .. " départ(s)"))

		-- le détail du jour choisi, sous la grille
		local y = ENTETE + derniereLigne * CASE_H + 10
		c.detailTitre:ClearAllPoints() c.detailTitre:SetPoint("TOPLEFT", 4, -y)
		local j = choisi and jours[choisi]
		local liste = {}
		if j then
			for _, e in ipairs(j.arrivees) do liste[#liste + 1] = e end
			for _, e in ipairs(j.departs) do liste[#liste + 1] = e end
		end
		if choisi then
			local a, m, jj = choisi:match("(%d+)-(%d+)-(%d+)")
			local t = time({ year = tonumber(a), month = tonumber(m), day = tonumber(jj), hour = 12 })
			c.detailTitre:SetText(JOURS[(tonumber(date("%w", t)) + 6) % 7 + 1] .. " " .. tonumber(jj) .. " " .. MOIS[tonumber(m)]:lower()
				.. (#liste == 0 and Opus.Gris("  · ni arrivée ni départ") or ""))
		else
			c.detailTitre:SetText(Opus.Gris("Aucune arrivée ni aucun départ relevé ce mois-ci."))
		end
		for i, d in ipairs(c.details) do
			local e = liste[i]
			d:SetShown(e ~= nil)
			if e then
				local nom = Qui(e)
				local membre = Opus.TrouverMembre(nom)
				local classe = Opus.db.classes[nom]
				local teinte = classe and Opus.Couleur(classe) or "|cffaaaaaa"
				local quoi = e.q == "join" and Opus.Vert("arrive")
					or e.q == "quit" and Opus.Rouge("part")
					or Opus.Rouge("renvoyé") .. Opus.Gris(" par " .. (e.a or "?"))
				d.nom = nom
				d.texte:SetText(Blason(nom, 16) .. "  " .. teinte .. nom .. "|r   " .. quoi .. Opus.Gris("  " .. date("%H h", e.t * 3600))
					.. (membre and "" or (e.q == "join" and Opus.Gris("  · n'est plus dans la guilde") or "")))
				d:ClearAllPoints() d:SetPoint("TOPLEFT", 0, -(y + 20 + (i - 1) * 20))
			end
		end
		local hauteur = y + 20 + math.min(#liste, DETAILS_MAX) * 20 + 8
		if #liste > DETAILS_MAX then
			hauteur = hauteur + 4
			c.details[DETAILS_MAX].texte:SetText(Opus.Gris(("… et %d autre(s)"):format(#liste - DETAILS_MAX + 1)))
			c.details[DETAILS_MAX].nom = nil
		end
		c:SetHeight(hauteur)
		return hauteur
	end
	return c
end
