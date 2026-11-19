-- PageReglages.lua : l'onglet « Réglages ». Ce qui ne se faisait que par /opus : ses préférences (annonces de niveau,
-- rôle, minimap, durée des essais), le partage (banque, liaisons Discord), les outils du chef et des officiers, et les
-- diagnostics. Chaque bouton passe par la même commande que /opus, pour qu'il n'y ait qu'un seul chemin.
local _, Opus = ...

local function Commande (texte) SlashCmdList.OPUS(texte) end

local NIVEAUX = { { "60", "Le niveau 60 seulement" }, { "paliers", "Les paliers de 10" }, { "tous", "Tous les niveaux" }, { "aucun", "Aucune" } }
local ROLES = { { "auto", "Selon ma spé" }, { "tank", "Tank" }, { "soin", "Soigneur" }, { "degats", "Dégâts" } }

local X_CONTROLE = 300           -- colonne des réglages, à droite des libellés

local function Rafraichir (cadre)
	cadre.niveaux:GenerateMenu()
	cadre.role:GenerateMenu()
	cadre.minimap:SetChecked(not Opus.db.minimap.cache)
	for nom, s in pairs(cadre.durees) do
		if not s:HasFocus() then s:SetText(Opus.db.dureeEssai[nom] or 14) end
	end

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
	Libelle("Mon rôle", "Quand ta spé ne le dit pas (druide farouche…).")
	cadre.role = Opus.Menu(cadre, 220, ROLES, function () return Opus.db.monRole or "auto" end, function (v) Commande("role " .. v) end)
	cadre.role:SetPoint("TOPLEFT", X_CONTROLE, y)
	Ligne(40)
	Libelle("Bouton de la minimap")
	cadre.minimap = CreateFrame("CheckButton", nil, cadre, "UICheckButtonTemplate")
	cadre.minimap:SetSize(24, 24) cadre.minimap:SetPoint("TOPLEFT", X_CONTROLE - 4, y)
	cadre.minimap:SetScript("OnClick", function (self)
		if self:GetChecked() == (Opus.db.minimap.cache == true) then Commande("minimap") end
	end)
	Ligne(30)
	Libelle("Durée des essais (jours)", "Pour le décompte de l'onglet Essais.")
	cadre.durees = {}
	local x = X_CONTROLE
	for _, nom in ipairs { "Apprenti", "Aspirant" } do
		local t = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("TOPLEFT", x, y - 6) t:SetText(nom)
		local s = CreateFrame("EditBox", nil, cadre, "InputBoxTemplate")
		s:SetSize(36, 20) s:SetPoint("LEFT", t, "RIGHT", 10, 0)
		s:SetAutoFocus(false) s:SetNumeric(true) s:SetMaxLetters(3)
		local function Valider (self)
			local n = tonumber(self:GetText())
			if n and n > 0 then Commande(("duree %s %d"):format(nom:lower(), n)) end
			self:ClearFocus()
			Opus.Rafraichir()
		end
		s:SetScript("OnEnterPressed", Valider)
		s:SetScript("OnEditFocusLost", function (self) if tonumber(self:GetText()) ~= Opus.db.dureeEssai[nom] then Valider(self) end end)
		s:SetScript("OnEscapePressed", function (self) self:ClearFocus() Opus.Rafraichir() end)
		cadre.durees[nom] = s
		x = x + 130
	end
	Ligne(40)

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
