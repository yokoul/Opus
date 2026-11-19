-- PageRegistre.lua : les vues « Prêts » et « Sorties » de l'onglet Banque (Registre.lua), et leur petit formulaire
local _, Opus = ...

local HAUTEUR = 20
local LIGNES_PRETS, LIGNES_REMISES, LIGNES_ATTENTE = 8, 12, 5
local decalagePrets, decalageRemises = 0, 0
local VIAS = { courrier = "courrier", echange = "échange", main = "en main propre", garde = "gardé" }

local function Date (t) return date("%d/%m/%y", t) end
local function Il (t) return Opus.Depuis(math.floor(t / 3600)) end

-- menu contextuel du client ; entrees = { { texte, f } } (un texte seul : un titre)
local function Contexte (owner, titre, entrees)
	if not MenuUtil or not MenuUtil.CreateContextMenu or #entrees == 0 then
		if entrees[1] and entrees[1][2] then entrees[1][2]() end
		return
	end
	MenuUtil.CreateContextMenu(owner, function (_, racine)
		racine:CreateTitle(titre)
		for _, e in ipairs(entrees) do
			if e[2] then racine:CreateButton(e[1], e[2]) else racine:CreateTitle(e[1]) end
		end
	end)
end

------------------------------------------------------------------------
-- formulaire : jusqu'à quatre champs, texte ou menu
------------------------------------------------------------------------

local f
local function ConstruireFormulaire ()
	f = CreateFrame("Frame", "OpusRegistre", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(440, 250) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OpusRegistre")
	local z = f.Inset
	f.lignes = {}
	for i = 1, 4 do
		local y = -14 - (i - 1) * 40
		local l = {}
		l.libelle = z:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		l.libelle:SetPoint("TOPLEFT", 14, y - 4)
		l.saisie = CreateFrame("EditBox", nil, z, "InputBoxTemplate")
		l.saisie:SetSize(260, 20) l.saisie:SetPoint("TOPLEFT", 136, y - 2)
		l.saisie:SetAutoFocus(false) l.saisie:SetMaxLetters(60)
		l.saisie:SetScript("OnEscapePressed", EditBox_ClearFocus) l.saisie:SetScript("OnEnterPressed", EditBox_ClearFocus)
		l.menu = CreateFrame("DropdownButton", nil, z, "WowStyle1DropdownTemplate")
		l.menu:SetWidth(270) l.menu:SetPoint("TOPLEFT", 130, y)
		l.menu:SetupMenu(function (_, racine)
			for _, c in ipairs(l.choix or {}) do
				racine:CreateRadio(c[2], function () return l.valeur == c[1] end, function () l.valeur = c[1] end)
			end
		end)
		l.aide = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.aide:SetPoint("TOPLEFT", 132, y - 24)
		f.lignes[i] = l
	end
	f.ok = Opus.Bouton(z, "Enregistrer", 130, function ()
		local v = {}
		for _, l in ipairs(f.lignes) do
			if l.cle then v[l.cle] = l.choix and l.valeur or strtrim(l.saisie:GetText() or "") end
		end
		if f.valider(v) ~= false then f:Hide() end
	end)
	f.ok:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
	f:Hide()
end

-- champs = { { cle, libellé, défaut, aide, choix } } ; valider(valeurs) renvoie false pour garder le formulaire ouvert
local function Formulaire (titre, champs, valider)
	if not f then ConstruireFormulaire() end
	f:SetTitle(titre)
	f.valider = valider
	local premier
	for i, l in ipairs(f.lignes) do
		local c = champs[i]
		l.cle, l.choix = c and c[1], c and c[5]
		l.libelle:SetShown(c ~= nil) l.aide:SetShown(c ~= nil)
		l.saisie:SetShown(c ~= nil and not l.choix) l.menu:SetShown(c ~= nil and l.choix ~= nil)
		if c then
			l.libelle:SetText(c[2]) l.aide:SetText(c[4] or "")
			if l.choix then l.valeur = c[3] or l.choix[1][1] l.menu:GenerateMenu()
			else l.saisie:SetText(c[3] or "") premier = premier or (c[3] == nil or c[3] == "") and l.saisie end
		end
	end
	f:SetHeight(110 + #champs * 40)
	f:Show()
	if premier then premier:SetFocus() end
end

local SENS = { { "g", "La guilde lui doit (il a avancé de l'or)" }, { "j", "Il doit à la guilde (elle lui a prêté)" } }

function Opus.FormulairePret ()
	Formulaire("Nouveau prêt", {
		{ "sens", "Sens", "g", nil, SENS },
		{ "qui", "Joueur", "", "Un de ses personnages ; le prénom suffit." },
		{ "or_", "Montant", "", "En po : « 83 », « 12,5 » ou « 12 po 50 pa »." },
		{ "motif", "Motif", "", "Ex. : premier onglet de la banque." },
	}, function (v)
		local c = Opus.LireOr(v.or_)
		if not c then Opus.Msg("montant illisible.") return false end
		if not Opus.NouveauPret(v.sens, v.qui, c, v.motif ~= "" and v.motif or nil) then return false end
	end)
end

local function FormulaireRemboursement (p)
	Formulaire("Remboursement : " .. p.r.qui, {
		{ "or_", "Montant", (("%g"):format(p.reste / 10000):gsub("%.", ",")), ("Reste %s ; en po."):format(Opus.OrDetail(p.reste)) },
		{ "note", "Note", "", "Ex. : par courrier, en main propre." },
	}, function (v)
		local c = Opus.LireOr(v.or_)
		if not c then Opus.Msg("montant illisible.") return false end
		Opus.Rembourser(p, c, v.note ~= "" and v.note or nil)
	end)
end

local function FormulaireRemise (a)
	Formulaire(("Sortie : %s"):format(a.e.o or "objet"), {
		{ "dest", "Remis à", "", "Le joueur, ou un autre de tes personnages." },
		{ "n", "Quantité", tostring(a.reste), ("Encore %d à remettre."):format(a.reste) },
		{ "via", "Comment", "main", nil, { { "main", "En main propre" }, { "courrier", "Par courrier" }, { "echange", "Par échange" } } },
	}, function (v)
		local n = tonumber(v.n)
		if not n or n < 1 then Opus.Msg("quantité illisible.") return false end
		if v.dest == "" then Opus.Msg("à qui ?") return false end
		Opus.Remettre(a, v.dest, n, v.via)
	end)
end

------------------------------------------------------------------------
-- la vue
------------------------------------------------------------------------

local function Ligne (parent, largeur, colonnes)
	local l = CreateFrame("Button", nil, parent)
	l:SetSize(largeur, HAUTEUR)
	l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Opus.Survol(l)
	l.cases = {}
	for c, col in ipairs(colonnes) do
		local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("LEFT", col[2], 0) t:SetWidth(col[3]) t:SetJustifyH(col[4] or "LEFT") t:SetWordWrap(false)
		l.cases[c] = t
	end
	return l
end

local function Entetes (parent, colonnes, y)
	for _, col in ipairs(colonnes) do
		local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		t:SetPoint("TOPLEFT", col[2], y) t:SetWidth(col[3]) t:SetJustifyH(col[4] or "LEFT")
		t:SetText(col[1])
	end
end

local COL_PRETS = {
	{ "Joueur", 2, 140 }, { "Sens", 146, 130 }, { "Prêté", 280, 74, "RIGHT" }, { "Rendu", 358, 74, "RIGHT" },
	{ "Reste", 436, 74, "RIGHT" }, { "Depuis", 514, 50, "RIGHT" }, { "Motif", 574, 110 },
}
local COL_REMISES = {
	{ "Date", 2, 60 }, { "De", 66, 130 }, { "À", 200, 130 }, { "Objet", 334, 230 }, { "Comment", 568, 110 },
}

local function BullePret (l)
	local p, lignes = l.p, {}
	if p.r.motif then lignes[#lignes + 1] = p.r.motif end
	lignes[#lignes + 1] = Opus.Gris(("noté par %s le %s%s"):format(p.r.par, Date(p.r.d), p.r.ev and " · relié à la banque" or ""))
	for i, r in ipairs(p.rembs) do
		if i > 10 then lignes[#lignes + 1] = Opus.Gris(("… et %d autre(s)"):format(#p.rembs - 10)) break end
		lignes[#lignes + 1] = ("%s · %s%s"):format(Date(r.d), Opus.OrDetail(r.c), Opus.Gris(" (" .. r.par .. (r.note and ", " .. r.note or "") .. ")"))
	end
	if #p.rembs == 0 then lignes[#lignes + 1] = Opus.Gris("Aucun remboursement.") end
	local props = Opus.Propositions(p)
	if #props > 0 and Opus.PeutConfigurer() then
		lignes[#lignes + 1] = " "
		lignes[#lignes + 1] = Opus.Vert(("%d opération(s) de la banque à confirmer : clic pour les voir."):format(#props))
	elseif Opus.PeutConfigurer() then
		lignes[#lignes + 1] = Opus.Gris("Clic : noter un remboursement, supprimer.")
	end
	return lignes
end

local function ClicPret (l)
	local p = l.p
	if not Opus.PeutConfigurer() then return end
	local entrees = {}
	for i, e in ipairs(Opus.Propositions(p)) do
		if i > 6 then break end
		entrees[#entrees + 1] = { ("Compter %s de %s (il y a %s)"):format(e.q == "or+" and "le dépôt" or "le retrait", Opus.OrDetail(e.c), Opus.Depuis(e.t)),
			function () Opus.Rembourser(p, e.c, nil, e) end }
	end
	if p.reste > 0 then entrees[#entrees + 1] = { "Noter un remboursement…", function () FormulaireRemboursement(p) end } end
	entrees[#entrees + 1] = { "Supprimer le prêt", function () Opus.Supprimer(p.r) end }
	Contexte(l, p.r.qui, entrees)
end

function Opus.ConstruireRegistre (parent, largeur)
	local v = CreateFrame("Frame", nil, parent)
	v:SetPoint("TOPLEFT") v:SetPoint("TOPRIGHT") v:SetHeight(1)

	-- prêts
	local p = CreateFrame("Frame", nil, v)
	p:SetPoint("TOPLEFT") p:SetPoint("TOPRIGHT") p:SetHeight(1)
	v.prets = p
	p.bilan = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	p.bilan:SetPoint("TOPLEFT", 2, -4)
	p.nouveau = Opus.Bouton(p, "Nouveau prêt", 120, Opus.FormulairePret)
	p.nouveau:SetPoint("TOPRIGHT", -2, 0)
	Entetes(p, COL_PRETS, -30)
	p.lignes = {}
	for i = 1, LIGNES_PRETS do
		local l = Ligne(p, largeur, COL_PRETS)
		l:SetPoint("TOPLEFT", 0, -46 - (i - 1) * HAUTEUR)
		Opus.Bulle(l, function (self) return self.p.r.qui end, BullePret)
		l:SetScript("OnClick", ClicPret)
		p.lignes[i] = l
	end
	p.ascenseur = Opus.Ascenseur(p, function (d) decalagePrets = d Opus.Rafraichir() end)
	p.ascenseur:SetPoint("TOPRIGHT", -2, -46)
	p.vide = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	p.vide:SetPoint("TOPLEFT", 4, -49)
	p.vide:SetText("Aucun prêt.")
	p.aide = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.aide:SetWidth(largeur - 4) p.aide:SetJustifyH("LEFT")
	p.aide:SetText("Visible de toute la guilde ; le chef et les officiers notent les prêts et leurs remboursements. L'addon propose "
		.. "comme remboursement les dépôts d'un débiteur, les retraits d'un créancier, et l'or qu'un officier lui envoie. "
		.. "Le dépôt qui fait un prêt à la guilde y est relié et ne compte pas comme cotisation.")

	-- remises
	local r = CreateFrame("Frame", nil, v)
	r:SetPoint("TOPLEFT") r:SetPoint("TOPRIGHT") r:SetHeight(1)
	v.remises = r
	r.titreAttente = Opus.Section(r)
	r.titreAttente:SetPoint("TOPLEFT", 2, -4)
	r.attente = {}
	for i = 1, LIGNES_ATTENTE do
		local l = CreateFrame("Frame", nil, r)
		l:SetSize(largeur, 24)
		l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.texte:SetPoint("LEFT", 8, 0) l.texte:SetWidth(largeur - 250) l.texte:SetJustifyH("LEFT") l.texte:SetWordWrap(false)
		l.garde = Opus.Bouton(l, "Gardé", 70, function (self) local a = self:GetParent().a Opus.Remettre(a, Opus.MonNom(), a.reste, "garde") end, true)
		l.garde:SetPoint("RIGHT", -4, 0)
		l.remis = Opus.Bouton(l, "Remis à…", 100, function (self) FormulaireRemise(self:GetParent().a) end, true)
		l.remis:SetPoint("RIGHT", l.garde, "LEFT", -6, 0)
		r.attente[i] = l
	end
	r.titre = Opus.Section(r)
	r.titre:SetText("Sorties d'objets")
	r.entetes = CreateFrame("Frame", nil, r)
	r.entetes:SetSize(largeur, 16)
	Entetes(r.entetes, COL_REMISES, 0)
	r.lignes = {}
	for i = 1, LIGNES_REMISES do
		local l = Ligne(r, largeur, COL_REMISES)
		Opus.Bulle(l, function (self) return self.x.o or "objet" end, function (self)
			local x = self.x
			return { ("%s → %s · %d"):format(x.de, x.a, x.n), Opus.Gris(("noté par %s, il y a %s"):format(x.par, Il(x.d))),
				(Opus.PeutConfigurer() or x.de == Opus.MonNom()) and Opus.Gris("Clic : supprimer.") or nil }
		end)
		l:SetScript("OnClick", function (self)
			if not Opus.PeutConfigurer() and self.x.de ~= Opus.MonNom() then return end
			Contexte(self, self.x.o or "objet", { { "Supprimer cette sortie", function () Opus.Supprimer(self.x) end } })
		end)
		r.lignes[i] = l
	end
	r.ascenseur = Opus.Ascenseur(r, function (d) decalageRemises = d Opus.Rafraichir() end)
	r.vide = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	r.vide:SetText("Aucune sortie notée.")
	r.aide = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.aide:SetWidth(largeur - 4) r.aide:SetJustifyH("LEFT")
	r.aide:SetText("Un objet retiré de la banque puis envoyé par courrier ou par échange est noté tout seul, à qui que ce soit, "
		.. "un autre de tes personnages compris. Pour un objet remis en main propre, ou que l'addon n'a pas vue : « Remis à… » ci-dessus. "
		.. "Visible de toute la guilde.")
	return v
end

local function RafraichirPrets (p, info)
	local prets = Opus.Prets()
	local doit, nDoit, du, nDu = Opus.BilanPrets()
	local morceaux = {}
	if nDoit > 0 then morceaux[#morceaux + 1] = ("La guilde doit %s à %d joueur(s)"):format(Opus.OrDetail(doit), nDoit) end
	if nDu > 0 then morceaux[#morceaux + 1] = ("on lui doit %s"):format(Opus.OrDetail(du)) end
	p.bilan:SetText(#morceaux > 0 and table.concat(morceaux, " · ") or Opus.Gris("Aucun prêt en cours."))
	info:SetText(("%d prêt(s) noté(s)"):format(#prets))
	p.nouveau:SetShown(Opus.PeutConfigurer())
	local officier = Opus.PeutConfigurer()
	decalagePrets = math.max(0, math.min(decalagePrets, #prets - LIGNES_PRETS))
	for i, l in ipairs(p.lignes) do
		local x = prets[i + decalagePrets]
		l:SetShown(x ~= nil)
		if x then
			l.p = x
			local m = Opus.TrouverMembre(x.r.qui)
			local nom = m and (Opus.Couleur(m.classe) .. x.r.qui .. "|r") or Opus.Gris(x.r.qui)
			local props = officier and x.reste > 0 and #Opus.Propositions(x) or 0
			l.cases[1]:SetText(nom .. (props > 0 and Opus.Vert("  (" .. props .. ")") or ""))
			l.cases[2]:SetText(x.r.sens == "g" and "la guilde lui doit" or "doit à la guilde")
			l.cases[3]:SetText(Opus.Or(x.r.c))
			l.cases[4]:SetText(Opus.Or(x.rendu))
			l.cases[5]:SetText(x.reste > 0 and Opus.Or(x.reste) or (Opus.Coche(12) .. " soldé"))
			l.cases[6]:SetText(Il(x.r.d))
			l.cases[7]:SetText(x.r.motif or "")
		end
	end
	local n = math.min(#prets, LIGNES_PRETS)
	p.ascenseur:SetHeight(math.max(n, 1) * HAUTEUR)
	p.ascenseur:Recaler(decalagePrets, #prets, LIGNES_PRETS)
	p.vide:SetShown(#prets == 0)
	local y = 46 + math.max(n, 1) * HAUTEUR + 10
	p.aide:SetPoint("TOPLEFT", 2, -y)
	local h = p.aide:GetStringHeight()
	return y + math.ceil(type(h) == "number" and h or 36) + 8
end

local function RafraichirRemises (r, info)
	local attente, remises = Opus.RetraitsEnAttente(), Opus.Remises()
	info:SetText(("%d sortie(s) notée(s)"):format(#remises))
	local y = 4
	r.titreAttente:SetShown(#attente > 0)
	if #attente > 0 then
		r.titreAttente:SetText(("Tes retraits à remettre (%d)"):format(#attente))
		y = y + 20
	end
	for i, l in ipairs(r.attente) do
		local a = attente[i]
		l:SetShown(a ~= nil)
		if a then
			l.a = a
			l.texte:SetText(("%d × %s%s"):format(a.reste, a.e.o or ("objet " .. tostring(a.e.id)),
				Opus.Gris(("  · retiré par %s il y a %s"):format(a.e.nom, Opus.Depuis(a.e.t)))))
			l:SetPoint("TOPLEFT", 0, -y)
			y = y + 24
		end
	end
	if #attente > 0 then y = y + 10 end
	r.titre:SetPoint("TOPLEFT", 2, -y)
	y = y + 22
	r.entetes:SetPoint("TOPLEFT", 0, -y)
	y = y + 16
	decalageRemises = math.max(0, math.min(decalageRemises, #remises - LIGNES_REMISES))
	for i, l in ipairs(r.lignes) do
		local x = remises[i + decalageRemises]
		l:SetShown(x ~= nil)
		if x then
			l.x = x
			l:SetPoint("TOPLEFT", 0, -y - (i - 1) * HAUTEUR)
			local function Nom (nom)
				local m = Opus.TrouverMembre(nom)
				return m and (Opus.Couleur(m.classe) .. nom .. "|r") or Opus.Gris(nom)
			end
			l.cases[1]:SetText(Date(x.d))
			l.cases[2]:SetText(Nom(x.de))
			l.cases[3]:SetText(x.via == "garde" and Opus.Gris("—") or Nom(x.a))
			l.cases[4]:SetText(x.n .. " × " .. (x.o or ("objet " .. tostring(x.id_))))
			l.cases[5]:SetText(VIAS[x.via] or x.via)
		end
	end
	local n = math.min(#remises, LIGNES_REMISES)
	r.ascenseur:ClearAllPoints()
	r.ascenseur:SetPoint("TOPRIGHT", -2, -y)
	r.ascenseur:SetHeight(math.max(n, 1) * HAUTEUR)
	r.ascenseur:Recaler(decalageRemises, #remises, LIGNES_REMISES)
	r.vide:SetShown(#remises == 0)
	r.vide:SetPoint("TOPLEFT", 4, -y - 3)
	y = y + math.max(n, 1) * HAUTEUR + 10
	r.aide:SetPoint("TOPLEFT", 2, -y)
	local h = r.aide:GetStringHeight()
	return y + math.ceil(type(h) == "number" and h or 36) + 8
end

-- vue = « prets » ou « remises » ; renvoie la hauteur utile
function Opus.RafraichirRegistre (v, vue, info)
	v.prets:SetShown(vue == "prets")
	v.remises:SetShown(vue == "remises")
	if vue == "prets" then return RafraichirPrets(v.prets, info) end
	return RafraichirRemises(v.remises, info)
end

function Opus.MoletteRegistre (vue, d)
	if vue == "prets" then decalagePrets = decalagePrets - d else decalageRemises = decalageRemises - d end
end
