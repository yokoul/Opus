-- PageGuilde.lua : le tableau de la guilde. Les membres regroupés par voie (et les essais à part), avec leur classe,
-- grade, niveau, ancienneté et participation à la banque ; un clic ouvre la fiche du membre (son histoire dans la guilde,
-- sa banque, ses notes). Le journal de guilde brut reste une des vues du menu.
local _, Opus = ...

local LIGNES, HAUTEUR = 16, 22
local lignes, decalage = {}, 0
local vue, fiche = "voies", nil         -- vue du menu ; fiche = nom du membre ouvert

local VUES = {
	{ "voies", "Membres par voie" }, { "enligne", "Membres en ligne" },
	{ "tout", "Journal : tout" }, { "mouvements", "Journal : arrivées et départs" }, { "grades", "Journal : grades" },
}
local JOURNAL = { tout = true, mouvements = true, grades = true }

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
	if m.absent then return Opus.Gris("vu il y a " .. Opus.Depuis(math.floor(time() / 3600) - m.absent)) end
	return Opus.Gris("hors ligne")
end

------------------------------------------------------------------------
-- la liste des membres
------------------------------------------------------------------------

local function Elements ()
	local banque = {}
	for _, p in ipairs(Opus.Participation(30)) do banque[p.nom] = p end
	local groupes, ordre = {}, {}
	for _, m in ipairs(Opus.Membres()) do
		if vue ~= "enligne" or m.enLigne then
			local g = Opus.GRADES[m.grade] or {}
			local cle = (g.essai or Opus.db.montees[m.nom]) and "essai" or (g.voie or "commun")
			if not groupes[cle] then groupes[cle] = { cle = cle, membres = {}, rang = 99 } ordre[#ordre + 1] = groupes[cle] end
			local gr = groupes[cle]
			gr.membres[#gr.membres + 1] = m
			gr.rang = math.min(gr.rang, m.grade)
			m.banque = banque[m.nom]
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
	l.grade:SetText(m.nomGrade)
	l.niveau:SetText(m.niveau)
	l.depuis:SetText(TexteAnciennete(Anciennete(m)))
	local b = m.banque
	l.banque:SetText(b and (b.orPlus > 0 or b.objPlus > 0) and
		((b.orPlus > 0 and Opus.Or(b.orPlus) or "") .. (b.objPlus > 0 and ((b.orPlus > 0 and " · " or "") .. b.objPlus .. " obj.") or "")) or Opus.Gris("–"))
	l.statut:SetText(Statut(m))
end

------------------------------------------------------------------------
-- la fiche d'un membre
------------------------------------------------------------------------

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
		-- son joueur : Discord (Lien.lua) et personnages vus sur le même compte
		local j = Opus.Discord(m.nom)
		local autres = {}
		for _, p in ipairs(Opus.PersosDuJoueur(m.nom)) do
			if p.nom ~= m.nom then autres[#autres + 1] = nom(p.nom) .. (p.main and " ⭐" or "") end
		end
		local _, _, main = Opus.Discord(m.nom)
		if j then
			infos[#infos + 1] = Opus.Normal("Discord : ") .. Opus.Blanc(j.pseudo) .. (main and Opus.Gris(" · son main ⭐") or Opus.Gris(" · reroll"))
		end
		if #autres > 0 then infos[#infos + 1] = Opus.Normal("Ses autres persos : ") .. table.concat(autres, ", ") end
		if m.note ~= "" then infos[#infos + 1] = Opus.Normal("Note du jeu : ") .. m.note end
		if m.noteOff ~= "" then infos[#infos + 1] = Opus.Normal("Note d'officier du jeu : ") .. m.noteOff end
	end
	-- sa banque : sur 30 jours et depuis le début
	local tout, mois
	for _, p in ipairs(Opus.Participation(nil)) do if p.nom == fiche then tout = p end end
	for _, p in ipairs(Opus.Participation(30)) do if p.nom == fiche then mois = p end end
	local function Bilan (p)
		if not p then return Opus.Gris("rien") end
		local morceaux = {}
		if p.orPlus > 0 then morceaux[#morceaux + 1] = Opus.Or(p.orPlus) .. " déposés" end
		if p.orMoins > 0 then morceaux[#morceaux + 1] = Opus.Or(p.orMoins) .. " retirés" end
		if p.rep > 0 then morceaux[#morceaux + 1] = Opus.Or(p.rep) .. " de réparations" end
		if p.objPlus > 0 then morceaux[#morceaux + 1] = p.objPlus .. " objets déposés" end
		if p.objMoins > 0 then morceaux[#morceaux + 1] = p.objMoins .. " retirés" end
		return #morceaux > 0 and table.concat(morceaux, " · ") or Opus.Gris("rien")
	end
	infos[#infos + 1] = Opus.Normal("Banque, 30 jours : ") .. Bilan(mois)
	infos[#infos + 1] = Opus.Normal("Banque, depuis le début : ") .. Bilan(tout)
	c.infos:SetText(table.concat(infos, "\n"))

	-- les notes de l'addon (Notes.lua), sans limite de longueur
	local notes = {}
	local function Texte (note) return (note.x:gsub("|", "||")) .. Opus.Gris(("  — %s, %s"):format(note.par or "?", date("%d/%m/%Y", note.t))) end
	local pub, off = Opus.Note("p", fiche), Opus.Note("o", fiche)
	if pub then notes[#notes + 1] = Opus.Normal("Publique : ") .. Texte(pub) end
	if off then notes[#notes + 1] = Opus.Normal("Officiers : ") .. Texte(off) end
	c.notes:SetText(#notes > 0 and table.concat(notes, "\n\n") or Opus.Gris("Aucune note."))
	c.notePub:SetShown(m ~= nil and Opus.PeutNoter("p", fiche))
	c.noteOff:SetShown(m ~= nil and Opus.PeutNoter("o", fiche))

	-- son histoire : le journal de guilde où il apparaît
	local histoire = {}
	for _, e in ipairs(Opus.Evenements("tout")) do
		if e.a == fiche or e.b == fiche then
			histoire[#histoire + 1] = Opus.Gris(date("%d/%m", e.t * 3600)) .. "  " .. Opus.Phrase(e, nom)
			if #histoire >= 8 then break end
		end
	end
	c.histoire:SetText(#histoire > 0 and table.concat(histoire, "\n") or Opus.Gris("Rien au journal de guilde pour l'instant."))
	local function H (t) local h = t:GetStringHeight() return type(h) == "number" and h or 14 end
	local hauteur = 60 + H(c.infos) + 16 + 20 + 6 + H(c.notes) + 16 + 22 + H(c.histoire) + 8
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
			for _, w in ipairs { l.icone, l.nom, l.grade, l.niveau, l.depuis, l.banque, l.statut } do w:SetShown(membre) end
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
		l.nom = Texte("GameFontHighlight", 28, 150)
		l.grade = Texte("GameFontHighlightSmall", 182, 90)
		l.niveau = Texte("GameFontHighlightSmall", 274, 26, "RIGHT")
		l.depuis = Texte("GameFontHighlightSmall", 310, 70, "RIGHT")
		l.banque = Texte("GameFontHighlightSmall", 390, 110, "RIGHT")
		l.statut = Texte("GameFontHighlightSmall", 512, 160)
		l.quand = Texte("GameFontDisableSmall", 2, 52, "RIGHT")
		l.texte = Texte("GameFontHighlightSmall", 64)
		l.texte:SetPoint("RIGHT", -2, 0)
		l:SetScript("OnClick", function (self)
			local e = self.e
			local nom = e and (e.nom or (JOURNAL[vue] and (e.b or e.a)))
			if nom then fiche = nom Opus.Rafraichir() end
		end)
		Opus.Bulle(l, function (self)
			local e = self.e
			if not e or e.titre then return nil end
			if JOURNAL[vue] then return date("Vers le %d/%m/%Y, %H h", e.t * 3600) end
			return e.nom
		end, function (self)
			local e = self.e
			if not e or JOURNAL[vue] or e.titre then return nil end
			return { "Ancienneté : depuis l'arrivée relevée au journal de guilde ; en gris, arrivé avant le début du journal.",
				"Banque : dépôts des 30 derniers jours.", Opus.Gris("Clic : ouvrir sa fiche.") }
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
	local n = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	n:SetPoint("TOPLEFT", f.infos, "BOTTOMLEFT", 0, -16)
	n:SetText("Notes")
	f.noteOff = Opus.Bouton(f, "Note d'officier", 120, function () Opus.EditerNote("o", fiche) end, true)
	f.noteOff:SetPoint("RIGHT", f, "RIGHT", -4, 0) f.noteOff:SetPoint("TOP", n, "TOP", 0, 3)
	f.notePub = Opus.Bouton(f, "Note publique", 120, function () Opus.EditerNote("p", fiche) end, true)
	f.notePub:SetPoint("RIGHT", f.noteOff, "LEFT", -6, 0)
	f.notes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.notes:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -6) f.notes:SetWidth(largeur - 8)
	f.notes:SetJustifyH("LEFT") f.notes:SetSpacing(3)
	local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOPLEFT", f.notes, "BOTTOMLEFT", 0, -16)
	h:SetText("Son histoire dans la guilde")
	f.histoire = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.histoire:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6) f.histoire:SetWidth(largeur - 8)
	f.histoire:SetJustifyH("LEFT") f.histoire:SetSpacing(4)
	f:Hide()
end

-- ouvrir la page sur une fiche ou une vue, depuis ailleurs (autres onglets, minimap, /opus journal)
function Opus.OuvrirGuilde (v, nom)
	if v then vue, decalage = v, 0 end
	fiche = nom
	Opus.db.page = "guilde"
	Opus.Fenetre(true)
end

Opus.Page("guilde", "Guilde", Construire, Rafraichir, function (_, d) if not fiche then decalage = decalage - d * 2 end end)
