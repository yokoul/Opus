-- Notes.lua : des notes de l'addon, sans la limite de 31 caractères du jeu
-- Note publique : visible de tous les membres qui ont l'addon, écrite par le chef, les officiers, ou le joueur lui-même
-- (sur ses personnages). Note d'officier : écrite et lue par le chef et les officiers seuls ; elle passe par le canal
-- d'addon des officiers, que le jeu ne remet qu'à eux, et un joueur qui n'est plus officier l'efface de ses données.
-- Messages : « N » (une note, en morceaux), « n » (demande de rattrapage à la connexion).
local _, Opus = ...

local FS, RS = Opus.FS, Opus.RS
local MAX_NOTE = 1000              -- octets
local RATTRAPAGE_MAX = 100         -- notes renvoyées au plus pour une demande
local CANAL = { p = "GUILD", o = "OFFICER" }

local function Notes ()
	local guilde = GetGuildInfo("player")
	if not guilde then return nil end
	local n = Opus.db.notes[guilde] or { p = {}, o = {} }
	Opus.db.notes[guilde] = n
	return n
end

-- la note d'un personnage : { x = texte, par, t } ; genre « p » (publique) ou « o » (officier)
function Opus.Note (genre, nom)
	local n = Notes()
	if not n or (genre == "o" and not Opus.PeutConfigurer()) then return nil end
	local note = n[genre][nom]
	return note and note.x ~= "" and note or nil
end

-- un de ses personnages ? (vu sur ce compte, ou le même joueur)
local function AMoi (nom)
	local moi = Opus.MonNom()
	return nom == moi or Opus.Joueur(nom) == Opus.Joueur(moi)
end

-- l'auteur peut-il écrire cette note ? (auteur = membre du roster)
local function Permis (genre, nom, auteur)
	if Opus.PeutConfigurer(auteur.grade) then return true end
	return genre == "p" and (auteur.nom == nom or Opus.Joueur(auteur.nom) == Opus.Joueur(nom))
end

function Opus.PeutNoter (genre, nom)
	if Opus.PeutConfigurer() then return true end
	return genre == "p" and AMoi(nom)
end

------------------------------------------------------------------------
-- encodage : le texte est échappé (« % », séparateurs, retours à la ligne) puis coupé en morceaux
------------------------------------------------------------------------

local function Echapper (s) return (s:gsub("[%%;~|\n\r]", function (c) return ("%%%02X"):format(c:byte()) end)) end
local function Rendre (s) return (s:gsub("%%(%x%x)", function (h) return string.char(tonumber(h, 16)) end)) end

-- coupe un texte en morceaux dont la version échappée tient dans place octets, sans casser une lettre
local function Morceaux (texte, place)
	local liste, courant = {}, ""
	for lettre in texte:gmatch("[%z\1-\127\192-\255][\128-\191]*") do
		local e = Echapper(lettre)
		if #courant + #e > place then liste[#liste + 1] = courant courant = "" end
		courant = courant .. e
	end
	if courant ~= "" or #liste == 0 then liste[#liste + 1] = courant end
	return liste
end

local function Partager (genre, nom, note)
	if not IsInGuild() then return end
	local debut = table.concat({ "N", genre, Opus.MotMsg(nom, 48), note.t, Opus.MotMsg(note.par or "", 48) }, FS)
	local morceaux = Morceaux(note.x, Opus.MAX_MSG - #debut - 8)
	for i, m in ipairs(morceaux) do
		Opus.Envoyer(table.concat({ debut, i, #morceaux, m }, FS), CANAL[genre])
	end
end

------------------------------------------------------------------------
-- écrire
------------------------------------------------------------------------

function Opus.Noter (genre, nom, texte)
	if not Opus.PeutNoter(genre, nom) then Opus.Msg("tu ne peux pas modifier cette note.") return end
	texte = strtrim(texte or "")
	if #texte > MAX_NOTE then texte = texte:sub(1, MAX_NOTE):gsub("[\192-\255][\128-\191]*$", "") end
	local n = Notes()
	if not n then return end
	local note = { x = texte, par = Opus.MonNom(), t = time() }
	n[genre][nom] = note
	Partager(genre, nom, note)
	if Opus.Rafraichir then Opus.Rafraichir() end
end

------------------------------------------------------------------------
-- recevoir
------------------------------------------------------------------------

local enCours = {}      -- [clé] = { n, morceaux }

local function Retenir (genre, nom, note)
	local n = Notes()
	if not n then return false end
	local locale = n[genre][nom]
	if locale and locale.t >= note.t then return false end
	n[genre][nom] = note
	return true
end

Opus.recepteurs.N = function (_, champs, _, canal)
	local genre, nom, t, par, i, total, morceau = champs[2], champs[3], tonumber(champs[4]), champs[5], tonumber(champs[6]), tonumber(champs[7]), champs[8] or ""
	if not CANAL[genre] or canal ~= CANAL[genre] or not nom or nom == "" or not t or not i or not total or total < 1 or total > 20 then return end
	if genre == "o" and not Opus.PeutConfigurer() then return end
	if t > time() + 86400 then return end
	local cle = table.concat({ genre, nom, t, par }, FS)
	local r = enCours[cle] or { morceaux = {} }
	enCours[cle] = r
	r.morceaux[i] = morceau
	for k = 1, total do if not r.morceaux[k] then return end end
	enCours[cle] = nil
	-- écrite par quelqu'un qui en a le droit, sur un membre de la guilde
	local auteur, cible = Opus.TrouverMembre(par), Opus.TrouverMembre(nom)
	if not auteur or not cible or not Permis(genre, nom, auteur) then return end
	local texte = Rendre(table.concat(r.morceaux, "", 1, total))
	if #texte > MAX_NOTE then return end
	if Retenir(genre, nom, { x = texte, par = par, t = t }) and Opus.Rafraichir then Opus.Rafraichir() end
end

-- une demande de rattrapage : on renvoie les notes plus récentes que la plus récente du demandeur
Opus.recepteurs.n = function (_, champs, _, canal)
	local genre, depuis, rid = champs[2], tonumber(champs[3]) or 0, champs[4]
	if not CANAL[genre] or canal ~= CANAL[genre] or (genre == "o" and not Opus.PeutConfigurer()) then return end
	local n = Notes()
	if not n then return end
	local choix = {}
	for nom, note in pairs(n[genre]) do
		-- une heure de marge : les horloges des joueurs ne sont pas toutes à l'heure
		if note.t > depuis - 3600 and Opus.TrouverMembre(nom) then choix[#choix + 1] = { nom = nom, note = note } end
	end
	if #choix == 0 then return end
	table.sort(choix, function (a, b) return a.note.t > b.note.t end)
	while #choix > RATTRAPAGE_MAX do table.remove(choix) end
	Opus.Repondre(rid, CANAL[genre], function ()
		for _, c in ipairs(choix) do Partager(genre, c.nom, c.note) end
	end)
end

local function Demander (genre)
	local n = Notes()
	if not n then return end
	local plusRecente = 0
	for _, note in pairs(n[genre]) do plusRecente = math.max(plusRecente, note.t) end
	Opus.Envoyer(table.concat({ "n", genre, plusRecente, Opus.NouvelId() }, FS), CANAL[genre])
end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(40, function ()
		if not IsInGuild() then return end
		Demander("p")
		local _, _, rang = GetGuildInfo("player")
		if Opus.PeutConfigurer() then
			Demander("o")
		elseif rang then
			-- plus officier : ses notes d'officier ne restent pas dans ses données
			local n = Notes()
			if n and next(n.o) then n.o = {} end
		end
	end)
end)

------------------------------------------------------------------------
-- l'éditeur : un champ de plusieurs lignes
------------------------------------------------------------------------

local f

local function Construire ()
	f = CreateFrame("Frame", "OpusNote", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(440, 300) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OpusNote")
	local z = f.Inset
	f.aide = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.aide:SetPoint("TOPLEFT", 12, -10) f.aide:SetPoint("TOPRIGHT", -12, -10) f.aide:SetJustifyH("LEFT")

	local fond = CreateFrame("Frame", nil, z, "InsetFrameTemplate")
	fond:SetPoint("TOPLEFT", 10, -30) fond:SetPoint("BOTTOMRIGHT", -10, 44)
	local defile = CreateFrame("ScrollFrame", nil, fond)
	defile:SetPoint("TOPLEFT", 6, -6) defile:SetPoint("BOTTOMRIGHT", -6, 6)
	local s = CreateFrame("EditBox", nil, defile)
	s:SetMultiLine(true) s:SetAutoFocus(false) s:SetFontObject("ChatFontNormal")
	s:SetWidth(390) s:SetMaxBytes(MAX_NOTE + 1)
	s:SetScript("OnEscapePressed", EditBox_ClearFocus)
	defile:SetScrollChild(s)
	defile:EnableMouse(true)
	defile:SetScript("OnMouseDown", function () s:SetFocus() end)
	defile:SetScript("OnMouseWheel", function (self, d)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 20)))
	end)
	-- le curseur reste visible quand le texte dépasse
	s:SetScript("OnCursorChanged", function (self, _, y, _, h)
		local haut, vue = -y, defile:GetHeight()
		if haut < defile:GetVerticalScroll() then defile:SetVerticalScroll(haut)
		elseif haut + h > defile:GetVerticalScroll() + vue then defile:SetVerticalScroll(haut + h - vue) end
	end)
	f.compte = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.compte:SetPoint("BOTTOMLEFT", 14, 18)
	s:SetScript("OnTextChanged", function (self) f.compte:SetText(#self:GetText() .. " / " .. MAX_NOTE) end)
	f.saisie = s

	local ok = Opus.Bouton(z, "Enregistrer", 130, function ()
		Opus.Noter(f.genre, f.nom, f.saisie:GetText())
		f:Hide()
	end)
	ok:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", ok, "LEFT", -8, 0)
	f:Hide()
end

function Opus.EditerNote (genre, nom)
	if not Opus.PeutNoter(genre, nom) then return end
	if not f then Construire() end
	f.genre, f.nom = genre, nom
	f:SetTitle((genre == "o" and "Note d'officier : " or "Note publique : ") .. nom)
	f.aide:SetText(genre == "o" and "Lue par le chef et les officiers seuls (canal des officiers)."
		or "Lue par tous les membres qui ont l'addon. Laisser vide pour l'effacer.")
	local note = Opus.Note(genre, nom)
	f.saisie:SetText(note and note.x or "")
	f:Show()
	f.saisie:SetFocus()
	f.saisie:SetCursorPosition(#f.saisie:GetText())
end
