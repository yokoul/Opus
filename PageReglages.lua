-- PageReglages.lua : l'onglet « Réglages ». Ce qui ne se faisait que par /opus : ses préférences (annonces de niveau,
-- rôles, minimap), le partage (banque, liaisons Discord), la durée des essais (chef de guilde), les outils du chef et
-- des officiers, et les diagnostics. Chaque bouton passe par la même commande que /opus, pour qu'il n'y ait qu'un seul chemin.
local _, Opus = ...

local function Commande (texte) SlashCmdList.OPUS(texte) end

local NIVEAUX = { { "60", "Le niveau 60 seulement" }, { "paliers", "Les paliers de 10" }, { "tous", "Tous les niveaux" }, { "aucun", "Aucune" } }
local NOTIFS = { { "toutes", "Toutes" }, { "aucune", "Aucune" } }
local ROLES = { { "tank", "Tank" }, { "soin", "Soigneur" }, { "degats", "Dégâts" } }
local NOMS_ROLES = { tank = "tank", soin = "soigneur", degats = "dégâts" }

local X_CONTROLE = 300           -- colonne des réglages, à droite des libellés

local function Rafraichir (cadre)
	cadre.niveaux:GenerateMenu()
	cadre.notifs:GenerateMenu()
	-- ses rôles : ceux qu'il a cochés ; rien de coché, celui de sa spé
	local declares = {}
	for _, r in ipairs(Opus.ListeRoles(Opus.db.monRole)) do declares[r] = true end
	for r, c in pairs(cadre.roles) do c:SetChecked(declares[r] == true) end
	local spe = Opus.MaSpe and Opus.MaSpe()
	local deSpe = spe and Opus.RoleDeSpe(spe.arbre)
	cadre.roleAide:SetText(next(declares) and "Coche tout ce que tu sais jouer en donjon." or
		("Rien de coché : selon ta spé" .. (deSpe and (" (" .. NOMS_ROLES[deSpe] .. ")") or "") .. "."))
	cadre.minimap:SetChecked(not Opus.db.minimap.cache)

	-- la durée des essais : réglage de la guilde, modifiable par le chef seulement
	local chef = IsGuildLeader()
	local essais = Opus.GradesEssai()
	for i, d in ipairs(cadre.durees) do
		local g = essais[i]
		d.grade = g and g.nom
		d.nom:SetShown(g ~= nil) d.saisie:SetShown(g ~= nil)
		if g then
			d.nom:SetText(g.nom)
			d.saisie:SetEnabled(chef)
			if not d.saisie:HasFocus() then d.saisie:SetText(Opus.DureeEssai(g.nom)) end
		end
	end
	cadre.dureesAide:SetText(#essais == 0 and "Aucun grade d'essai dans la grille." or
		chef and "Partagée à toute la guilde." or "Réglée par le chef de guilde, partagée à tous.")

	local n = #Opus.db.banque.evenements
	cadre.banque:SetText(("%d opération(s) relevée(s) · %d membre(s) avec l'addon ces 7 jours"):format(n, Opus.Pairs()))
	local etat = Opus.EtatDiscord()
	cadre.discord:SetText(etat or Opus.Gris("Aucune liaison : un officier colle le code de /persoadmin export."))

	local officier = Opus.PeutConfigurer()
	cadre.import:SetEnabled(officier)
	for _, w in ipairs(cadre.officiers) do w:SetShown(officier) end
	cadre.horsOfficiers:SetShown(not officier)
	return cadre.hauteur
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	local titre = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titre:SetPoint("LEFT", 0, 0)
	titre:SetText("Réglages d'Opus")

	local y = -4
	local function Section (texte)
		local s = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		s:SetPoint("TOPLEFT", 4, y) s:SetText(texte)
		y = y - 26
		return s
	end
	local function Libelle (texte, aide)
		local t, a = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), nil
		t:SetPoint("TOPLEFT", 16, y - 4) t:SetText(texte)
		if aide then
			a = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			a:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2) a:SetWidth(X_CONTROLE - 30) a:SetJustifyH("LEFT") a:SetText(aide)
		end
		return t, a
	end
	local function Ligne (hauteur) y = y - (hauteur or 34) end

	-- ses préférences
	Section("Mes préférences")
	Libelle("Annonce des montées de niveau", "Dans la discussion ; le 60 aussi à l'écran.")
	cadre.niveaux = Opus.Menu(cadre, 220, NIVEAUX, function () return Opus.db.annonceNiveaux or "60" end, function (v) Commande("niveaux " .. v) end)
	cadre.niveaux:SetPoint("TOPLEFT", X_CONTROLE, y)
	Ligne(40)
	Libelle("Envies de donjon", "Notification quand un membre annonce une envie.")
	cadre.notifs = Opus.Menu(cadre, 220, NOTIFS, function () return Opus.db.notifEnvies or "toutes" end, function (v) Opus.db.notifEnvies = v end)
	cadre.notifs:SetPoint("TOPLEFT", X_CONTROLE, y)
	Ligne(40)
	local _, aide = Libelle("Mes rôles en groupe", " ")
	cadre.roleAide = aide
	cadre.roles = {}
	local function ChangerRoles ()
		local liste = {}
		for _, r in ipairs(ROLES) do if cadre.roles[r[1]]:GetChecked() then liste[#liste + 1] = r[1] end end
		Commande("role " .. (#liste > 0 and table.concat(liste, " ") or "auto"))
		Opus.Rafraichir()
	end
	for i, r in ipairs(ROLES) do
		local c = CreateFrame("CheckButton", nil, cadre, "UICheckButtonTemplate")
		c:SetSize(24, 24) c:SetPoint("TOPLEFT", X_CONTROLE - 4 + (i - 1) * 110, y)
		local t = c.Text or c.text
		if t then t:SetText(r[2]) t:SetFontObject("GameFontHighlightSmall") end
		c:SetScript("OnClick", ChangerRoles)
		cadre.roles[r[1]] = c
	end
	Ligne(40)
	Libelle("Bouton de la minimap")
	cadre.minimap = CreateFrame("CheckButton", nil, cadre, "UICheckButtonTemplate")
	cadre.minimap:SetSize(24, 24) cadre.minimap:SetPoint("TOPLEFT", X_CONTROLE - 4, y)
	cadre.minimap:SetScript("OnClick", function (self)
		if self:GetChecked() == (Opus.db.minimap.cache == true) then Commande("minimap") end
	end)
	Ligne(30)

	-- le partage
	Section("Données partagées")
	Libelle("Banque")
	cadre.banque = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.banque:SetPoint("TOPLEFT", 16, y - 22)
	local sync = Opus.Bouton(cadre, "Synchroniser", 130, function () Commande("sync") end)
	sync:SetPoint("TOPRIGHT", -8, y)
	Opus.Bulle(sync, "Synchroniser la banque", "Demande aux membres en ligne les opérations qui te manquent.")
	Ligne(46)
	Libelle("Liaisons Discord")
	cadre.discord = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.discord:SetPoint("TOPLEFT", 16, y - 22) cadre.discord:SetWidth(largeur - 170) cadre.discord:SetJustifyH("LEFT")
	cadre.import = Opus.Bouton(cadre, "Importer…", 130, function () Opus.OuvrirImport() end)
	cadre.import:SetPoint("TOPRIGHT", -8, y)
	Opus.Bulle(cadre.import, "Importer les liaisons Discord", "Coller le code de /persoadmin export (chef et officiers). L'addon le partage ensuite à la guilde.")
	Ligne(46)

	-- la durée des essais, pour toute la guilde (le chef seul la modifie, comme les grades en jeu)
	Section("Essais")
	local _, aideDurees = Libelle("Durée des essais (jours)", " ")
	cadre.dureesAide = aideDurees
	cadre.durees = {}
	for i = 1, 3 do
		local d = {}
		d.nom = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		d.nom:SetPoint("TOPLEFT", X_CONTROLE + (i - 1) * 130, y - 6)
		d.saisie = CreateFrame("EditBox", nil, cadre, "InputBoxTemplate")
		d.saisie:SetSize(36, 20) d.saisie:SetPoint("LEFT", d.nom, "RIGHT", 10, 0)
		d.saisie:SetAutoFocus(false) d.saisie:SetNumeric(true) d.saisie:SetMaxLetters(3)
		local function Valider (self)
			local n = tonumber(self:GetText())
			if d.grade and n and n ~= Opus.DureeEssai(d.grade) then Opus.ModifierDureeEssai(d.grade, n) end
			self:ClearFocus()
			Opus.Rafraichir()
		end
		d.saisie:SetScript("OnEnterPressed", Valider)
		d.saisie:SetScript("OnEditFocusLost", Valider)
		d.saisie:SetScript("OnEscapePressed", function (self) self:SetText(d.grade and Opus.DureeEssai(d.grade) or "") self:ClearFocus() end)
		cadre.durees[i] = d
	end
	Ligne(40)

	-- le chef et les officiers
	Section("Guilde (chef et officiers)")
	cadre.officiers = {}
	cadre.horsOfficiers = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.horsOfficiers:SetPoint("TOPLEFT", 16, y - 4)
	cadre.horsOfficiers:SetText("Réservé au chef et aux officiers.")
	local function Outil (libelle, aide, bouton, commande)
		local t, a = Libelle(libelle, aide)
		local b = Opus.Bouton(cadre, bouton, 130, commande)
		b:SetPoint("TOPRIGHT", -8, y)
		table.insert(cadre.officiers, t) table.insert(cadre.officiers, b)
		if a then table.insert(cadre.officiers, a) end
		Ligne(40)
	end
	Outil("Restriction et cotisation", "Restriction temporaire (réparations, or) et barème de la cotisation.", "Ouvrir…", function () Opus.OuvrirReglages() end)
	Outil("Droits des grades", "Compare les droits réels à la grille (résultat dans la discussion).", "Contrôler", function () Commande("controle") end)
	Outil("Réglages à faire à la main", "Ce que le jeu ne laisse pas régler par l'addon, grade par grade.", "Afficher", function () Commande("fiche") end)

	-- les diagnostics
	Section("Diagnostics")
	Libelle("Résultats dans la discussion, pour signaler un problème.")
	local px = X_CONTROLE
	for _, d in ipairs { { "Banque", "diagbanque" }, { "Droits", "diag" }, { "Spé", "diagspe" } } do
		local b = Opus.Bouton(cadre, d[1], 90, function () Commande(d[2]) end)
		b:SetPoint("TOPLEFT", px, y)
		px = px + 98
	end
	Ligne(34)
	cadre.hauteur = -y + 8
end

Opus.Page("reglages", "Réglages", Construire, Rafraichir)
