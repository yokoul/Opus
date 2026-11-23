-- RaidInstantane.lua : l'instantané du site, importé par le maître du butin et un second de secours (/opus raid droits)
-- Le site calcule tout (wishlists validées, compteurs normalisés, poids votés, Suicide King) ; l'addon ne fait que le
-- lire pour la soirée. Un nouvel import remplace l'ancien en entier.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local POIDS = { "perso", "perdues", "dernier", "gain" }   -- dans l'ordre de l'enregistrement P

local function Nombre (v, min, max)
	v = tonumber(v)
	if not v or v ~= v or (min and v < min) or (max and v > max) then return nil end
	return v
end

-- Lit les enregistrements d'un instantané. Rend l'instantané, ou nil et la raison. Une lettre inconnue est ignorée :
-- le site peut ajouter des enregistrements sans casser les addons déjà installés.
function Raid.DecoderInstantane (texte)
	local enregistrements, erreur = Raid.Ouvrir(texte, "I")
	if not enregistrements then return nil, erreur end
	local i = { joueurs = {}, souhaits = {}, sk = {}, de = {}, nJoueurs = 0, nObjets = 0 }
	for n, r in ipairs(enregistrements) do
		local lettre = r[1]
		local function Faux (quoi) return nil, "enregistrement " .. n .. " (" .. lettre .. ") : " .. quoi end
		if lettre == "E" then
			if i.id then return Faux("deux en-têtes") end
			i.id, i.tier, i.date, i.tables, i.taille = r[2], r[3], Nombre(r[4], 0), r[5], Nombre(r[6], 1)
			if not i.id or i.id == "" or not i.date then return Faux("en-tête incomplet") end
		elseif lettre == "P" then
			i.poids = {}
			for k, cle in ipairs(POIDS) do
				i.poids[cle] = Nombre(r[k + 1], 0)
				if not i.poids[cle] then return Faux("poids « " .. cle .. " » illisible") end
			end
		elseif lettre == "J" then
			local nom = r[2] and strtrim(r[2])
			if not nom or nom == "" then return Faux("joueur sans nom") end
			if i.joueurs[nom] then return Faux(nom .. " en double") end
			local j = { role = r[3] or "", perdues = Nombre(r[4], 0, 1), dernier = Nombre(r[5], 0, 1), gain = Nombre(r[6], 0, 1),
				perso = r[7] == "reroll" and "reroll" or "main" }
			if not (j.perdues and j.dernier and j.gain) then return Faux("compteurs de " .. nom .. " illisibles (entre 0 et 1)") end
			i.joueurs[nom], i.nJoueurs = j, i.nJoueurs + 1
		elseif lettre == "W" then
			local id = Nombre(r[2], 1)
			if not id then return Faux("objet sans itemID") end
			if i.souhaits[id] then return Faux("objet " .. id .. " en double") end
			local candidats = {}
			for _, c in ipairs(Raid.Liste(r[3])) do
				local nom, rang = c:match("^(.-):(%d+)$")
				if not nom then return Faux("candidat « " .. c .. " » illisible (nom:rang)") end
				candidats[#candidats + 1] = { nom = strtrim(nom), rang = tonumber(rang) }
			end
			i.souhaits[id], i.nObjets = candidats, i.nObjets + 1
		elseif lettre == "S" then
			i.sk = Raid.Liste(r[2])
		elseif lettre == "Z" then
			i.de = Raid.Liste(r[2])
		end
	end
	if not i.id then return nil, "pas d'en-tête" end
	if not i.poids then return nil, "pas de poids" end
	-- un candidat doit être un joueur de l'instantané : sinon ses compteurs manquent
	for id, candidats in pairs(i.souhaits) do
		for _, c in ipairs(candidats) do
			if not i.joueurs[c.nom] then return nil, "objet " .. id .. " : " .. c.nom .. " n'est pas dans les joueurs" end
		end
	end
	for _, nom in ipairs(i.sk) do
		if not i.joueurs[nom] then return nil, "Suicide King : " .. nom .. " n'est pas dans les joueurs" end
	end
	return i
end

-- les noms de l'instantané que le roster ne connaît pas tels quels (faute de frappe sur le site, membre parti…)
function Raid.NomsInconnus (i)
	local connus, inconnus = {}, {}
	for _, m in ipairs(Raid.Membres()) do connus[m.nom] = true end
	local vus = {}
	local function Voir (nom) if not connus[nom] and not vus[nom] then vus[nom] = true inconnus[#inconnus + 1] = nom end end
	for nom in pairs(i.joueurs) do Voir(nom) end
	for _, nom in ipairs(i.de) do Voir(nom) end
	table.sort(inconnus)
	return inconnus
end

-- Les membres du raid (ou du groupe, pour les essais), par leur nom complet : le jeu peut n'y mettre que le prénom,
-- qu'on résout par la guilde comme un expéditeur (un prénom porté par plusieurs membres en ligne reste tel quel,
-- signalé à part).
function Raid.MembresDuRaid ()
	local liste = {}
	local function Ajouter (nom)
		if not nom then return end
		local m = Raid.Identifier(nom, true)
		liste[#liste + 1] = { nom = m and m.nom or Raid.Court(nom), sur = m and true or false }
	end
	if IsInRaid() then
		for n = 1, GetNumGroupMembers() or 0 do Ajouter((GetRaidRosterInfo(n))) end
	elseif IsInGroup() then
		for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
			local prenom, famille = UnitName(u)
			if prenom then Ajouter(famille and famille ~= "" and (prenom .. "-" .. famille) or prenom) end
		end
	end
	return liste
end

-- l'instantané face au raid : ses joueurs absents, les membres du raid sans wishlist, les noms que l'on ne tranche pas
function Raid.FaceAuRaid (i)
	local presents, absents, sans, flous = {}, {}, {}, {}
	for _, m in ipairs(Raid.MembresDuRaid()) do
		presents[m.nom] = true
		if not i.joueurs[m.nom] then
			if m.sur or m.nom:find(" ", 1, true) then sans[#sans + 1] = m.nom else flous[#flous + 1] = m.nom end
		end
	end
	for nom in pairs(i.joueurs) do if not presents[nom] then absents[#absents + 1] = nom end end
	table.sort(absents) table.sort(sans) table.sort(flous)
	return absents, sans, flous
end

-- Rien de tout ça ne bloque : l'instantané couvre toute la guilde, un joueur absent ce soir n'est simplement pas
-- candidat. À l'import, les absents ne sont que comptés ; /opus raid etat les nomme (detail).
local function Signaler (i, detail)
	local inconnus = Raid.NomsInconnus(i)
	if #inconnus > 0 then Msg("|cffffd100pas dans la guilde sous ce nom|r : " .. table.concat(inconnus, ", ") .. ".") end
	if not IsInRaid() then return end
	local absents, sans, flous = Raid.FaceAuRaid(i)
	if #absents > 0 then
		Msg("|cff808080pas dans le raid ce soir|r : " .. (detail and table.concat(absents, ", ") .. "."
			or #absents .. " joueur" .. (#absents > 1 and "s" or "") .. " de l'instantané, pas candidats (/opus raid etat pour les noms)."))
	end
	if #sans > 0 then Msg("|cffffd100dans le raid, sans wishlist|r : " .. table.concat(sans, ", ") .. ".") end
	if #flous > 0 then Msg("|cffff5555prénom porté par plusieurs membres en ligne|r : " .. table.concat(flous, ", ") .. ".") end
end

local function Pluriel (n, mot) return n .. " " .. mot .. (n > 1 and "s" or "") end

local function Resume (i)
	return string.format("instantané %s (%s, du %s) : %s, %s, Suicide King de %d, %s", i.id, i.tier ~= "" and i.tier or "tier ?",
		date("%d/%m %H:%M", i.date), Pluriel(i.nJoueurs, "joueur"), Pluriel(i.nObjets, "objet"), #i.sk, Pluriel(#i.de, "désenchanteur"))
end

function Raid.ImporterInstantane (texte)
	if not Raid.PeutGerer() then Msg("import de l'instantané " .. Raid.QuiPeut() .. ".") return false end
	local i, erreur = Raid.DecoderInstantane(texte)
	if not i then Msg("|cffff5555instantané refusé|r : " .. erreur .. ".") return false end
	i.importe, i.par = time(), Raid.MonNom()
	Raid.db.instantane = i
	Msg(Resume(i) .. ".")
	Signaler(i)
	return true
end

local function Etat ()
	local i = Raid.db.instantane
	if not i then Msg("aucun instantané : un officier colle celui du site avec /opus raid import.") return end
	Msg(Resume(i) .. ", importé le " .. date("%d/%m à %H:%M", i.importe) .. " par " .. (i.par or "?") .. ".")
	Msg(string.format("poids : prio perso %s, prios perdues %s, dernier loot %s, gain %s.", i.poids.perso, i.poids.perdues, i.poids.dernier, i.poids.gain))
	Signaler(i, true)
end

-- les candidats d'un objet, pour vérifier un import (l'itemID, ou l'objet lié en discussion)
local function Objet (texte)
	local i = Raid.db.instantane
	if not i then Msg("aucun instantané importé.") return end
	local id = tonumber(texte) or tonumber((texte or ""):match("item:(%d+)"))
	if not id then Msg("usage : /opus raid objet <itemID ou lien de l'objet>") return end
	local candidats = i.souhaits[id]
	if not candidats or #candidats == 0 then Msg("objet " .. id .. " : aucun candidat en wishlist (Suicide King).") return end
	Msg("objet " .. id .. " : " .. Pluriel(#candidats, "candidat") .. ".")
	for _, c in ipairs(candidats) do
		local j = i.joueurs[c.nom]
		DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (%s, %s) — rang %d, prios perdues %.2f, dernier loot %.2f, gain %.2f",
			c.nom, j.role, j.perso, c.rang, j.perdues, j.dernier, j.gain))
	end
end

------------------------------------------------------------------------
-- la fenêtre d'import : un champ où coller la chaîne (comme /opus import)
------------------------------------------------------------------------

local f

local function Bouton (parent, texte, largeur, clic)
	local b = CreateFrame("Button", nil, parent, "SharedButtonSmallTemplate")
	b:SetSize(largeur, 24) b:SetText(texte) b:SetScript("OnClick", clic)
	return b
end

local function Construire ()
	f = CreateFrame("Frame", "OpusRaidImport", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(460, 190) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Importer l'instantané du site")
	tinsert(UISpecialFrames, "OpusRaidImport")
	local z = f.Inset
	local aide = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	aide:SetPoint("TOPLEFT", 12, -12) aide:SetPoint("TOPRIGHT", -12, -12)
	aide:SetJustifyH("LEFT") aide:SetSpacing(3)
	aide:SetText("Sur le site Opus, la page du raid donne l'instantané de la soirée (une chaîne qui commence par "
		.. NORMAL_FONT_COLOR:WrapTextInColorCode("OLS1:I:") .. ") : copie-le en entier et colle-le ici (Ctrl+V).")
	f.saisie = CreateFrame("EditBox", nil, z, "InputBoxTemplate")
	f.saisie:SetSize(410, 20) f.saisie:SetPoint("TOPLEFT", 18, -60) f.saisie:SetAutoFocus(true)
	f.saisie:SetMaxLetters(0)
	if f.saisie.SetMaxBytes then f.saisie:SetMaxBytes(0) end
	f.etat = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.etat:SetPoint("TOPLEFT", 12, -88)
	f.saisie:SetScript("OnTextChanged", function (self)
		local n = #self:GetText()
		f.etat:SetText(n > 0 and (n .. " caractères collés") or "")
	end)
	f.saisie:SetScript("OnEscapePressed", function () f:Hide() end)
	local ok = Bouton(z, "Importer", 120, function ()
		if Raid.ImporterInstantane(f.saisie:GetText()) then f:Hide() end
	end)
	ok:SetPoint("BOTTOMRIGHT", -12, 12)
	f.saisie:SetScript("OnEnterPressed", function () ok:Click() end)
	local annuler = Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", ok, "LEFT", -8, 0)
	f:Hide()
end

function Raid.OuvrirImport ()
	if not Raid.PeutGerer() then Msg("import de l'instantané " .. Raid.QuiPeut() .. ".") return end
	if not f then Construire() end
	f.saisie:SetText("")
	f:Show()
end

------------------------------------------------------------------------
-- l'essai en donjon : un instantané fabriqué en jeu, pour essayer la soirée à quelques-uns
------------------------------------------------------------------------

-- des candidats imaginaires, comptés présents, pour que la fiche de décision ait de quoi montrer
local FIGURANTS = { { "Essai Rempart", "tank" }, { "Essai Lumière", "heal" }, { "Essai Lame", "dps" }, { "Essai Arcane", "dps" } }

-- un nombre entre 0 et 1, toujours le même pour un même texte
local function Hasard (texte)
	local h = 0
	for k = 1, #texte do h = (h * 31 + texte:byte(k)) % 1000003 end
	return (h % 1000) / 999
end

-- L'instantané d'essai : le groupe et les figurants, des compteurs variés ; chaque objet ramassé a des candidats
-- (RaidScore.lua), tout le monde sauf toi, pour que tu puisses objecter et voter. Son rapport ne part jamais au site.
local function Essai ()
	if not Raid.PeutGerer() then Msg("l'essai " .. Raid.QuiPeut() .. ".") return end
	local moi = Raid.MonNom()
	local i = { id = "essai-donjon-" .. time(), code = "ESSAI", taille = 5, poids = { perso = 50, perdues = 25, dernier = 15, gain = 10 },
		joueurs = {}, souhaits = {}, sk = {}, de = {}, nJoueurs = 0, nObjets = 0, essai = true, importe = time(), par = moi }
	local function Joueur (nom, role)
		if i.joueurs[nom] then return end
		i.joueurs[nom] = { role = role, perdues = Hasard(nom .. "p"), dernier = Hasard(nom .. "d"), gain = Hasard(nom .. "g"), perso = "main" }
		i.nJoueurs = i.nJoueurs + 1
		i.sk[#i.sk + 1] = nom
	end
	for _, m in ipairs(Raid.MembresDuRaid()) do Joueur(m.nom, "dps") end
	Joueur(moi, "dps")
	for _, fig in ipairs(FIGURANTS) do Joueur(fig[1], fig[2]) end
	i.de[1] = moi
	Raid.db.instantane = i
	Msg(string.format("instantané d'essai : %d joueurs (ton groupe et %d figurants). Chaque objet ramassé a des candidats ; "
		.. "rien de cette soirée ne part au site. Mets le seuil de butin du groupe à « Inhabituel », passe maître du butin, "
		.. "puis /opus raid ouvrir. Il remplace l'instantané du site : réimporte-le après (« Du bridge » ou /opus raid import).", i.nJoueurs, #FIGURANTS))
end

-- les candidats d'un objet de l'essai, tirés une fois pour toutes : tout le monde sauf toi, un rang de 1 à 5
function Raid.CandidatsEssai (i, itemID)
	if i.souhaits[itemID] then return i.souhaits[itemID] end
	local moi, liste = Raid.MonNom(), {}
	for nom in pairs(i.joueurs) do
		if nom ~= moi then liste[#liste + 1] = { nom = nom, rang = 1 + math.floor(Hasard(nom .. itemID) * 4.99) } end
	end
	table.sort(liste, function (a, b) return a.nom < b.nom end)
	i.souhaits[itemID], i.nObjets = liste, i.nObjets + 1
	return liste
end

-- les figurants de l'essai comptent comme présents
function Raid.Figurant (nom)
	local i = Raid.db.instantane
	return i and i.essai and nom:sub(1, 6) == "Essai " or false
end

Raid.Commande("essai", "essai", "un instantané d'essai fabriqué en jeu, pour essayer une soirée en donjon à quelques-uns", Essai)
Raid.Commande("import", "import", "coller l'instantané du site (selon /opus raid droits)", function () Raid.OuvrirImport() end)
Raid.Commande("etat", "etat", "l'instantané importé : joueurs, objets, poids, noms inconnus de la guilde, absents du raid", Etat)
Raid.Commande("objet", "objet <itemID>", "les candidats d'un objet dans l'instantané", Objet)
