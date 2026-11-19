-- EnviesVue.lua : les envies de donjon à l'écran. La vue de l'onglet Groupe (tous les donjons demandés, grisés hors de son
-- niveau, avec qui les veut, pourquoi et quand) et le formulaire « J'ai besoin d'un donjon ».
local _, Opus = ...

local LIGNES, HAUTEUR = 16, 24
local ATLAS_ROLES = { tank = "roleicon-tiny-tank", soin = "roleicon-tiny-healer", degats = "roleicon-tiny-dps" }
local NOMS_ROLES = { tank = "tank", soin = "soigneur", degats = "dégâts" }

local function IconesRoles (texte)
	local icones = {}
	for _, r in ipairs(Opus.ListeRoles(texte)) do icones[#icones + 1] = CreateAtlasMarkup(ATLAS_ROLES[r], 13, 13) end
	return table.concat(icones, "")
end

-- un donjon à sa portée : de 5 niveaux sous son minimum à 2 au-dessus de son maximum (comme le panneau de groupe)
local function APortee (d)
	local n = UnitLevel("player")
	return not d.min or (n >= d.min - 5 and n <= d.max + 2)
end

local function Chuchoter (nom)
	local seul = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
	if not seul then return end
	if securecall then securecall(seul, nom) else seul(nom) end
end

------------------------------------------------------------------------
-- le formulaire
------------------------------------------------------------------------

local f, saisie

local function Choisis ()
	local noms = {}
	for _, cle in ipairs(saisie.donjons) do noms[#noms + 1] = Opus.DonjonDe(cle).nom end
	return #noms > 0 and table.concat(noms, ", ") or "Choisis jusqu'à 3 donjons"
end

local function ConstruireFormulaire ()
	f = CreateFrame("Frame", "OpusEnvie", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(460, 360) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("J'ai besoin d'un donjon")
	tinsert(UISpecialFrames, "OpusEnvie")
	local z = f.Inset
	local y = -12
	local function Libelle (texte)
		local t = z:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOPLEFT", 14, y - 4) t:SetText(texte)
		return t
	end
	local X = 130

	Libelle("Donjons")
	f.donjons = CreateFrame("DropdownButton", nil, z, "WowStyle1DropdownTemplate")
	f.donjons:SetWidth(300) f.donjons:SetPoint("TOPLEFT", X, y)
	f.donjons:SetupMenu(function (_, racine)
		for _, d in ipairs(Opus.TousLesDonjons()) do
			local texte = ("%s  (%d-%d)"):format(d.nom, d.min, d.max)
			local function Pris ()
				for _, cle in ipairs(saisie.donjons) do if cle == d.cle then return true end end
				return false
			end
			racine:CreateCheckbox(APortee(d) and texte or Opus.Gris(texte), Pris, function ()
				for i, cle in ipairs(saisie.donjons) do if cle == d.cle then table.remove(saisie.donjons, i) f.donjons:OverrideText(Choisis()) return end end
				if #saisie.donjons < 3 then table.insert(saisie.donjons, d.cle) end
				f.donjons:OverrideText(Choisis())
			end)
		end
	end)
	y = y - 34

	Libelle("Pour")
	f.pourquoi = {}
	for i, p in ipairs(Opus.POURQUOI) do
		local c = CreateFrame("CheckButton", nil, z, "UICheckButtonTemplate")
		c:SetSize(24, 24) c:SetPoint("TOPLEFT", X - 4 + (i - 1) * 100, y)
		local t = c.Text or c.text
		if t then t:SetText(p[2]) t:SetFontObject("GameFontHighlightSmall") end
		c:SetScript("OnClick", function (self) saisie.pourquoi[p[1]] = self:GetChecked() or nil end)
		f.pourquoi[p[1]] = c
	end
	y = y - 32

	local function Champ (largeur, max, aide)
		local s = CreateFrame("EditBox", nil, z, "InputBoxTemplate")
		s:SetSize(largeur, 20) s:SetPoint("TOPLEFT", X + 6, y - 2)
		s:SetAutoFocus(false) s:SetMaxLetters(max)
		s:SetScript("OnEscapePressed", EditBox_ClearFocus) s:SetScript("OnEnterPressed", EditBox_ClearFocus)
		if aide then
			local a = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			a:SetPoint("TOPLEFT", s, "BOTTOMLEFT", -4, -3) a:SetText(aide)
		end
		return s
	end
	Libelle("Note")
	f.note = Champ(290, 60, "Ex. : la quête de la Confrérie, le bâton du dernier boss.")
	y = y - 46

	Libelle("Disponible")
	f.creneau = Opus.Menu(z, 160, Opus.CRENEAUX, function () return saisie.creneau end, function (v)
		saisie.creneau = v
		if not saisie.dureeChoisie then saisie.duree = Opus.DureePourCreneau(v) f.duree:GenerateMenu() end
		if v == "autre" then f.precision:SetFocus() end
	end)
	f.creneau:SetPoint("TOPLEFT", X, y)
	y = y - 30
	f.precision = Champ(290, 40, "Précision libre : « demain 21 h », « après 22 h »…")
	y = y - 46

	Libelle("Afficher")
	f.duree = Opus.Menu(z, 160, Opus.DUREES_ENVIE, function () return saisie.duree end, function (v) saisie.duree, saisie.dureeChoisie = v, true end)
	f.duree:SetPoint("TOPLEFT", X, y)
	y = y - 34

	f.roles = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.roles:SetPoint("TOPLEFT", 14, y - 4) f.roles:SetWidth(420) f.roles:SetJustifyH("LEFT")

	local publier = Opus.Bouton(z, "Publier", 130, function ()
		if #saisie.donjons == 0 then Opus.Msg("choisis au moins un donjon.") return end
		saisie.note = strtrim(f.note:GetText() or "")
		saisie.precision = strtrim(f.precision:GetText() or "")
		Opus.PublierEnvie(saisie)
		f:Hide()
	end)
	publier:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", publier, "LEFT", -8, 0)
	f:Hide()
end

-- ouvre le formulaire ; avec un donjon déjà choisi (« Moi aussi » → autre créneau)
function Opus.EditerEnvie (cle, creneau)
	if not f then ConstruireFormulaire() end
	saisie = { donjons = cle and { cle } or {}, pourquoi = {}, creneau = creneau or "maintenant", suite = cle ~= nil or nil }
	saisie.duree = Opus.DureePourCreneau(saisie.creneau)
	for _, c in pairs(f.pourquoi) do c:SetChecked(false) end
	f.note:SetText("") f.precision:SetText("")
	f.donjons:OverrideText(Choisis())
	f.creneau:GenerateMenu() f.duree:GenerateMenu()
	local roles = {}
	for _, r in ipairs(Opus.ListeRoles(Opus.MesRoles())) do roles[#roles + 1] = NOMS_ROLES[r] end
	f.roles:SetText(Opus.Normal("Tes rôles : ") .. (#roles > 0 and table.concat(roles, ", ") or Opus.Gris("inconnus"))
		.. Opus.Gris("  · à régler dans l'onglet Réglages"))
	f:Show()
	if creneau == "autre" then f.precision:SetFocus() end
end

------------------------------------------------------------------------
-- la vue de l'onglet Groupe
------------------------------------------------------------------------

-- les lignes : pour chaque donjon demandé, un en-tête puis une ligne par envie ; ceux à sa portée d'abord
local function Elements ()
	local parDonjon, ordre = {}, {}
	for _, e in ipairs(Opus.Envies()) do
		for _, cle in ipairs(e.donjons) do
			if not parDonjon[cle] then parDonjon[cle] = { d = Opus.DonjonDe(cle), envies = {} } ordre[#ordre + 1] = parDonjon[cle] end
			table.insert(parDonjon[cle].envies, e)
		end
	end
	table.sort(ordre, function (a, b)
		local x, y = APortee(a.d), APortee(b.d)
		if x ~= y then return x end
		if #a.envies ~= #b.envies then return #a.envies > #b.envies end
		return (a.d.min or 99) < (b.d.min or 99)
	end)
	local elements = {}
	for _, g in ipairs(ordre) do
		local dispo, places = Opus.CompositionPossible(g.d.cle)
		elements[#elements + 1] = { donjon = g.d, n = #g.envies, dispo = #dispo, places = places }
		for _, e in ipairs(g.envies) do elements[#elements + 1] = { envie = e, donjon = g.d } end
	end
	return elements
end

local NOMS = { tank = "tank", soin = "soigneur", degats = "dégâts" }
local function Manque (places)
	local manque = {}
	for i, r in ipairs(Opus.PLACES) do if not places[i] then manque[r] = (manque[r] or 0) + 1 end end
	local morceaux = {}
	for _, r in ipairs { "tank", "soin", "degats" } do if manque[r] then morceaux[#morceaux + 1] = manque[r] .. " " .. NOMS[r] end end
	return table.concat(morceaux, ", ")
end

function Opus.VueEnvies (parent, largeur)
	local v = CreateFrame("Frame", nil, parent)
	v:SetPoint("TOPLEFT") v:SetPoint("TOPRIGHT")
	local decalage = 0

	local nouveau = Opus.Bouton(v, "J'ai besoin d'un donjon…", 200, function () Opus.EditerEnvie() end)
	nouveau:SetPoint("TOPLEFT", 0, 0)
	v.annoncer = Opus.BoutonSecurise(v, 170, function ()
		GameTooltip:SetText("Annoncer en guilde")
		GameTooltip:AddLine("Pour les membres sans l'addon : ta dernière envie dans la discussion de guilde.", 1, 1, 1, true)
	end)
	v.annoncer:SetText("Annoncer en /g")
	v.annoncer:SetPoint("LEFT", nouveau, "RIGHT", 8, 0)
	v.info = v:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	v.info:SetPoint("TOPRIGHT", -4, -6)

	v.lignes = {}
	for i = 1, LIGNES do
		local l = CreateFrame("Button", nil, v)
		l:SetSize(largeur - 14, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -32 - (i - 1) * HAUTEUR)
		Opus.Survol(l)
		local function Texte (police, x, w, align)
			local t = l:CreateFontString(nil, "OVERLAY", police)
			t:SetPoint("LEFT", x, 0) if w then t:SetWidth(w) end t:SetJustifyH(align or "LEFT") t:SetWordWrap(false)
			return t
		end
		-- en-tête d'un donjon
		l.titre = Texte("GameFontNormal", 4, 300)
		l.resume = Texte("GameFontHighlightSmall", 310, 200)
		l.moiAussi = CreateFrame("DropdownButton", nil, l, "WowStyle1DropdownTemplate")
		l.moiAussi:SetWidth(110) l.moiAussi:SetPoint("RIGHT", -88, 0)
		l.moiAussi:SetDefaultText("Moi aussi")
		l.moiAussi:SetupMenu(function (_, racine)
			for _, c in ipairs(Opus.CRENEAUX) do
				racine:CreateButton(c[2], function ()
					local cle = l.element and l.element.donjon.cle
					if not cle then return end
					if c[1] == "autre" then Opus.EditerEnvie(cle, "autre") return end
					Opus.PublierEnvie({ donjons = { cle }, pourquoi = {}, creneau = c[1], duree = Opus.DureePourCreneau(c[1]), suite = true })
				end)
			end
		end)
		l.former = Opus.Bouton(l, "Former", 80, function () if l.element then Opus.FormerDepuisEnvie(l.element.donjon.cle) end end, true)
		l.former:SetPoint("RIGHT", -2, 0)
		Opus.Bulle(l.former, "Former le groupe", "Remplit le panneau de groupe avec ceux qui sont disponibles maintenant et en ligne.")
		-- une envie
		l.icone = l:CreateTexture(nil, "ARTWORK")
		l.icone:SetSize(16, 16) l.icone:SetPoint("LEFT", 18, 0)
		l.nom = Texte("GameFontHighlightSmall", 40, 140)
		l.roles = Texte("GameFontHighlightSmall", 182, 44)
		l.quand = Texte("GameFontHighlightSmall", 228, 150)
		l.quoi = Texte("GameFontHighlightSmall", 382, 210)
		l.action = Opus.Bouton(l, "Écrire", 70, function ()
			local e = l.element and l.element.envie
			if not e then return end
			if e.par == Opus.MonNom() then Opus.RetirerEnvie(e.id) else Chuchoter(e.par) end
		end, true)
		l.action:SetPoint("RIGHT", -2, 0)
		Opus.Bulle(l, function (self)
			local e = self.element and self.element.envie
			return e and e.par
		end, function (self)
			local e = self.element and self.element.envie
			if not e then return nil end
			local lignes = {}
			if e.note then lignes[#lignes + 1] = e.note end
			lignes[#lignes + 1] = Opus.Gris("Publiée le " .. date("%d/%m à %H h %M", e.m) .. ", affichée jusqu'au " .. date("%d/%m à %H h", e.fin) .. ".")
			return lignes
		end)
		v.lignes[i] = l
	end
	v.vide = v:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	v.vide:SetPoint("TOPLEFT", 4, -38) v.vide:SetWidth(largeur - 20) v.vide:SetJustifyH("LEFT")
	v.vide:SetText("Aucune envie de donjon pour l'instant. Tu dois faire un donjon pour une quête ou un objet ? Annonce-le : la guilde est prévenue, et chacun peut dire quand il est disponible.")

	function v.Defiler (d) decalage = math.max(0, decalage - d * 2) end

	function v.Rafraichir ()
		local elements = Elements()
		local moi = Opus.MonNom()
		decalage = math.max(0, math.min(decalage, #elements - LIGNES))
		local joueurs, n = {}, 0
		for _, e in ipairs(Opus.Envies()) do if not joueurs[e.par] then joueurs[e.par] = true n = n + 1 end end
		v.info:SetText(("%d envie(s) · %d joueur(s)"):format(#Opus.Envies(), n))
		for i, l in ipairs(v.lignes) do
			local x = elements[i + decalage]
			l.element = x
			l:SetShown(x ~= nil)
			if x then
				local entete = x.envie == nil
				for _, w in ipairs { l.titre, l.resume, l.moiAussi, l.former } do w:SetShown(entete) end
				for _, w in ipairs { l.icone, l.nom, l.roles, l.quand, l.quoi, l.action } do w:SetShown(not entete) end
				if entete then
					local d = x.donjon
					local titre = d.nom .. (d.min and ("  (%d-%d)"):format(d.min, d.max) or "")
					l.titre:SetText(APortee(d) and titre or Opus.Gris(titre))
					local manque = Manque(x.places)
					l.resume:SetText(Opus.Gris(x.n .. " envie(s)") .. (x.dispo > 0 and (Opus.Gris(" · ") .. Opus.Vert(x.dispo .. " dispo")) or "")
						.. (x.dispo > 0 and (manque == "" and Opus.Vert(" · complet !") or Opus.Gris(" · manque " .. manque)) or ""))
					l.former:SetEnabled(x.dispo >= 2)
				else
					local e = x.envie
					local m = Opus.TrouverMembre(e.par)
					local classe = Opus.db.classes[e.par] or (m and m.classe)
					local atlas = classe and GetClassAtlas and GetClassAtlas(classe:lower())
					if atlas then l.icone:SetAtlas(atlas) end
					l.icone:SetShown(atlas ~= nil)
					local nom = (classe and Opus.Couleur(classe) or "") .. e.par .. "|r" .. (m and m.niveau and Opus.Gris(" " .. m.niveau) or "")
					l.nom:SetText((m and m.enLigne) and nom or (nom .. Opus.Gris(" ·")))
					l.roles:SetText(IconesRoles(e.roles))
					l.quand:SetText(Opus.TexteCreneau(e))
					local quoi = Opus.TextePourquoi(e)
					l.quoi:SetText((quoi ~= "" and quoi or "") .. (e.note and Opus.Gris((quoi ~= "" and " · " or "") .. e.note) or ""))
					l.action:SetText(e.par == moi and "Retirer" or "Écrire")
				end
			end
		end
		-- l'annonce en guilde : sa dernière envie
		local mienne
		for _, e in ipairs(Opus.Envies()) do if e.par == moi then mienne = e break end end
		local texte = ""
		if mienne then
			local noms = {}
			for _, cle in ipairs(mienne.donjons) do noms[#noms + 1] = Opus.DonjonDe(cle).nom end
			local quoi = Opus.TextePourquoi(mienne)
			local quand = Opus.TexteCreneau(mienne):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			texte = ("/g [Opus] Je cherche du monde pour %s%s, %s : chuchotez-moi !"):format(table.concat(noms, ", "),
				quoi ~= "" and (" (" .. quoi .. ")") or "", quand)
		end
		v.annoncer:SetAttribute("macrotext", texte:sub(1, 255))
		v.annoncer:SetEnabled(texte ~= "")
		v.vide:SetShown(#elements == 0)
		local visibles = math.min(#elements, LIGNES)
		local hauteur = 32 + math.max(visibles * HAUTEUR, #elements == 0 and 60 or 0) + 8
		v:SetHeight(hauteur)
		return hauteur
	end
	return v
end
