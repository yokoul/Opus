-- Editeur.lua : modifier un grade de la grille (chef et officiers) ; rôle, voie, essai et sorties, description, droits
-- attendus, or et onglets. Enregistrer crée une nouvelle version de la grille, partagée aux membres (Partage.lua).
local _, Opus = ...

local e                      -- la fenêtre, créée au premier usage
local brouillon, rang        -- copie de la configuration en cours d'édition, et le grade édité

local DROITS = {
	{ "officier", "Officier (canaux, notes, MdJ)" }, { "inviter", "Inviter" }, { "promouvoir", "Promouvoir" },
	{ "retrograder", "Rétrograder" }, { "exclure", "Exclure" }, { "reparer", "Réparations guilde" },
}
local ESSAIS = { { "non", "Pas un essai" }, { "guilde", "Essai guilde" }, { "raid", "Essai raid" } }

local function Etiquette (parent, texte, x, y)
	local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("TOPLEFT", x, y)
	t:SetText(texte)
	return t
end

local function Saisie (parent, largeur, x, y, lettres)
	local s = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	s:SetSize(largeur, 20)
	s:SetPoint("TOPLEFT", x + 6, y)
	s:SetAutoFocus(false)
	if lettres then s:SetMaxLetters(lettres) end
	s:SetScript("OnEnterPressed", EditBox_ClearFocus)
	s:SetScript("OnEscapePressed", EditBox_ClearFocus)
	return s
end

local function Case (parent, texte, x, y)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c:SetPoint("TOPLEFT", x, y)
	local t = c.Text or c.text
	if t then t:SetText(texte) t:SetFontObject("GameFontHighlightSmall") end
	return c
end

local function Grade () return brouillon.grades[rang] end

-- les champs reprennent le grade du brouillon
local function Remplir ()
	local g = Grade()
	e:SetTitle("Grade : " .. (Opus.GRADES[rang] and Opus.GRADES[rang].nom or rang))
	e.role:SetText(g.role or "")
	e.voie:SetText(g.voie or "")
	e.desc:SetText(g.desc or "")
	e.essai:GenerateMenu()
	e.sorties:GenerateMenu()
	for _, d in ipairs(DROITS) do e.droits[d[1]]:SetChecked(g[d[1]] and true or false) end
	e.or_:SetText(tostring(g.or_ or 0))
	for t = 1, 3 do
		local o = g.onglets and g.onglets[t] or { voir = false, deposer = false, retraits = 0 }
		local ligne = e.onglets[t]
		ligne.nom:SetText(brouillon.onglets[t] or "")
		ligne.voir:SetChecked(o.voir) ligne.deposer:SetChecked(o.deposer)
		ligne.retraits:SetText(tostring(o.retraits or 0))
	end
end

-- les champs reviennent dans le brouillon
local function Relever ()
	local g = Grade()
	g.role = strtrim(e.role:GetText())
	g.voie = strtrim(e.voie:GetText()) ~= "" and strtrim(e.voie:GetText()) or nil
	g.desc = strtrim(e.desc:GetText()) ~= "" and strtrim(e.desc:GetText()) or nil
	for _, d in ipairs(DROITS) do g[d[1]] = e.droits[d[1]]:GetChecked() or nil end
	g.or_ = tonumber(e.or_:GetText()) or 0
	g.onglets = g.onglets or {}
	for t = 1, 3 do
		local ligne = e.onglets[t]
		local nom = strtrim(ligne.nom:GetText())
		brouillon.onglets[t] = nom ~= "" and nom or nil
		g.onglets[t] = { voir = ligne.voir:GetChecked() and true or false, deposer = ligne.deposer:GetChecked() and true or false,
			retraits = tonumber(ligne.retraits:GetText()) or 0 }
	end
end

local function Construire ()
	e = CreateFrame("Frame", "OpusEditeur", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(e)
	ButtonFrameTemplate_HideButtonBar(e)
	e:SetSize(460, 470)
	e:SetPoint("CENTER")
	e:SetFrameStrata("DIALOG")
	e:SetToplevel(true)
	e:EnableMouse(true)
	e:SetMovable(true)
	e:RegisterForDrag("LeftButton")
	e:SetScript("OnDragStart", e.StartMoving)
	e:SetScript("OnDragStop", e.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OpusEditeur")
	local z = e.Inset
	local x2 = 230

	Etiquette(z, "Rôle", 12, -12)
	e.role = Saisie(z, 190, 12, -30, 40)
	Etiquette(z, "Voie", x2, -12)
	e.voie = Saisie(z, 190, x2, -30, 20)

	Etiquette(z, "Essai", 12, -60)
	e.essai = Opus.Menu(z, 190, ESSAIS,
		function () return Grade().essai or "non" end,
		function (v) Grade().essai = v ~= "non" and v or nil end)
	e.essai:SetPoint("TOPLEFT", 12, -78)
	Etiquette(z, "Mène à", x2, -60)
	-- les sorties d'essai : des cases dans un menu, parmi les autres grades
	e.sorties = CreateFrame("DropdownButton", nil, z, "WowStyle1DropdownTemplate")
	e.sorties:SetWidth(190)
	e.sorties:SetPoint("TOPLEFT", x2, -78)
	e.sorties:SetDefaultText("aucun grade")
	e.sorties:SetupMenu(function (_, racine)
		for j, g in ipairs(Opus.GRADES) do
			if j ~= rang then
				racine:CreateCheckbox(g.nom, function () return tContains(Grade().sorties or {}, j) end, function ()
					local s = Grade().sorties or {}
					Grade().sorties = s
					if tContains(s, j) then tDeleteItem(s, j) else table.insert(s, j) end
				end)
			end
		end
	end)

	Etiquette(z, "Description", 12, -110)
	e.desc = Saisie(z, 410, 12, -128, 120)

	Etiquette(z, "Droits attendus", 12, -160)
	e.droits = {}
	for i, d in ipairs(DROITS) do
		e.droits[d[1]] = Case(z, d[2], 12 + ((i - 1) % 2) * 218, -178 - math.floor((i - 1) / 2) * 24)
	end
	Etiquette(z, "Or par jour (po)", 12, -254)
	e.or_ = Saisie(z, 60, 140, -251, 6)
	e.or_:SetNumeric(true)

	Etiquette(z, "Onglets de banque", 12, -284)
	local entetes = { { "Nom de l'onglet", 12 }, { "Voir", 196 }, { "Déposer", 246 }, { "Retraits / j", 320 } }
	for _, h in ipairs(entetes) do
		local t = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		t:SetPoint("TOPLEFT", h[2], -302) t:SetText(h[1])
	end
	e.onglets = {}
	for t = 1, 3 do
		local y = -318 - (t - 1) * 26
		e.onglets[t] = {
			nom = Saisie(z, 160, 12, y - 2, 24),
			voir = Case(z, "", 196, y),
			deposer = Case(z, "", 252, y),
			retraits = Saisie(z, 50, 320, y - 2, 4),
		}
		e.onglets[t].retraits:SetNumeric(true)
	end

	local enregistrer = Opus.Bouton(z, "Enregistrer", 140, function ()
		Relever()
		Opus.EnregistrerConfig(brouillon)
		e:Hide()
		Opus.Msg("grille enregistrée et partagée avec les membres qui ont l'addon.")
	end)
	enregistrer:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 110, function () e:Hide() end)
	annuler:SetPoint("RIGHT", enregistrer, "LEFT", -8, 0)
	e:Hide()
end

function Opus.EditerGrade (r)
	if not Opus.PeutConfigurer() then Opus.Msg("seuls le chef et les officiers modifient la grille.") return end
	if InCombatLockdown() then return end
	if not e then Construire() end
	brouillon = Opus.Copie(Opus.Config())
	brouillon.onglets = brouillon.onglets or {}
	brouillon.grades[r] = brouillon.grades[r] or { role = "", sorties = {} }
	rang = r
	Remplir()
	e:Show()
end
