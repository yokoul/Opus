-- PageGuilde.lua : le tableau de la guilde. Les membres regroupés par voie (et les essais à part), avec leur classe,
-- joueur Discord, grade, niveau, ancienneté et dernière connexion ; un clic ouvre la fiche du membre (ses persos, ses
-- niveaux, ses notes, son histoire dans la guilde). Le journal de guilde brut reste une des vues du menu.
local _, Opus = ...

local LIGNES, HAUTEUR = 16, 22
local lignes, decalage = {}, 0
local vue, fiche = "voies", nil         -- vue du menu ; fiche = nom du membre ouvert
local tousNiveaux = false              -- fiche : la liste de tous ses niveaux est dépliée
local PERSOS_MAX = 8                   -- persos du même joueur montrés dans la fiche

local VUES = {
	{ "voies", "Membres par voie" }, { "enligne", "Membres en ligne" },
	{ "tout", "Journal : tout" }, { "mouvements", "Journal : arrivées et départs" }, { "grades", "Journal : grades" },
}
local JOURNAL = { tout = true, mouvements = true, grades = true }

local NOTES_MAX = 130         -- hauteur de la boîte des notes dans la fiche, au-delà on défile dedans
-- l'étoile d'un main : l'icône du marqueur de raid (les polices du jeu n'ont pas l'emoji ⭐, affiché en carré)
local ETOILE = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"

local function Icone (classe, taille)
	local atlas = classe and GetClassAtlas and GetClassAtlas(classe:lower())
	return atlas and CreateAtlasMarkup(atlas, taille or 16, taille or 16) or ""
end

local function Duree (secondes)
	local j = math.floor(secondes / 86400)
	if j < 1 then return "aujourd'hui" elseif j < 60 then return j .. " j" end
	return math.floor(j / 30) .. " mois"
end

-- depuis quand un membre est dans la guilde : son arrivée au journal, sinon la première fois que l'addon l'a vu
-- Depuis quand un membre est dans la guilde : son arrivée au journal ; sinon il est arrivé avant le journal relevé :
-- chez Opus, on le compte depuis la création de la guilde ; ailleurs, « avant » le premier du mois du plus ancien relevé.
-- Renvoie t, et "exact", "creation" ou "avant".
Opus.CREATION_OPUS = time({ year = 2026, month = 11, day = 5, hour = 0 })
local function Anciennete (m)
	local t = Opus.ArriveeJournal(m.nom)
	if t then return t, "exact" end
	if GetGuildInfo("player") == "Opus" then return Opus.CREATION_OPUS, "creation" end
	local plusAncien
	for _, e in ipairs(Opus.db.journal.evenements) do plusAncien = math.min(plusAncien or e.t, e.t) end
	if not plusAncien then return nil end
	local d = date("*t", plusAncien * 3600)
	return time({ year = d.year, month = d.month, day = 1, hour = 0 }), "avant"
end

local function TexteAnciennete (t, sorte)
	if not t then return "" end
	if sorte == "creation" then return Opus.Gris(date("%d/%m", t) .. " (création)") end
	if sorte == "avant" then return Opus.Gris("avant le " .. date("%d/%m", t)) end
	return Duree(time() - t)
end

local function Statut (m)
	if m.enLigne then return Opus.Vert("en ligne") .. (m.zone and (" · " .. m.zone) or "") end
	local zone = m.zone and m.zone ~= "" and (" · " .. m.zone) or ""
	if m.absent then return Opus.Gris("vu il y a " .. Opus.Depuis(math.floor(time() / 3600) - m.absent) .. zone) end
	return Opus.Gris("hors ligne" .. zone)
end

------------------------------------------------------------------------
-- la liste des membres
------------------------------------------------------------------------

local function Elements ()
	local groupes, ordre = {}, {}
	for _, m in ipairs(Opus.Membres()) do
		if vue ~= "enligne" or m.enLigne then
			local g = Opus.GRADES[m.grade] or {}
			local cle = (g.essai or Opus.db.montees[m.nom]) and "essai" or (g.voie or "commun")
			if not groupes[cle] then groupes[cle] = { cle = cle, membres = {}, rang = 99 } ordre[#ordre + 1] = groupes[cle] end
			local gr = groupes[cle]
			gr.membres[#gr.membres + 1] = m
			gr.rang = math.min(gr.rang, m.grade)
		end
	end
	-- les voies dans l'ordre de leur meilleur grade, les essais à la fin
	table.sort(ordre, function (a, b)
		if (a.cle == "essai") ~= (b.cle == "essai") then return b.cle == "essai" end
		return a.rang < b.rang
	end)
	local elements = {}
	for _, gr in ipairs(ordre) do
		local titre = gr.cle == "essai" and "À l'essai" or gr.cle == "commun" and "Commun" or (Opus.NomVoie(gr.cle):gsub("^%l", string.upper))
		elements[#elements + 1] = { titre = titre, n = #gr.membres }
		table.sort(gr.membres, function (a, b)
			if a.grade ~= b.grade then return a.grade < b.grade end
			if a.enLigne ~= b.enLigne then return a.enLigne end
			if a.niveau ~= b.niveau then return a.niveau > b.niveau end
			return a.nom < b.nom
		end)
		for _, m in ipairs(gr.membres) do elements[#elements + 1] = m end
	end
	return elements
end

local function LigneMembre (l, m)
	local atlas = m.classe and GetClassAtlas and GetClassAtlas(m.classe:lower())
	if atlas then l.icone:SetAtlas(atlas) end
	l.icone:SetShown(atlas ~= nil)
	l.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
	-- son joueur Discord (dernier import) : en blanc avec une étoile sur un main, en gris sur un reroll ; « +2 » : ses
	-- autres persos connus
	local j, _, main = Opus.Discord(m.nom)
	local autres = j and #j.persos - 1 or 0
	l.joueur:SetText(j and ((main and (Opus.Blanc(j.pseudo) .. " " .. ETOILE) or Opus.Gris(j.pseudo)) .. (autres > 0 and Opus.Gris(" +" .. autres) or "")) or Opus.Gris("–"))
	l.grade:SetText(m.nomGrade)
	l.niveau:SetText(m.niveau)
	l.depuis:SetText(TexteAnciennete(Anciennete(m)))
	l.statut:SetText(Statut(m))
end

------------------------------------------------------------------------
-- la fiche d'un membre
------------------------------------------------------------------------

-- une colonne de note : titre, bouton « Modifier », et une boîte de hauteur limitée qui défile à la molette
local function ColonneNote (f, titre, genre)
	local col = {}
	col.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	col.titre:SetText(titre)
	col.bouton = Opus.Bouton(f, "Modifier", 80, function () Opus.EditerNote(genre, fiche) end, true)
	col.boite = CreateFrame("ScrollFrame", nil, f)
	col.boite:SetPoint("TOPLEFT", col.titre, "BOTTOMLEFT", 0, -6)
	col.dedans = CreateFrame("Frame", nil, col.boite)
	col.boite:SetScrollChild(col.dedans)
	col.texte = col.dedans:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	col.texte:SetPoint("TOPLEFT") col.texte:SetJustifyH("LEFT") col.texte:SetSpacing(3)
	local total, visibles = 0, 0
	function col.Defiler (y)
		y = math.max(0, math.min(math.max(0, total - visibles), y))
		col.boite:SetVerticalScroll(y)
		col.ascenseur:Recaler(y, total, visibles)
	end
	col.ascenseur = Opus.Ascenseur(f, col.Defiler)
	col.ascenseur:SetPoint("TOPRIGHT", col.boite, "TOPRIGHT")
	col.ascenseur:SetPoint("BOTTOMRIGHT", col.boite, "BOTTOMRIGHT")
	col.boite:EnableMouseWheel(true)
	col.boite:SetScript("OnMouseWheel", function (self, d) col.Defiler((tonumber(self:GetVerticalScroll()) or 0) - d * 30) end)
	-- largeur de la colonne, à partir de x ; renvoie la hauteur du texte
	function col.Placer (x, largeur, texte)
		col.titre:SetShown(true)
		col.bouton:ClearAllPoints()
		col.bouton:SetPoint("TOP", col.titre, "TOP", 0, 3)
		col.bouton:SetPoint("RIGHT", f, "LEFT", x + largeur, 0)
		col.boite:SetWidth(largeur) col.dedans:SetWidth(largeur - 16) col.texte:SetWidth(largeur - 16)
		col.texte:SetText(texte)
		local h = col.texte:GetStringHeight()
		return math.ceil(type(h) == "number" and h or 14)
	end
	-- hauteur de la boîte (la même pour les deux colonnes) ; revient en haut quand la fiche change
	function col.Hauteur (texte, boite, nouvelle)
		total, visibles = texte, boite
		col.boite:SetHeight(boite) col.dedans:SetHeight(texte)
		col.Defiler(nouvelle and 0 or (tonumber(col.boite:GetVerticalScroll()) or 0))
	end
	function col.Montrer (oui, peut)
		for _, w in ipairs { col.titre, col.boite, col.ascenseur } do w:SetShown(oui) end
		col.bouton:SetShown(oui and peut)
	end
	return col
end

local function Fiche (cadre)
	local m = Opus.TrouverMembre(fiche)
	local c = cadre.fiche
	local nom = function (n) local x = Opus.TrouverMembre(n) return x and (Opus.Couleur(x.classe) .. n .. "|r") or Opus.Gris(n) end
	local g = m and Opus.GRADES[m.grade] or {}
	c.icone:SetText(m and Icone(m.classe, 40) or "")
	c.titre:SetText(m and (Opus.Couleur(m.classe) .. m.nom .. "|r") or Opus.Gris(fiche .. " (n'est plus dans la guilde)"))
	c.sous:SetText(m and (m.nomGrade .. (g.role and g.role ~= "" and (" · " .. g.role) or "") .. " · niveau " .. m.niveau) or "")
	c.statut:SetText(m and Statut(m) or "")

	local infos = {}
	if m then
		local t, sorte = Anciennete(m)
		if t then
			infos[#infos + 1] = Opus.Normal("Dans la guilde : ") .. (sorte == "creation" and ("depuis la création de la guilde (" .. date("%d/%m/%Y", t) .. ")")
				or sorte == "avant" and ("arrivé avant le " .. date("%d/%m/%Y", t) .. ", début du journal relevé")
				or ("depuis le " .. date("%d/%m/%Y", t) .. " (" .. Duree(time() - t) .. ")"))
		end
		-- son joueur Discord (Lien.lua) ; ses persos sont dans le bloc « Ses persos »
		local j, _, main = Opus.Discord(m.nom)
		if j then
			infos[#infos + 1] = Opus.Normal("Discord : ") .. Opus.Blanc(j.pseudo) .. (main and (Opus.Gris(" · son main ") .. ETOILE) or Opus.Gris(" · reroll"))
		end
		if m.note ~= "" then infos[#infos + 1] = Opus.Normal("Note du jeu : ") .. m.note end
		if m.noteOff ~= "" then infos[#infos + 1] = Opus.Normal("Note d'officier du jeu : ") .. m.noteOff end
	end
	c.infos:SetText(table.concat(infos, "\n"))
	local function H (t) local h = t:GetStringHeight() return type(h) == "number" and h or 14 end
	local y = 60 + (#infos > 0 and H(c.infos) or 0) + 16

	-- ses persos (Discord et même compte), une ligne chacun ; un clic ouvre sa fiche
	local persos = m and Opus.PersosDuJoueur(m.nom) or {}
	local montrer = #persos > 1
	c.persosTitre:SetShown(montrer)
	for i = 1, PERSOS_MAX do
		local l, p = c.persos[i], montrer and persos[i]
		l:SetShown(p ~= nil and p ~= false)
		if p then
			local x = p.membre
			l.nom = p.nom
			local atlas = x.classe and GetClassAtlas and GetClassAtlas(x.classe:lower())
			if atlas then l.icone:SetAtlas(atlas) end
			l.icone:SetShown(atlas ~= nil)
			l.texte:SetText(Opus.Couleur(x.classe) .. p.nom .. "|r" .. (p.main and (" " .. ETOILE) or "") .. (p.nom == m.nom and Opus.Gris("  (cette fiche)") or ""))
			l.niveau:SetText(x.niveau or "")
			l.grade:SetText(x.nomGrade or "")
			l.statut:SetText(x.enLigne ~= nil and Statut(x) or "")
			l:ClearAllPoints() l:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(y + 20 + (i - 1) * 20))
		end
	end
	if montrer then
		c.persosTitre:ClearAllPoints() c.persosTitre:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -y)
		y = y + 20 + math.min(#persos, PERSOS_MAX) * 20 + 14
	end

	-- ses niveaux (Niveaux.lua) : le 60 en avant, la liste complète en dépliant
	local montees = Opus.Montees(fiche)
	local resume
	if montees[1] and montees[1].niveau >= 60 then
		local e = montees[1]
		resume = ETOILE .. " |cffffd100Niveau 60|r " .. (e.approche and Opus.Gris("vu le " .. date("%d/%m/%Y", e.t)) or ("le " .. date("%d/%m/%Y à %H h %M", e.t)))
	elseif montees[1] then
		local e = montees[1]
		resume = "Dernier niveau : " .. Opus.Blanc(e.niveau) .. (e.approche and Opus.Gris(", vu le " .. date("%d/%m", e.t)) or (", le " .. date("%d/%m à %H h %M", e.t)))
	else
		resume = Opus.Gris("Aucune montée relevée pour l'instant : l'addon les note quand il les voit passer.")
	end
	if tousNiveaux and #montees > 0 then
		local liste = {}
		for _, e in ipairs(montees) do
			local quand = date(e.approche and "%d/%m" or "%d/%m %H:%M", e.t)
			liste[#liste + 1] = Opus.Blanc(e.niveau) .. " " .. (e.approche and Opus.Gris(quand) or quand)
		end
		resume = resume .. "\n" .. table.concat(liste, Opus.Gris("  ·  ")) .. "\n" .. Opus.Gris("En gris : vu après coup, au retour de quelqu'un qui a l'addon.")
	end
	c.niveauxTitre:ClearAllPoints() c.niveauxTitre:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -y)
	c.niveaux:SetText(resume)
	c.niveauxBouton:SetShown(#montees > 1)
	c.niveauxBouton:SetText(tousNiveaux and "Replier" or ("Tous (" .. #montees .. ")"))
	y = y + 20 + H(c.niveaux) + 16

	-- les notes de l'addon (Notes.lua), sans limite de longueur : publique | officiers
	local function Texte (note)
		if not note then return Opus.Gris("Aucune note.") end
		return (note.x:gsub("|", "||")) .. "\n" .. Opus.Gris(("— %s, %s"):format(note.par or "?", date("%d/%m/%Y", note.t)))
	end
	local officier = Opus.PeutConfigurer()
	c.colPub.titre:ClearAllPoints() c.colPub.titre:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -y)
	local largeurCol = officier and math.floor((c.largeurNotes - 16) / 2) or c.largeurNotes
	local hPub = c.colPub.Placer(4, largeurCol, Texte(Opus.Note("p", fiche)))
	local hOff = officier and c.colOff.Placer(4 + largeurCol + 16, largeurCol, Texte(Opus.Note("o", fiche))) or 0
	c.colOff.titre:ClearAllPoints()
	c.colOff.titre:SetPoint("TOP", c.colPub.titre, "TOP")
	c.colOff.titre:SetPoint("LEFT", c, "LEFT", 4 + largeurCol + 16, 0)
	c.colPub.Montrer(true, m ~= nil and Opus.PeutNoter("p", fiche))
	c.colOff.Montrer(officier, m ~= nil and Opus.PeutNoter("o", fiche))

	-- son histoire : le journal de guilde où il apparaît
	local histoire = {}
	for _, e in ipairs(Opus.Evenements("tout")) do
		if e.a == fiche or e.b == fiche then
			histoire[#histoire + 1] = Opus.Gris(date("%d/%m", e.t * 3600)) .. "  " .. Opus.Phrase(e, nom)
			if #histoire >= 8 then break end
		end
	end
	c.histoire:SetText(#histoire > 0 and table.concat(histoire, "\n") or Opus.Gris("Rien au journal de guilde pour l'instant."))
	-- les boîtes des notes : à la taille du plus long texte, jusqu'à NOTES_MAX ; au-delà, on défile dedans
	local boite = math.min(math.max(hPub, hOff), NOTES_MAX)
	local nouvelle = c.pour ~= fiche
	c.pour = fiche
	c.colPub.Hauteur(hPub, boite, nouvelle)
	if officier then c.colOff.Hauteur(hOff, boite, nouvelle) end
	local hauteur = y + 20 + 6 + boite + 16 + 22 + H(c.histoire) + 8
	c:SetHeight(hauteur)
	return math.max(hauteur, 240)
end

------------------------------------------------------------------------
-- la page
------------------------------------------------------------------------

local function Rafraichir (cadre)
	cadre.vue:GenerateMenu()
	cadre.retour:SetShown(fiche ~= nil)
	cadre.vue:SetShown(fiche == nil)
	cadre.fiche:SetShown(fiche ~= nil)
	if fiche then
		for i = 1, LIGNES do lignes[i]:Hide() end
		cadre.ascenseur:Hide()
		cadre.vide:Hide()
		cadre.info:SetText("")
		return Fiche(cadre)
	end

	local journal = JOURNAL[vue]
	local elements = journal and Opus.Evenements(vue) or Elements()
	local membres = {}
	for _, m in ipairs(Opus.Membres()) do membres[m.nom] = m end
	local function Nom (n)
		local m = membres[n]
		return m and (Opus.Couleur(m.classe) .. n .. "|r") or Opus.Gris(n)
	end

	decalage = math.max(0, math.min(decalage, #elements - LIGNES))
	local enLigne, total = 0, 0
	for _, m in pairs(membres) do total = total + 1 if m.enLigne then enLigne = enLigne + 1 end end
	for i = 1, LIGNES do
		local l, e = lignes[i], elements[i + decalage]
		l:SetShown(e ~= nil)
		if e then
			l.e = e
			local membre = not journal and e.nom ~= nil
			for _, w in ipairs { l.icone, l.nom, l.joueur, l.grade, l.niveau, l.depuis, l.statut } do w:SetShown(membre) end
			l.titre:SetShown(not journal and e.titre ~= nil)
			l.quand:SetShown(journal) l.texte:SetShown(journal)
			if journal then
				l.quand:SetText(Opus.Depuis(e.t))
				l.texte:SetText(Opus.Phrase(e, Nom))
			elseif membre then
				LigneMembre(l, e)
			else
				l.titre:SetText(e.titre .. Opus.Gris("  " .. e.n))
			end
		end
	end
	local visibles = math.min(#elements, LIGNES)
	cadre.ascenseur:SetHeight(math.max(visibles, 1) * HAUTEUR)
	cadre.ascenseur:Recaler(decalage, #elements, LIGNES)
	cadre.vide:SetShown(#elements == 0)
	if journal then
		local plusAncien = elements[#elements]
		cadre.info:SetText(("%d événement(s)%s"):format(#elements, plusAncien and (" depuis le " .. date("%d/%m", plusAncien.t * 3600)) or ""))
	else
		cadre.info:SetText(("%d membres · %d en ligne"):format(total, enLigne))
	end
	return math.max(visibles, 1) * HAUTEUR
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	cadre.vue = Opus.Menu(barre, 220, VUES, function () return vue end, function (v) vue, decalage = v, 0 Opus.Rafraichir() end)
	cadre.vue:SetPoint("LEFT", 0, 0)
	cadre.retour = Opus.Bouton(barre, "Retour", 100, function () fiche = nil Opus.Rafraichir() end)
	cadre.retour:SetPoint("LEFT", 0, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	for i = 1, LIGNES do
		local l = CreateFrame("Button", nil, cadre)
		l:SetSize(largeur - 14, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -(i - 1) * HAUTEUR)
		Opus.Survol(l)
		local function Texte (police, x, w, align)
			local t = l:CreateFontString(nil, "OVERLAY", police)
			t:SetPoint("LEFT", x, 0) if w then t:SetWidth(w) end t:SetJustifyH(align or "LEFT") t:SetWordWrap(false)
			return t
		end
		l.titre = Texte("GameFontNormal", 2)
		l.icone = l:CreateTexture(nil, "ARTWORK")
		l.icone:SetSize(18, 18) l.icone:SetPoint("LEFT", 5, 0)
		l.nom = Texte("GameFontHighlight", 28, 140)
		l.joueur = Texte("GameFontHighlightSmall", 172, 110)
		l.grade = Texte("GameFontHighlightSmall", 286, 90)
		l.niveau = Texte("GameFontHighlightSmall", 378, 24, "RIGHT")
		l.depuis = Texte("GameFontHighlightSmall", 408, 62, "RIGHT")
		l.statut = Texte("GameFontHighlightSmall", 482, 192)
		l.quand = Texte("GameFontDisableSmall", 2, 52, "RIGHT")
		l.texte = Texte("GameFontHighlightSmall", 64)
		l.texte:SetPoint("RIGHT", -2, 0)
		l:SetScript("OnClick", function (self)
			local e = self.e
			local nom = e and (e.nom or (JOURNAL[vue] and (e.b or e.a)))
			if nom then fiche, tousNiveaux = nom, false Opus.Rafraichir() end
		end)
		Opus.Bulle(l, function (self)
			local e = self.e
			if not e or e.titre then return nil end
			if JOURNAL[vue] then return date("Vers le %d/%m/%Y, %H h", e.t * 3600) end
			return e.nom
		end, function (self)
			local e = self.e
			if not e or JOURNAL[vue] or e.titre then return nil end
			return { "Joueur : son pseudo Discord (" .. ETOILE .. " sur son main, +N : ses autres persos), d'après le dernier /opus import.",
				"Ancienneté : depuis l'arrivée relevée au journal de guilde ; en gris, arrivé avant le début du journal.",
				"Hors ligne : sa dernière connexion et la dernière zone connue.", Opus.Gris("Clic : ouvrir sa fiche.") }
		end)
		lignes[i] = l
	end
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) decalage = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", -2, 0)

	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", 4, -4)
	cadre.vide:SetText("Rien à afficher pour l'instant.")

	-- la fiche
	local f = CreateFrame("Frame", nil, cadre)
	f:SetPoint("TOPLEFT") f:SetPoint("TOPRIGHT") f:SetHeight(360)
	cadre.fiche = f
	f.icone = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.icone:SetPoint("TOPLEFT", 4, -4)
	f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.titre:SetPoint("TOPLEFT", 56, -6)
	f.sous = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.sous:SetPoint("TOPLEFT", f.titre, "BOTTOMLEFT", 0, -4)
	f.statut = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.statut:SetPoint("TOPRIGHT", -4, -8)
	f.infos = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.infos:SetPoint("TOPLEFT", 4, -60) f.infos:SetWidth(largeur - 8)
	f.infos:SetJustifyH("LEFT") f.infos:SetSpacing(4)
	-- ses persos : une ligne cliquable chacun
	f.persosTitre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.persosTitre:SetText("Ses persos")
	f.persos = {}
	for i = 1, PERSOS_MAX do
		local l = CreateFrame("Button", nil, f)
		l:SetSize(largeur - 14, 20)
		Opus.Survol(l)
		local function Texte (x, w, align)
			local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", x, 0) t:SetWidth(w) t:SetJustifyH(align or "LEFT") t:SetWordWrap(false)
			return t
		end
		l.icone = l:CreateTexture(nil, "ARTWORK")
		l.icone:SetSize(16, 16) l.icone:SetPoint("LEFT", 6, 0)
		l.texte = Texte(28, 250)
		l.niveau = Texte(282, 24, "RIGHT")
		l.grade = Texte(316, 110)
		l.statut = Texte(432, 242)
		l:SetScript("OnClick", function (self)
			if self.nom and self.nom ~= fiche then fiche = self.nom tousNiveaux = false Opus.Rafraichir() end
		end)
		f.persos[i] = l
	end
	-- ses niveaux : le résumé, et la liste complète en dépliant
	f.niveauxTitre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.niveauxTitre:SetText("Ses niveaux")
	f.niveauxBouton = Opus.Bouton(f, "Tous", 100, function () tousNiveaux = not tousNiveaux Opus.Rafraichir() end, true)
	f.niveauxBouton:SetPoint("TOP", f.niveauxTitre, "TOP", 0, 3)
	f.niveauxBouton:SetPoint("RIGHT", f, "LEFT", 4 + largeur - 8, 0)
	f.niveaux = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.niveaux:SetPoint("TOPLEFT", f.niveauxTitre, "BOTTOMLEFT", 0, -6) f.niveaux:SetWidth(largeur - 8)
	f.niveaux:SetJustifyH("LEFT") f.niveaux:SetSpacing(4)
	-- les notes : publique | officiers, côte à côte (la publique seule prend toute la largeur)
	f.colPub = ColonneNote(f, "Note publique", "p")
	f.colOff = ColonneNote(f, "Note d'officier", "o")
	f.colOff.titre:SetPoint("TOP", f.colPub.titre, "TOP")
	f.largeurNotes = largeur - 8
	local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOPLEFT", f.colPub.boite, "BOTTOMLEFT", 0, -16)
	h:SetText("Son histoire dans la guilde")
	f.histoire = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.histoire:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6) f.histoire:SetWidth(largeur - 8)
	f.histoire:SetJustifyH("LEFT") f.histoire:SetSpacing(4)
	f:Hide()
end

-- ouvrir la page sur une fiche ou une vue, depuis ailleurs (autres onglets, minimap, /opus journal)
function Opus.OuvrirGuilde (v, nom)
	if v then vue, decalage = v, 0 end
	fiche, tousNiveaux = nom, false
	Opus.db.page = "guilde"
	Opus.Fenetre(true)
end

Opus.Page("guilde", "Guilde", Construire, Rafraichir, function (_, d) if not fiche then decalage = decalage - d * 2 end end)
