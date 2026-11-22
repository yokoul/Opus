-- EnviesVue.lua : les envies de donjon à l'écran. Une carte par donjon demandé (comme la recherche de groupe du jeu) :
-- sa tranche de niveaux face au sien, les places du groupe déjà couvertes par ceux qui sont disponibles maintenant, et
-- qui le veut, quand et pourquoi ; l'onglet Groupe les assemble (PageGroupe.lua). Et le formulaire « J'ai besoin d'un
-- donjon ».
local _, Opus = ...

local JOUEURS_MAX, JOUEUR_H = 6, 18
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
	f:SetSize(460, 430) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
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

	-- le PL : un grand peut venir booster le groupe (les monstres gris ne rapportent plus d'XP)
	Libelle("Booster")
	f.pl = CreateFrame("CheckButton", nil, z, "UICheckButtonTemplate")
	f.pl:SetSize(24, 24) f.pl:SetPoint("TOPLEFT", X - 4, y)
	local tpl = f.pl.Text or f.pl.text
	if tpl then tpl:SetText("PL accepté : un 60 (ou un grand) peut venir nous booster") tpl:SetFontObject("GameFontHighlightSmall") end
	Opus.Bulle(f.pl, "PL accepté", "Le groupe veut bien d'un ou deux grands personnages pour faire le donjon vite. Avec eux, les monstres "
		.. "sont gris : plus personne ne gagne d'XP en les tuant (les quêtes et les objets restent).")
	f.pl:SetScript("OnClick", function (self) saisie.pl = self:GetChecked() or nil end)
	y = y - 30

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

	-- le rôle (ou les rôles) avec lequel on vient : ceux qu'on sait jouer, tous cochés par défaut
	Libelle("Je viens en")
	f.casesRoles = {}
	f.casesRoles.ancre = CreateFrame("Frame", nil, z)
	f.casesRoles.ancre:SetSize(1, 1) f.casesRoles.ancre:SetPoint("TOPLEFT", X - 4, y)
	for i, r in ipairs { "tank", "soin", "degats" } do
		local c = CreateFrame("CheckButton", nil, z, "UICheckButtonTemplate")
		c:SetSize(24, 24) c:SetPoint("TOPLEFT", X - 4 + (i - 1) * 100, y)
		local t = c.Text or c.text
		if t then t:SetText(CreateAtlasMarkup(ATLAS_ROLES[r], 14, 14) .. " " .. (r == "tank" and "Tank" or r == "soin" and "Soigneur" or "Dégâts")) t:SetFontObject("GameFontHighlightSmall") end
		c:SetScript("OnClick", function (self)
			-- au moins un rôle reste coché
			local un = false
			for _, k in ipairs { "tank", "soin", "degats" } do if f.casesRoles[k]:GetChecked() then un = true end end
			if not un then self:SetChecked(true) end
		end)
		f.casesRoles[r] = c
	end
	y = y - 30
	f.roles = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.roles:SetPoint("TOPLEFT", 14, y - 4) f.roles:SetWidth(420) f.roles:SetJustifyH("LEFT")

	local publier = Opus.Bouton(z, "Publier", 130, function ()
		if #saisie.donjons == 0 then Opus.Msg("choisis au moins un donjon.") return end
		saisie.note = strtrim(f.note:GetText() or "")
		saisie.precision = strtrim(f.precision:GetText() or "")
		local roles = {}
		for _, r in ipairs { "tank", "soin", "degats" } do if f.casesRoles[r]:IsShown() and f.casesRoles[r]:GetChecked() then roles[#roles + 1] = r end end
		saisie.roles = #roles > 0 and table.concat(roles, ",") or nil
		Opus.PublierEnvie(saisie)
		f:Hide()
	end)
	publier:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", publier, "LEFT", -8, 0)
	f:Hide()
end

-- ouvre le formulaire ; avec un donjon déjà choisi (celui choisi pour « En ligne à ta portée », ou « Moi aussi » → autre créneau : suite)
function Opus.EditerEnvie (cle, creneau, suite)
	if not f then ConstruireFormulaire() end
	saisie = { donjons = cle and { cle } or {}, pourquoi = {}, creneau = creneau or "maintenant", suite = suite or nil }
	saisie.duree = Opus.DureePourCreneau(saisie.creneau)
	for _, c in pairs(f.pourquoi) do c:SetChecked(false) end
	f.pl:SetChecked(false)
	f.note:SetText("") f.precision:SetText("")
	f.donjons:OverrideText(Choisis())
	f.creneau:GenerateMenu() f.duree:GenerateMenu()
	-- les rôles qu'on sait jouer (onglet Réglages), tous cochés ; sans rôle connu, les trois
	local mesRoles = Opus.ListeRoles(Opus.MesRoles())
	local connus = {}
	for _, r in ipairs(mesRoles) do connus[r] = true end
	local x = 0
	for _, r in ipairs { "tank", "soin", "degats" } do
		local c = f.casesRoles[r]
		local montrer = #mesRoles == 0 or connus[r]
		c:SetShown(montrer) c:SetChecked(montrer)
		if montrer then c:ClearAllPoints() c:SetPoint("TOPLEFT", f.casesRoles.ancre, "TOPLEFT", x, 0) x = x + 100 end
	end
	f.roles:SetText(#mesRoles > 1 and "Décoche pour ne venir que dans un rôle. Tes rôles se règlent dans l'onglet Réglages."
		or "Tes rôles se règlent dans l'onglet Réglages (plusieurs possibles).")
	f:Show()
	if creneau == "autre" then f.precision:SetFocus() end
end

------------------------------------------------------------------------
-- la vue de l'onglet Groupe : une carte par donjon
------------------------------------------------------------------------

-- les donjons demandés, ceux à sa portée d'abord, puis les plus demandés
local function Donjons ()
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
	for _, g in ipairs(ordre) do
		-- les disponibles maintenant d'abord ; une seule ligne par joueur, la plus utile
		table.sort(g.envies, function (a, b)
			local x, y = Opus.DispoMaintenant(a), Opus.DispoMaintenant(b)
			if x ~= y then return x end
			return a.m > b.m
		end)
		local vus, uniques = {}, {}
		for _, e in ipairs(g.envies) do
			if not vus[e.par] then vus[e.par] = true uniques[#uniques + 1] = e end
		end
		g.envies = uniques
		g.dispo, g.places = Opus.CompositionPossible(g.d.cle)
		g.interesses, g.prevues = Opus.CompositionPossible(g.d.cle, true)
	end
	return ordre
end

-- les places du groupe, comme la recherche de groupe du jeu : pleines si quelqu'un de disponible la tient
local ATLAS_PLACES = { tank = "groupfinder-icon-role-large-tank", soin = "groupfinder-icon-role-large-heal", degats = "groupfinder-icon-role-large-dps" }
local function Atlas (texture, atlas, repli)
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then atlas = repli end
	texture:SetAtlas(atlas)
end

-- la barre de niveaux : la tranche du donjon sur une échelle autour d'elle, et un repère à son niveau (comme la portée
-- d'une recette de métier)
function Opus.CreerBarre (parent, largeur)
	local c = {}
	c.barre = parent:CreateTexture(nil, "ARTWORK")
	c.barre:SetColorTexture(0.15, 0.13, 0.1, 0.9)
	c.barre:SetSize(largeur or 220, 6)
	c.plage = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	c.moi = parent:CreateTexture(nil, "OVERLAY")
	c.moi:SetColorTexture(1, 1, 1, 1) c.moi:SetWidth(2)
	c.moiTexte = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.min = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.max = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	function c.Montrer (oui)
		for _, w in ipairs { c.barre, c.plage, c.moi, c.moiTexte, c.min, c.max } do w:SetShown(oui) end
		if c.gris and not oui then c.gris:Hide() end
	end
	return c
end

-- joueurs : les autres niveaux à situer (son groupe, ou les intéressés), { niveau } ; la zone rouge commence au niveau où
-- les monstres du donjon deviennent gris (Opus.ECART_GRIS au-dessus de son maximum) : un seul joueur au-delà, et plus
-- personne du groupe ne gagne d'XP sur ses victimes
function Opus.PlacerBarre (c, d, joueurs)
	if not d or not d.min then c.Montrer(false) for _, r in ipairs(c.reperes or {}) do r:Hide() end return end
	c.Montrer(true)
	local n = UnitLevel("player")
	local plusHaut, plusBas = n, n
	for _, j in ipairs(joueurs or {}) do plusHaut, plusBas = math.max(plusHaut, j.niveau), math.min(plusBas, j.niveau) end
	local seuil = d.max + Opus.ECART_GRIS
	local bas, haut = math.max(1, math.min(d.min, plusBas) - 4), math.min(60, math.max(d.max, plusHaut) + 4)
	if haut - bas < 12 then haut = math.min(60, bas + 12) bas = math.max(1, haut - 12) end
	local w = c.barre:GetWidth()
	w = type(w) == "number" and w > 0 and w or 200
	local function X (niveau) return (math.max(bas, math.min(haut, niveau)) - bas) / (haut - bas) * w end
	c.plage:ClearAllPoints()
	c.plage:SetPoint("TOPLEFT", c.barre, "TOPLEFT", X(d.min), 0)
	c.plage:SetPoint("BOTTOMLEFT", c.barre, "BOTTOMLEFT", X(d.min), 0)
	c.plage:SetWidth(math.max(2, X(d.max) - X(d.min)))
	-- vert : dans la tranche ; jaune : à portée ; gris : trop loin (un reroll peut y aller)
	local dedans, proche = n >= d.min and n <= d.max, APortee(d)
	if dedans then c.plage:SetColorTexture(0.25, 0.75, 0.25, 0.9)
	elseif proche then c.plage:SetColorTexture(0.9, 0.7, 0.15, 0.9)
	else c.plage:SetColorTexture(0.45, 0.45, 0.45, 0.8) end
	-- la zone sans XP, si l'échelle l'atteint
	c.gris = c.gris or c.barre:GetParent():CreateTexture(nil, "ARTWORK", nil, 1)
	c.gris:SetColorTexture(0.8, 0.15, 0.1, 0.55)
	c.gris:SetShown(seuil <= haut)
	if seuil <= haut then
		c.gris:ClearAllPoints()
		c.gris:SetPoint("TOPLEFT", c.barre, "TOPLEFT", X(seuil), 0)
		c.gris:SetPoint("BOTTOMRIGHT", c.barre, "BOTTOMRIGHT", 0, 0)
	end
	c.min:ClearAllPoints() c.min:SetPoint("TOP", c.plage, "BOTTOMLEFT", 0, -2) c.min:SetText(d.min)
	c.max:ClearAllPoints() c.max:SetPoint("TOP", c.plage, "BOTTOMRIGHT", 0, -2) c.max:SetText(d.max)
	local x = X(n)
	c.moi:ClearAllPoints() c.moi:SetPoint("TOPLEFT", c.barre, "TOPLEFT", x - 1, 3) c.moi:SetPoint("BOTTOMLEFT", c.barre, "BOTTOMLEFT", x - 1, -3)
	c.moi:SetColorTexture(n >= seuil and 1 or 1, n >= seuil and 0.3 or 1, n >= seuil and 0.3 or 1, 1)
	c.moiTexte:ClearAllPoints() c.moiTexte:SetPoint("BOTTOM", c.moi, "TOP", 0, 1)
	c.moiTexte:SetText(n >= seuil and Opus.Rouge("toi " .. n) or Opus.Blanc("toi " .. n))
	-- les autres : un petit repère chacun, rouge s'ils rendraient les monstres gris
	c.reperes = c.reperes or {}
	for i, j in ipairs(joueurs or {}) do
		local r = c.reperes[i] or c.barre:GetParent():CreateTexture(nil, "OVERLAY")
		c.reperes[i] = r
		r:SetWidth(2)
		-- au-delà du seuil : rouge, ou doré si le groupe accepte le PL (il vient booster)
		local rouge = j.niveau >= seuil
		if rouge and j.booste then r:SetColorTexture(1, 0.82, 0, 1)
		else r:SetColorTexture(rouge and 1 or 0.45, rouge and 0.25 or 0.75, rouge and 0.25 or 1, 0.9) end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", c.barre, "TOPLEFT", X(j.niveau) - 1, 2) r:SetPoint("BOTTOMLEFT", c.barre, "BOTTOMLEFT", X(j.niveau) - 1, -2)
		r:Show()
	end
	for i = #(joueurs or {}) + 1, #c.reperes do c.reperes[i]:Hide() end
end

local function Carte (v, largeur)
	local c = CreateFrame("Frame", nil, v, "BackdropTemplate")
	c:SetWidth(largeur - 14)
	if c.SetBackdrop then
		c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		c:SetBackdropColor(0.06, 0.05, 0.04, 0.85)
		c:SetBackdropBorderColor(0.45, 0.38, 0.25, 0.9)
	end
	c.titre = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.titre:SetPoint("TOPLEFT", 12, -10) c.titre:SetWidth(300) c.titre:SetJustifyH("LEFT") c.titre:SetWordWrap(false)
	c.sous = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.sous:SetPoint("TOPLEFT", c.titre, "BOTTOMLEFT", 0, -3)
	-- la barre de niveaux, sous le titre
	c.niveaux = Opus.CreerBarre(c)
	c.niveaux.barre:SetPoint("TOPLEFT", 12, -60)
	-- les cinq places, à droite du titre
	c.places = {}
	for i = 1, #Opus.PLACES do
		local t = c:CreateTexture(nil, "ARTWORK")
		t:SetSize(26, 26) t:SetPoint("TOPLEFT", 330 + (i - 1) * 30, -12)
		c.places[i] = t
		-- au survol : qui tient la place
		local z = CreateFrame("Frame", nil, c)
		z:SetAllPoints(t) z:EnableMouse(true)
		t.zone = z
		Opus.Bulle(z, function (self) return self.titre end, function (self) return self.texte end)
	end
	c.etat = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.etat:SetPoint("TOPLEFT", 330, -44) c.etat:SetWidth(210) c.etat:SetJustifyH("LEFT") c.etat:SetWordWrap(false)
	c.moiAussi = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
	c.moiAussi:SetWidth(110) c.moiAussi:SetPoint("TOPRIGHT", -10, -10)
	c.moiAussi:SetDefaultText("Moi aussi")
	c.moiAussi:SetupMenu(function (_, racine)
		local garder = MenuResponse and MenuResponse.Refresh
		local mes = Opus.ListeRoles(Opus.MesRoles())
		local function NomRole (r) return CreateAtlasMarkup(ATLAS_ROLES[r], 14, 14) .. " " .. (r == "tank" and "Tank" or r == "soin" and "Soigneur" or "Dégâts") end
		-- sa propre envie sur ce donjon : le rôle et le créneau se changent tout de suite
		local mienne = c.mienne
		if mienne then
			local actuels = Opus.ListeRoles(mienne.roles)
			local tous = #actuels ~= 1
			if #mes > 1 then
				racine:CreateTitle("Je viens en")
				racine:CreateRadio("Tous mes rôles", function () return tous end, function () Opus.ModifierEnvie(mienne.id, { roles = false }, c.donjon.cle) end)
				for _, r in ipairs(mes) do
					racine:CreateRadio(NomRole(r), function () return not tous and actuels[1] == r end, function () Opus.ModifierEnvie(mienne.id, { roles = r }, c.donjon.cle) end)
				end
				racine:CreateDivider()
			end
			racine:CreateTitle("Disponible")
			for _, cr in ipairs(Opus.CRENEAUX) do
				if cr[1] ~= "autre" then
					racine:CreateRadio(cr[2], function () return mienne.creneau == cr[1] end, function () Opus.ModifierEnvie(mienne.id, { creneau = cr[1] }, c.donjon.cle) end)
				end
			end
			racine:CreateDivider()
			racine:CreateCheckbox("PL accepté (un grand peut booster)", function () return mienne.pl == true end,
				function () Opus.ModifierEnvie(mienne.id, { pl = not mienne.pl }, c.donjon.cle) end)
			racine:CreateDivider()
			-- clôt aussi les envies des membres de son groupe sur ce donjon (fait ou pas, peu importe)
			racine:CreateButton("Clore pour mon groupe", function () Opus.DonjonFait(c.donjon.cle) end)
			racine:CreateButton("Retirer mon envie pour ce donjon", function () Opus.RetirerEnvie(mienne.id, c.donjon.cle) end)
			return
		end
		-- sinon « Moi aussi » : d'abord le rôle, si on en joue plusieurs (le menu reste ouvert), puis le créneau, qui publie
		if #mes > 1 then
			c.roleChoisi = c.roleChoisi or "tous"
			racine:CreateTitle("Je viens en")
			racine:CreateRadio("Tous mes rôles", function () return c.roleChoisi == "tous" end, function () c.roleChoisi = "tous" return garder end)
			for _, r in ipairs(mes) do
				racine:CreateRadio(NomRole(r), function () return c.roleChoisi == r end, function () c.roleChoisi = r return garder end)
			end
			racine:CreateDivider()
			racine:CreateTitle("Disponible")
		end
		for _, cr in ipairs(Opus.CRENEAUX) do
			racine:CreateButton(cr[2], function ()
				local cle = c.donjon and c.donjon.cle
				if not cle then return end
				if cr[1] == "autre" then Opus.EditerEnvie(cle, "autre", true) return end
				local role = c.roleChoisi and c.roleChoisi ~= "tous" and c.roleChoisi or nil
				Opus.PublierEnvie({ donjons = { cle }, pourquoi = {}, creneau = cr[1], duree = Opus.DureePourCreneau(cr[1]), suite = true, roles = role })
			end)
		end
		-- sans envie sur ce donjon, mais en groupe avec des intéressés (celui qui a mené le groupe, un booster…)
		if c.donjon and #Opus.GroupeAvecEnvie(c.donjon.cle) > 0 then
			racine:CreateDivider()
			racine:CreateButton("Clore pour mon groupe", function () Opus.DonjonFait(c.donjon.cle) end)
		end
	end)
	-- inviter ceux qui sont disponibles maintenant, depuis la carte : /invite dans un bouton sécurisé
	c.inviter = Opus.BoutonSecurise(c, 110, function (self)
		GameTooltip:SetText("Inviter les dispo")
		if #self.noms == 0 then
			GameTooltip:AddLine("Personne d'autre n'est disponible maintenant et en ligne.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Invite ceux qui sont disponibles maintenant et en ligne, la composition d'abord :", 1, 1, 1, true)
			for _, nom in ipairs(self.noms) do GameTooltip:AddLine(nom, 0.5, 0.5, 0.5) end
		end
	end)
	c.inviter:SetText("Inviter les dispo")
	c.inviter:SetPoint("TOPRIGHT", c.moiAussi, "BOTTOMRIGHT", 0, -6)
	c.inviter.noms = {}

	-- les joueurs intéressés, une ligne chacun sous l'en-tête
	c.joueurs = {}
	for i = 1, JOUEURS_MAX do
		local l = CreateFrame("Button", nil, c)
		l:SetSize(largeur - 40, JOUEUR_H)
		l:SetPoint("TOPLEFT", 10, -84 - (i - 1) * JOUEUR_H)
		Opus.Survol(l)
		l.icone = l:CreateTexture(nil, "ARTWORK")
		l.icone:SetSize(14, 14) l.icone:SetPoint("LEFT", 2, 0)
		local function Texte (x, w)
			local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", x, 0) t:SetWidth(w) t:SetJustifyH("LEFT") t:SetWordWrap(false)
			return t
		end
		l.nom = Texte(22, 150)
		l.roles = Texte(176, 44)
		l.quand = Texte(222, 170)
		l.quoi = Texte(396, 150)
		l.action = Opus.Bouton(l, "Écrire", 64, function ()
			local e = l.envie
			if not e then return end
			if e.par == Opus.MonNom() then Opus.RetirerEnvie(e.id, c.donjon and c.donjon.cle) else Chuchoter(e.par) end
		end, true)
		l.action:SetPoint("RIGHT", 0, 0) l.action:SetHeight(16)
		Opus.Bulle(l, function (self) return self.envie and self.envie.par end, function (self)
			local e = self.envie
			if not e then return nil end
			local lignes = {}
			local quoi = Opus.TextePourquoi(e)
			if quoi ~= "" then lignes[#lignes + 1] = "Pour : " .. quoi end
			local m, d = Opus.TrouverMembre(e.par), self:GetParent().donjon
			if m and d and d.max and m.niveau - d.max >= Opus.ECART_GRIS and Opus.PLAccepte(d.cle) then
				lignes[#lignes + 1] = Opus.Normal("Vient booster : le groupe accepte le PL (avec lui, les monstres sont gris et ne rapportent plus d'XP).")
			elseif m and d and d.max and m.niveau - d.max >= Opus.ECART_GRIS then
				lignes[#lignes + 1] = Opus.Rouge(("Monstres gris pour lui (%d niveaux au-dessus du donjon) : avec lui, plus personne ne gagne d'XP. Un reroll ?"):format(m.niveau - d.max))
			end
			if e.pl then lignes[#lignes + 1] = Opus.Normal("PL accepté : un grand peut venir booster.") end
			if e.note then lignes[#lignes + 1] = e.note end
			lignes[#lignes + 1] = Opus.Gris("Publiée le " .. date("%d/%m à %H h %M", e.m) .. ", affichée jusqu'au " .. date("%d/%m à %H h", e.fin) .. ".")
			return lignes
		end)
		c.joueurs[i] = l
	end
	c.plus = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	-- le badge Discord, à cheval sur l'angle : une expédition est prévue pour ce donjon (client opus-bridge)
	c.discord = CreateFrame("Button", nil, c)
	c.discord:SetSize(22, 22) c.discord:SetPoint("CENTER", c, "TOPLEFT", 4, -4)
	c.discord.icone = c.discord:CreateTexture(nil, "ARTWORK")
	c.discord.icone:SetAllPoints() c.discord.icone:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
	if Opus.BulleExpedition then Opus.BulleExpedition(c.discord) end
	c.discord:Hide()
	return c
end

local function RemplirCarte (c, g)
	local d, moi = g.d, Opus.MonNom()
	c.donjon = d
	c.discord.exp = Opus.ExpeditionPour and Opus.ExpeditionPour(d.cle)
	c.discord:SetShown(c.discord.exp ~= nil)
	c.titre:SetText(APortee(d) and d.nom or Opus.Gris(d.nom))
	local pourquoi = {}
	for _, e in ipairs(g.envies) do for cle in pairs(e.pourquoi) do pourquoi[cle] = true end end
	local raisons = {}
	for _, p in ipairs(Opus.POURQUOI) do if pourquoi[p[1]] then raisons[#raisons + 1] = p[2]:lower() end end
	local pl = Opus.PLAccepte(d.cle)
	c.sous:SetText(Opus.Gris((d.min and ("niveaux %d à %d"):format(d.min, d.max) or "") .. (d.entree and (", entrée dès " .. d.entree) or "") .. (#raisons > 0 and ("  ·  " .. table.concat(raisons, ", ")) or ""))
		.. (pl and ("  ·  " .. Opus.Normal("PL accepté")) or ""))
	local niveaux, moi = {}, Opus.MonNom()
	for _, e in ipairs(g.envies) do
		local m = e.par ~= moi and Opus.TrouverMembre(e.par)
		if m and m.niveau then niveaux[#niveaux + 1] = { niveau = m.niveau, booste = pl } end
	end
	Opus.PlacerBarre(c.niveaux, d, niveaux)
	-- une place pleine : quelqu'un est disponible maintenant pour la tenir ; à demi teintée : un intéressé s'y est
	-- déclaré pour un autre créneau (son envie compte, soi compris) ; grisée : personne
	local manque = 0
	for i, r in ipairs(Opus.PLACES) do
		local t = c.places[i]
		Atlas(t, ATLAS_PLACES[r], ATLAS_ROLES[r])
		local NOMS_PLACES = { tank = "Tank", soin = "Soigneur", degats = "Dégâts" }
		t.zone.titre = NOMS_PLACES[r]
		if g.places[i] then
			t:SetDesaturated(false) t:SetAlpha(1)
			t.zone.texte = { g.places[i], Opus.Vert("disponible maintenant") }
		elseif g.prevues[i] then
			t:SetDesaturated(false) t:SetAlpha(0.5)
			t.zone.texte = { g.prevues[i], Opus.Gris("intéressé, pour un autre créneau") }
			manque = manque + 1
		else
			t:SetDesaturated(true) t:SetAlpha(0.25)
			t.zone.texte = Opus.Gris("Personne pour l'instant.")
			manque = manque + 1
		end
	end
	c.etat:SetText(#g.dispo == 0 and Opus.Gris(#g.envies .. " intéressé(s) · personne de dispo")
		or manque == 0 and Opus.Vert("Groupe complet possible maintenant !")
		or (Opus.Vert(#g.dispo .. " disponible(s) maintenant") .. Opus.Gris(" · " .. #g.envies .. " intéressé(s)")))
	-- les invités : la composition d'abord, puis les autres disponibles, quatre au plus (on est le cinquième)
	local noms, pris = {}, { [moi] = true }
	local function Ajouter (nom)
		if nom and not pris[nom] and #noms < #Opus.PLACES - 1 and not UnitInParty(nom) then noms[#noms + 1] = nom end
		if nom then pris[nom] = true end
	end
	for i = 1, #Opus.PLACES do Ajouter(g.places[i]) end
	for _, j in ipairs(g.dispo) do Ajouter(j.nom) end
	c.inviter.noms = noms
	if not InCombatLockdown() then
		local lignes = {}
		for _, nom in ipairs(noms) do lignes[#lignes + 1] = "/invite " .. nom end
		c.inviter:SetAttribute("macrotext", table.concat(lignes, "\n"))
		c.inviter:SetEnabled(#noms > 0)
	end
	-- le menu : « Mon envie » si on en a une sur ce donjon, sinon « Moi aussi » ; jamais le rôle choisi en titre
	c.mienne = nil
	for _, e in ipairs(g.envies) do if e.par == moi then c.mienne = e end end
	c.moiAussi:GenerateMenu()
	c.moiAussi:OverrideText(c.mienne and "Mon envie" or "Moi aussi")
	local montres = math.min(#g.envies, JOUEURS_MAX)
	for i, l in ipairs(c.joueurs) do
		local e = g.envies[i]
		l.envie = e
		l:SetShown(e ~= nil and i <= montres)
		if e then
			local m = Opus.TrouverMembre(e.par)
			local classe = Opus.db.classes[e.par] or (m and m.classe)
			local atlas = classe and GetClassAtlas and GetClassAtlas(classe:lower())
			if atlas then l.icone:SetAtlas(atlas) end
			l.icone:SetShown(atlas ~= nil)
			local gris = m and m.niveau and d.max and m.niveau - d.max >= Opus.ECART_GRIS
			local niveau = m and m.niveau and (gris and (pl and Opus.Normal("  " .. m.niveau .. " booste") or Opus.Rouge("  " .. m.niveau)) or Opus.Gris("  " .. m.niveau)) or ""
			l.nom:SetText((classe and Opus.Couleur(classe) or "") .. e.par .. "|r" .. niveau
				.. ((m and m.enLigne) and "" or Opus.Gris("  hors ligne")))
			l.roles:SetText(IconesRoles(e.roles))
			l.quand:SetText(Opus.TexteCreneau(e))
			l.quoi:SetText(Opus.Gris(e.note or Opus.TextePourquoi(e)))
			l.action:SetText(e.par == moi and "Retirer" or "Écrire")
		end
	end
	local h = 84 + montres * JOUEUR_H + 8
	c.plus:SetShown(#g.envies > montres)
	if #g.envies > montres then
		c.plus:ClearAllPoints() c.plus:SetPoint("TOPLEFT", 32, -(84 + montres * JOUEUR_H))
		c.plus:SetText(("… et %d autre(s)"):format(#g.envies - montres))
		h = h + 14
	end
	c:SetHeight(h)
	return h
end

-- pour l'onglet Groupe (PageGroupe.lua), qui assemble les cartes
Opus.DonjonsDemandes = Donjons
Opus.CarteDonjon = Carte
Opus.RemplirCarteDonjon = RemplirCarte
Opus.IconesRoles = IconesRoles
Opus.APortee = APortee
Opus.Chuchoter = Chuchoter
function Opus.AtlasPlace (texture, role) Atlas(texture, ATLAS_PLACES[role], ATLAS_ROLES[role]) end

-- l'annonce en guilde de sa dernière envie, pour ceux qui n'ont pas l'addon (« » sans envie)
function Opus.MacroEnvie ()
	local moi = Opus.MonNom()
	for _, e in ipairs(Opus.Envies()) do
		if e.par == moi then
			local noms = {}
			for _, cle in ipairs(e.donjons) do noms[#noms + 1] = Opus.DonjonDe(cle).nom end
			local quoi = Opus.TextePourquoi(e)
			local quand = Opus.TexteCreneau(e):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			return (("/g [Opus] Je cherche du monde pour %s%s, %s%s : les détails dans l'addon Opus, onglet Groupe !"):format(table.concat(noms, ", "),
				quoi ~= "" and (" (" .. quoi .. ")") or "", quand, e.pl and ", PL accepté" or "")):sub(1, 255)
		end
	end
	return ""
end
