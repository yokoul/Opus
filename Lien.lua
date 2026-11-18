-- Lien.lua : qui joue quels personnages, d'après le bot Discord de la guilde (ForePlate)
-- Un addon ne lit pas Internet : un modérateur du Discord lance /persoadmin export, un officier colle le code en jeu
-- (/opus import), puis l'addon le partage aux membres de la guilde (« W » : en-tête, « w » : joueurs, « Y » : demande
-- de rattrapage à la connexion). Le code tient sur une ligne :
--   OPUS1!<date>!<nombre de joueurs>!<id Discord>=<pseudo>=<perso>*,<perso>;…!<contrôle>
-- où « * » marque un main. Ces liaisons s'ajoutent aux personnages vus sur un même compte (Cotisation.lua).
local _, Opus = ...

local FS, RS = Opus.FS, Opus.RS
local MAX_JOUEURS, MAX_PERSOS = 1000, 50

------------------------------------------------------------------------
-- les noms : comparés sans casse ni accents (le bot écrit « Éléa », le roster peut écrire « Eléa »)
------------------------------------------------------------------------

local PLI = {}
for lettres, base in pairs({ ["àáâãäåÀÁÂÃÄÅ"] = "a", ["çÇ"] = "c", ["èéêëÈÉÊË"] = "e", ["ìíîïÌÍÎÏ"] = "i", ["ñÑ"] = "n",
	["òóôõöøÒÓÔÕÖØ"] = "o", ["ùúûüÙÚÛÜ"] = "u", ["ýÿÝ"] = "y" }) do
	for l in lettres:gmatch("[\192-\255][\128-\191]*") do PLI[l] = base end
end

local function Pli (nom)
	return (nom:lower():gsub("[\192-\255][\128-\191]*", PLI):gsub("%s+", " "))
end
Opus.Pli = Pli

-- même calcul que le bot (export.py) : somme pondérée des octets, modulo 65521
local function Controle (s)
	local t = 0
	for i = 1, #s do t = (t + s:byte(i) * ((i - 1) % 7 + 1)) % 65521 end
	return ("%04x"):format(t)
end

------------------------------------------------------------------------
-- les données : [guilde] = { t = date de l'export, par = qui l'a importé, joueurs = { [id] = { pseudo, persos } } }
------------------------------------------------------------------------

local index, indexDe = {}, nil       -- [nom plié] = { id, main } ; reconstruit quand les données changent

local function Donnees ()
	local guilde = GetGuildInfo("player")
	return guilde and Opus.db.discord[guilde]
end

local function Indexer ()
	local d = Donnees()
	index, indexDe = {}, d
	if not d then return end
	for id, j in pairs(d.joueurs) do
		for _, p in ipairs(j.persos) do index[Pli(p.nom)] = { id = id, main = p.main } end
	end
end

local function Trouver (nom)
	if not nom or not Opus.db then return nil end
	if indexDe ~= Donnees() then Indexer() end
	return index[Pli(nom)]
end

-- le joueur Discord d'un personnage : { pseudo, persos = { { nom, main } } }, son id, et s'il est un de ses mains
function Opus.Discord (nom)
	local x = Trouver(nom)
	if not x then return nil end
	return Donnees().joueurs[x.id], x.id, x.main
end

function Opus.DiscordId (nom)
	local x = Trouver(nom)
	return x and x.id
end

-- tous les personnages du joueur dans la guilde, mains d'abord : ceux de Discord et ceux vus sur son compte
function Opus.PersosDuJoueur (nom)
	local cle, liste, vus = Opus.Joueur(nom), {}, {}
	local function Ajouter (n, main)
		local m = Opus.TrouverMembre(n) or Opus.TrouverMembreLie(n)
		if m and not vus[m.nom] then vus[m.nom] = true liste[#liste + 1] = { nom = m.nom, main = main, membre = m } end
	end
	local j = Opus.Discord(nom)
	for _, p in ipairs(j and j.persos or {}) do Ajouter(p.nom, p.main) end
	for n in pairs(Opus.db.alts) do if Opus.Joueur(n) == cle then Ajouter(n, false) end end
	Ajouter(nom, false)
	table.sort(liste, function (a, b)
		if a.main ~= b.main then return a.main end
		return a.nom < b.nom
	end)
	return liste
end

-- le main d'un reroll (nil pour un main, ou si on ne le sait pas)
function Opus.MainDe (nom)
	local j, _, main = Opus.Discord(nom)
	if not j or main then return nil end
	for _, p in ipairs(j.persos) do
		local m = p.main and (Opus.TrouverMembre(p.nom) or Opus.TrouverMembreLie(p.nom))
		if m then return m.nom end
	end
	return nil
end

------------------------------------------------------------------------
-- lire un code
------------------------------------------------------------------------

local function Propre (s) return (s:gsub("[;~:=,!*|]", " "):gsub("^%s+", ""):gsub("%s+$", "")) end

-- renvoie { t, joueurs } ou nil et la raison
local function Lire (code)
	code = (code or ""):gsub("`", ""):gsub("%s+$", ""):gsub("^%s+", "")
	local corps, controle = code:match("^(.*)!(%x%x%x%x)$")
	if not corps then return nil, "ce n'est pas un code d'export du bot (/persoadmin export)." end
	if Controle(corps) ~= controle:lower() then return nil, "code incomplet ou modifié : recopie-le en entier." end
	local t, n, liste = corps:match("^OPUS1!(%d+)!(%d+)!(.*)$")
	if not t then return nil, "version du code inconnue : mets l'addon à jour." end
	local joueurs, compte = {}, 0
	for r in liste:gmatch("[^;]+") do
		local id, pseudo, noms = r:match("^(%d+)=([^=]*)=(.+)$")
		if id and compte < MAX_JOUEURS then
			local j = { pseudo = Propre(pseudo) ~= "" and Propre(pseudo) or "?", persos = {} }
			for x in noms:gmatch("[^,]+") do
				local main = x:sub(-1) == "*"
				local nom = Propre(main and x:sub(1, -2) or x)
				if nom ~= "" and #j.persos < MAX_PERSOS then j.persos[#j.persos + 1] = { nom = nom, main = main } end
			end
			if #j.persos > 0 then joueurs[id] = j compte = compte + 1 end
		end
	end
	if compte ~= tonumber(n) then return nil, ("le code annonce %s joueur(s), %d lu(s) : recopie-le en entier."):format(n, compte) end
	return { t = tonumber(t), joueurs = joueurs }
end

------------------------------------------------------------------------
-- partage
------------------------------------------------------------------------

-- les joueurs en enregistrements « i:id=pseudo=persos » ; un joueur aux nombreux persos prend plusieurs enregistrements
local function Enregistrements (d)
	local liste = {}
	for id, j in pairs(d.joueurs) do
		local debut, noms, long = id .. "=" .. j.pseudo .. "=", {}, 0
		for _, p in ipairs(j.persos) do
			local x = p.nom .. (p.main and "*" or "")
			if #noms > 0 and #debut + long + #x > 170 then
				liste[#liste + 1] = debut .. table.concat(noms, ",")
				noms, long = {}, 0
			end
			noms[#noms + 1] = x
			long = long + #x + 1
		end
		liste[#liste + 1] = debut .. table.concat(noms, ",")
	end
	return liste
end

local function Partager (d)
	if not IsInGuild() or not d then return end
	local liste = Enregistrements(d)
	Opus.Envoyer(table.concat({ "W", d.t, #liste, Opus.MotMsg(d.par or "", 48) }, FS))
	local entete = "w" .. FS .. d.t
	local message = entete
	for i, r in ipairs(liste) do
		local x = i .. ":" .. r
		if #message + 1 + #x > Opus.MAX_MSG then Opus.Envoyer(message) message = entete end
		message = message .. RS .. x
	end
	if message ~= entete then Opus.Envoyer(message) end
end

local enCours = {}     -- [t] = { n, par, recus = { [i] = enregistrement } }

local function Complet (t)
	local r = enCours[t]
	if not r or not r.n then return end
	for i = 1, r.n do if not r.recus[i] then return end end
	enCours[t] = nil
	local locale = Donnees()
	if locale and locale.t >= t then return end
	-- importé par quelqu'un qui en a le droit (chef ou officier)
	local auteur = r.par and Opus.TrouverMembre(r.par)
	if not auteur or not Opus.PeutConfigurer(auteur.grade) then return end
	local d = { t = t, par = r.par, joueurs = {} }
	for i = 1, r.n do
		local id, pseudo, noms = r.recus[i]:match("^(%d+)=([^=]*)=(.+)$")
		if id then
			local j = d.joueurs[id] or { pseudo = Propre(pseudo), persos = {} }
			d.joueurs[id] = j
			for nom in noms:gmatch("[^,]+") do
				local main = nom:sub(-1) == "*"
				if #j.persos < MAX_PERSOS then j.persos[#j.persos + 1] = { nom = Propre(main and nom:sub(1, -2) or nom), main = main } end
			end
		end
	end
	Opus.db.discord[GetGuildInfo("player")] = d
	Indexer()
	Opus.Msg(("liaisons Discord mises à jour (export du %s, importé par %s)."):format(date("%d/%m %H:%M", t), r.par))
	if Opus.Rafraichir then Opus.Rafraichir() end
end

Opus.recepteurs.W = function (_, champs, _, canal)
	local t, n = tonumber(champs[2]), tonumber(champs[3])
	if canal ~= "GUILD" or not t or not n or n < 1 or n > MAX_JOUEURS * 3 then return end
	local r = enCours[t] or { recus = {} }
	enCours[t] = r
	r.n, r.par = n, champs[4] ~= "" and champs[4] or nil
	Complet(t)
end

Opus.recepteurs.w = function (enregistrements, champs, _, canal)
	local t = tonumber(champs[2])
	if canal ~= "GUILD" or not t then return end
	local r = enCours[t] or { recus = {} }
	enCours[t] = r
	for i = 2, #enregistrements do
		local k, x = enregistrements[i]:match("^(%d+):(.+)$")
		if k then r.recus[tonumber(k)] = x end
	end
	Complet(t)
end

-- une demande de rattrapage : qui a un export plus récent le renvoie
Opus.recepteurs.Y = function (_, champs, _, canal)
	local d, t = Donnees(), tonumber(champs[2]) or 0
	if canal ~= "GUILD" or not d or d.t <= t then return end
	Opus.Repondre(champs[3], "GUILD", function () Partager(Donnees()) end)
end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(30, function ()
		if not IsInGuild() then return end
		local d = Donnees()
		Opus.Envoyer(table.concat({ "Y", d and d.t or 0, Opus.NouvelId() }, FS))
	end)
end)

------------------------------------------------------------------------
-- importer
------------------------------------------------------------------------

function Opus.ImporterDiscord (code)
	if not Opus.PeutConfigurer() then Opus.Msg("seuls le chef et les officiers importent les liaisons Discord.") return false end
	local d, raison = Lire(code)
	if not d then Opus.Msg("import refusé : " .. raison) return false end
	local locale = Donnees()
	if locale and locale.t > d.t then
		Opus.Msg(("import refusé : la guilde a déjà un export plus récent (du %s)."):format(date("%d/%m %H:%M", locale.t)))
		return false
	end
	d.par = Opus.MonNom()
	Opus.db.discord[GetGuildInfo("player")] = d
	Indexer()
	local joueurs, persos, dansLaGuilde = 0, 0, 0
	for _, j in pairs(d.joueurs) do
		joueurs = joueurs + 1
		for _, p in ipairs(j.persos) do
			persos = persos + 1
			if Opus.TrouverMembre(p.nom) or Opus.TrouverMembreLie(p.nom) then dansLaGuilde = dansLaGuilde + 1 end
		end
	end
	Opus.Msg(("%d joueur(s), %d perso(s) importés, dont %d dans la guilde ; partage aux membres en cours."):format(joueurs, persos, dansLaGuilde))
	Partager(d)
	if Opus.Rafraichir then Opus.Rafraichir() end
	return true
end

-- un membre du roster sous un nom écrit autrement (casse, accents)
function Opus.TrouverMembreLie (nom)
	local cle = Pli(nom)
	for _, m in ipairs(Opus.Membres()) do if Pli(m.nom) == cle then return m end end
	return nil
end

-- l'état des liaisons, en clair
local function Etat ()
	local d = Donnees()
	if not d then
		Opus.Msg("aucune liaison Discord : un officier colle le code de /persoadmin export avec /opus import.")
		return
	end
	local lies, total = 0, 0
	for _, m in ipairs(Opus.Membres()) do
		total = total + 1
		if Opus.DiscordId(m.nom) then lies = lies + 1 end
	end
	local joueurs = 0
	for _ in pairs(d.joueurs) do joueurs = joueurs + 1 end
	Opus.Msg(("liaisons Discord : export du %s (importé par %s), %d joueur(s) ; %d membre(s) sur %d reliés."):format(
		date("%d/%m/%Y %H:%M", d.t), d.par or "?", joueurs, lies, total))
end

------------------------------------------------------------------------
-- la fenêtre d'import : un champ où coller le code
------------------------------------------------------------------------

local f

local function Construire ()
	f = CreateFrame("Frame", "OpusImport", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(460, 190) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Importer les liaisons Discord")
	tinsert(UISpecialFrames, "OpusImport")
	local z = f.Inset
	local aide = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	aide:SetPoint("TOPLEFT", 12, -12) aide:SetPoint("TOPRIGHT", -12, -12)
	aide:SetJustifyH("LEFT") aide:SetSpacing(3)
	aide:SetText("Sur Discord, " .. Opus.Normal("/persoadmin export") .. " donne un code (ou un fichier) : copie-le en entier "
		.. "et colle-le ici (Ctrl+V). L'addon le partage ensuite aux membres de la guilde.")
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
	local ok = Opus.Bouton(z, "Importer", 120, function ()
		if Opus.ImporterDiscord(f.saisie:GetText()) then f:Hide() end
	end)
	ok:SetPoint("BOTTOMRIGHT", -12, 12)
	f.saisie:SetScript("OnEnterPressed", function () ok:Click() end)
	local annuler = Opus.Bouton(z, "Annuler", 100, function () f:Hide() end)
	annuler:SetPoint("RIGHT", ok, "LEFT", -8, 0)
	f:Hide()
end

function Opus.OuvrirImport ()
	if not Opus.PeutConfigurer() then Opus.Msg("seuls le chef et les officiers importent les liaisons Discord.") return end
	if not f then Construire() end
	f.saisie:SetText("")
	f:Show()
end

Opus.Commande("import", "import", "coller le code de /persoadmin export (Discord) : qui joue quels persos (chef et officiers)", function () Opus.OuvrirImport() end)
Opus.Commande("discord", "discord", "état des liaisons Discord (date de l'export, membres reliés)", Etat)
