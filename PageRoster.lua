-- PageRoster.lua : la composition de la guilde. Les rôles en un coup d'œil, puis une carte par classe : combien, quelles
-- spés (celles annoncées par l'addon de chacun), quels niveaux ; au survol, les membres de la classe.
local _, Opus = ...

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local COLONNES, LARGEUR_CARTE, HAUTEUR_CARTE, ECART, HAUT = 3, 224, 96, 9, 30
local NIVEAU_MAX = 60
local cartes, filtre = {}, "tous"

local FILTRES = { { "tous", "Tous les membres" }, { "max", "Niveau " .. NIVEAU_MAX }, { "raid", "Raiders (voie du Tour)" }, { "enligne", "En ligne" } }
local ROLES = { tank = "roleicon-tiny-tank", soin = "roleicon-tiny-healer", degats = "roleicon-tiny-dps" }

local function IconeRole (role, taille) return CreateAtlasMarkup(ROLES[role], taille or 14, taille or 14) end

local function Garder (m)
	if filtre == "max" then return m.niveau >= NIVEAU_MAX end
	if filtre == "enligne" then return m.enLigne end
	if filtre == "raid" then
		local g = Opus.GRADES[m.grade] or {}
		return g.voie == "Tour" or g.essai == "raid"
	end
	return true
end

-- par classe : les membres, leurs spés connues, leurs rôles
local function Composition ()
	local parClasse, roles, connues, total = {}, { tank = 0, soin = 0, degats = 0, inconnu = 0 }, 0, 0
	for _, c in ipairs(CLASSES) do parClasse[c] = { membres = {}, spes = {}, roles = { tank = 0, soin = 0, degats = 0 }, inconnues = 0, niveaux = 0, max = 0 } end
	for _, m in ipairs(Opus.Membres()) do
		local c = m.classe and parClasse[m.classe]
		if c and Garder(m) then
			total = total + 1
			c.membres[#c.membres + 1] = m
			c.niveaux = c.niveaux + m.niveau
			if m.niveau >= NIVEAU_MAX then c.max = c.max + 1 end
			local s = Opus.db.spes[m.nom]
			m.spe = s
			if s then
				connues = connues + 1
				c.spes[s.arbre] = (c.spes[s.arbre] or 0) + 1
				local r = Opus.RoleDeSpe(s.arbre)
				if r then c.roles[r] = c.roles[r] + 1 roles[r] = roles[r] + 1 else roles.inconnu = roles.inconnu + 1 end
			else
				c.inconnues = c.inconnues + 1
				roles.inconnu = roles.inconnu + 1
			end
		end
	end
	return parClasse, roles, connues, total
end

local function Rafraichir (cadre)
	cadre.filtre:GenerateMenu()
	local parClasse, roles, connues, total = Composition()
	cadre.info:SetText(("%d membres · %d spé(s) connue(s)"):format(total, connues))
	cadre.roles:SetText(("%s %s tanks     %s %s soigneurs     %s %s dégâts     %s"):format(
		IconeRole("tank", 16), Opus.Blanc(roles.tank), IconeRole("soin", 16), Opus.Blanc(roles.soin),
		IconeRole("degats", 16), Opus.Blanc(roles.degats), Opus.Gris(roles.inconnu .. " sans spé connue")))

	for i, classe in ipairs(CLASSES) do
		local carte, c = cartes[i], parClasse[classe]
		local n = #c.membres
		local nomClasse = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classe]) or classe
		carte.c = c
		carte.icone:SetText(CreateAtlasMarkup(GetClassAtlas(classe:lower()), 28, 28))
		carte.icone:SetAlpha(n > 0 and 1 or 0.35)
		carte.nom:SetText(n > 0 and (Opus.Couleur(classe) .. nomClasse .. "|r") or Opus.Gris(nomClasse))
		carte.nombre:SetText(n > 0 and Opus.Blanc(n) or Opus.Gris("0"))
		-- les spés, de la plus jouée à la moins jouée, puis les inconnues
		local liste = {}
		for arbre, k in pairs(c.spes) do liste[#liste + 1] = { arbre = arbre, k = k } end
		table.sort(liste, function (a, b) return a.k > b.k end)
		local morceaux = {}
		for _, s in ipairs(liste) do morceaux[#morceaux + 1] = s.arbre .. " " .. Opus.Blanc(s.k) end
		if c.inconnues > 0 then morceaux[#morceaux + 1] = Opus.Gris(c.inconnues .. " ?") end
		carte.spes:SetText(n > 0 and table.concat(morceaux, " · ") or Opus.Gris("personne"))
		local r = {}
		for _, role in ipairs { "tank", "soin", "degats" } do
			if c.roles[role] > 0 then r[#r + 1] = IconeRole(role) .. " " .. c.roles[role] end
		end
		carte.roles:SetText(table.concat(r, "   "))
		carte.niveaux:SetText(n > 0 and Opus.Gris(("niv. moyen %d · %d au %d"):format(math.floor(c.niveaux / n + 0.5), c.max, NIVEAU_MAX)) or "")
	end
	return HAUT + math.ceil(#CLASSES / COLONNES) * (HAUTEUR_CARTE + ECART) + 16
end

-- au survol d'une carte : ses membres, avec leur spé
local function Bulle (self)
	local c, lignes = self.c, {}
	if not c or #c.membres == 0 then return nil end
	table.sort(c.membres, function (a, b)
		if a.niveau ~= b.niveau then return a.niveau > b.niveau end
		return a.nom < b.nom
	end)
	for i, m in ipairs(c.membres) do
		if i > 20 then lignes[#lignes + 1] = Opus.Gris(("… et %d autre(s)"):format(#c.membres - 20)) break end
		local s = m.spe
		local role = s and Opus.RoleDeSpe(s.arbre)
		lignes[#lignes + 1] = ("%s%s  %s  %s%s"):format(role and (IconeRole(role) .. " ") or "", Opus.Blanc(m.nom), Opus.Gris("niv. " .. m.niveau),
			s and (s.arbre .. Opus.Gris(" (" .. s.points .. ")")) or Opus.Gris("spé inconnue"), m.enLigne and ("  " .. Opus.Vert("en ligne")) or "")
	end
	return lignes
end

local function Construire (cadre, barre)
	cadre.filtre = Opus.Menu(barre, 200, FILTRES, function () return filtre end, function (v) filtre = v Opus.Rafraichir() end)
	cadre.filtre:SetPoint("LEFT", 0, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	cadre.roles = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cadre.roles:SetPoint("TOPLEFT", 4, -4)

	for i = 1, #CLASSES do
		local col, ligne = (i - 1) % COLONNES, math.floor((i - 1) / COLONNES)
		-- une carte = un encart natif du client
		local carte = CreateFrame("Frame", nil, cadre, "InsetFrameTemplate")
		carte:SetSize(LARGEUR_CARTE, HAUTEUR_CARTE)
		carte:SetPoint("TOPLEFT", col * (LARGEUR_CARTE + ECART), -HAUT - ligne * (HAUTEUR_CARTE + ECART))
		carte:EnableMouse(true)
		Opus.Bulle(carte, function (self)
			local c = self.c
			return c and #c.membres > 0 and self.nom:GetText() or nil
		end, Bulle)
		local function Texte (police, ...)
			local t = carte:CreateFontString(nil, "OVERLAY", police)
			t:SetPoint(...) t:SetJustifyH("LEFT")
			return t
		end
		carte.icone = Texte("GameFontHighlight", "TOPLEFT", 8, -8)
		carte.nom = Texte("GameFontNormalLarge", "TOPLEFT", 44, -10)
		carte.nombre = Texte("GameFontHighlightLarge", "TOPRIGHT", -10, -10)
		carte.spes = Texte("GameFontHighlightSmall", "TOPLEFT", 10, -44)
		carte.spes:SetWidth(LARGEUR_CARTE - 20) carte.spes:SetWordWrap(true) carte.spes:SetMaxLines(2)
		carte.roles = Texte("GameFontHighlightSmall", "BOTTOMLEFT", 10, 10)
		carte.niveaux = Texte("GameFontDisableSmall", "BOTTOMRIGHT", -10, 10)
		carte.niveaux:SetJustifyH("RIGHT")
		cartes[i] = carte
	end
end

Opus.Page("roster", "Roster", Construire, Rafraichir)
