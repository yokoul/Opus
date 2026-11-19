-- Niveaux.lua : les montées de niveau des membres de la guilde. L'addon relève le roster chaque minute et note chaque
-- niveau gagné depuis le relevé précédent ; il l'annonce dans la discussion (le niveau 60 aussi au milieu de l'écran).
-- Un niveau vu juste après un relevé récent est daté à la minute près ; vu après une absence (le joueur a monté pendant
-- qu'on n'était pas connecté), il est seulement « vu le » et n'est pas annoncé.
-- Les dates passent d'un membre à l'autre : « L » (des montées), « l » (demande de rattrapage à la connexion).
local _, Opus = ...

local FS, RS = Opus.FS, Opus.RS
local NIVEAU_MAX = 60
local PRECIS = 15 * 60            -- un relevé précédent plus ancien : la montée n'est plus datée précisément
local RATTRAPAGE_MAX = 300        -- montées renvoyées au plus pour une demande

local function Donnees ()
	local guilde = GetGuildInfo("player")
	if not guilde or not Opus.db then return nil end
	local d = Opus.db.niveaux[guilde] or { suivi = {}, dings = {} }
	Opus.db.niveaux[guilde] = d
	return d
end

-- retient une montée : une date précise l'emporte sur une date approchée, et la plus ancienne des deux sinon
local function Retenir (d, nom, niveau, t, approche)
	local liste = d.dings[nom] or {}
	d.dings[nom] = liste
	local e = liste[niveau]
	if e then
		local avant, nouvelle = e.a == true, approche == true
		if not ((avant and not nouvelle) or (avant == nouvelle and t < e.t)) then return false end
	end
	liste[niveau] = { t = t, a = approche or nil }
	return true
end

-- les montées d'un membre, du plus haut niveau au plus bas : { { niveau, t, approche } }
function Opus.Montees (nom)
	local d = Donnees()
	local liste = {}
	for niveau, e in pairs(d and d.dings[nom] or {}) do liste[#liste + 1] = { niveau = niveau, t = e.t, approche = e.a } end
	table.sort(liste, function (a, b) return a.niveau > b.niveau end)
	return liste
end

------------------------------------------------------------------------
-- annonces : réglables par /opus niveaux (tous, 60, aucun)
------------------------------------------------------------------------

local function Annoncer (m, niveau)
	local mode = Opus.db.annonceNiveaux or "tous"
	if mode == "aucun" or (mode == "60" and niveau < NIVEAU_MAX) then return end
	local nom = Opus.Couleur(m.classe) .. m.nom .. "|r"
	if niveau >= NIVEAU_MAX then
		Opus.Msg(("%s |cffffd100atteint le niveau %d ! Félicitations !|r"):format(nom, niveau))
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, ("%s atteint le niveau %d !"):format(nom, niveau), ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 })
		end
		pcall(PlaySound, 888)       -- le son de montée de niveau
	else
		Opus.Msg(("%s passe niveau %d."):format(nom, niveau))
	end
end

------------------------------------------------------------------------
-- relevé du roster
------------------------------------------------------------------------

function Opus.ReleverNiveaux ()
	local d = Donnees()
	if not d then return end
	local maintenant, moi = time(), Opus.MonNom()
	for _, m in ipairs(Opus.Membres()) do
		local niveau, s = tonumber(m.niveau), d.suivi[m.nom]
		if niveau and niveau > 0 then
			if s and niveau > s.n and niveau <= NIVEAU_MAX then
				local precis = maintenant - s.t <= PRECIS
				for n = s.n + 1, niveau do Retenir(d, m.nom, n, maintenant, not precis) end
				if precis and m.nom ~= moi then Annoncer(m, niveau) end
			end
			d.suivi[m.nom] = { n = niveau, t = maintenant }
		end
	end
end

------------------------------------------------------------------------
-- partage : rattrapage à la connexion
------------------------------------------------------------------------

local function Encoder (nom, niveau, e)
	return table.concat({ (Opus.MotMsg(nom, 48):gsub(":", " ")), niveau, e.t, e.a and 1 or 0 }, ":")
end

local function Envoyer (liste)
	local entete = "L"
	local message = entete
	for _, x in ipairs(liste) do
		local r = Encoder(x.nom, x.niveau, x.e)
		if #message + 1 + #r > Opus.MAX_MSG then Opus.Envoyer(message) message = entete end
		message = message .. RS .. r
	end
	if message ~= entete then Opus.Envoyer(message) end
end

Opus.recepteurs.L = function (enregistrements, _, _, canal)
	local d = Donnees()
	if canal ~= "GUILD" or not d then return end
	local limite, change = time() + 86400, false
	for i = 2, #enregistrements do
		local nom, niveau, t, a = strsplit(":", enregistrements[i])
		niveau, t = tonumber(niveau), tonumber(t)
		-- un membre de la guilde, un niveau qu'il a déjà atteint, une date vraisemblable
		local m = nom and Opus.TrouverMembre(nom)
		if m and niveau and t and niveau >= 2 and niveau <= math.min(NIVEAU_MAX, m.niveau) and t <= limite then
			change = Retenir(d, m.nom, niveau, t, a == "1") or change
		end
	end
	if change and Opus.Rafraichir then Opus.Rafraichir() end
end

local function PlusRecente (d)
	local t = 0
	for _, liste in pairs(d.dings) do for _, e in pairs(liste) do t = math.max(t, e.t) end end
	return t
end

-- une demande : qui a des montées plus récentes que la plus récente du demandeur les renvoie
Opus.recepteurs.l = function (_, champs, _, canal)
	local d, depuis = Donnees(), tonumber(champs[2]) or 0
	if canal ~= "GUILD" or not d or PlusRecente(d) <= depuis then return end
	local choix = {}
	for nom, liste in pairs(d.dings) do
		-- une heure de marge : les horloges des joueurs ne sont pas toutes à l'heure
		for niveau, e in pairs(liste) do
			if e.t > depuis - 3600 then choix[#choix + 1] = { nom = nom, niveau = niveau, e = e } end
		end
	end
	table.sort(choix, function (a, b) return a.e.t > b.e.t end)
	while #choix > RATTRAPAGE_MAX do table.remove(choix) end
	Opus.Repondre(champs[3], "GUILD", function () Envoyer(choix) end)
end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	-- le roster est relu chaque minute : c'est ce qui date les montées
	C_Timer.NewTicker(60, function () if IsInGuild() then Opus.DemanderListe() end end)
	C_Timer.After(50, function ()
		local d = Donnees()
		if d then Opus.Envoyer(table.concat({ "l", PlusRecente(d), Opus.NouvelId() }, FS)) end
	end)
end)

Opus.Ecoute("GUILD_ROSTER_UPDATE", function () Opus.ReleverNiveaux() end)

Opus.Commande("niveaux", "niveaux [tous|60|aucun]", "annonce des montées de niveau de la guilde : toutes, le 60 seulement, ou aucune", function (reste)
	reste = (reste or ""):lower()
	if reste == "tous" or reste == "60" or reste == "aucun" then Opus.db.annonceNiveaux = reste end
	local mode = Opus.db.annonceNiveaux or "tous"
	Opus.Msg("annonce des montées de niveau : " .. (mode == "tous" and "toutes" or mode == "60" and "le niveau 60 seulement" or "aucune") ..
		Opus.Gris(" (/opus niveaux tous, 60 ou aucun)"))
end)
