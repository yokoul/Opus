-- Journal.lua : arrivées, départs et changements de grade, relevés dans le journal de guilde du serveur
-- Comme celui de la banque, ce journal ne garde que les derniers événements, datés « il y a N heures ». Tout membre
-- peut le lire (sans passer à la banque) : l'addon le relève à la connexion puis régulièrement, et fusionne les
-- relevés dans un historique qui, lui, ne s'efface pas (un an).
local _, Opus = ...

local CONSERVATION = 400 * 24          -- en heures
local TYPES = { invite = true, join = true, promote = true, demote = true, remove = true, quit = true }

local function Maintenant () return math.floor(time() / 3600) end
local function IlYA (an, mois, jour, heure) return ((an or 0) * 365 + (mois or 0) * 30 + (jour or 0)) * 24 + (heure or 0) end

-- la signature laisse de côté le second nom : le jeu ne le donne pas toujours (« ? » tant que le client ne connaît pas
-- ce joueur), et un relevé suivant peut l'apporter
local function Signature (e) return table.concat({ e.q, e.a or "", e.g or "" }, "|") end

-- même fusion que pour la banque : un événement déjà vu (même type, mêmes noms, même grade, à une heure près) ne
-- revient pas ; s'il lui manquait le second nom et que ce relevé l'a, on le complète
local function Fusionner (lus)
	local evenements, index, pris, n = Opus.db.journal.evenements, {}, {}, 0
	for _, e in ipairs(evenements) do
		local s = Signature(e)
		index[s] = index[s] or {}
		table.insert(index[s], e)
	end
	local function Trouver (e, exact)
		for _, v in ipairs(index[Signature(e)] or {}) do
			if not pris[v] and math.abs(v.t - e.t) <= 1 then
				if (exact and v.b == e.b) or (not exact and (v.b == nil or e.b == nil)) then return v end
			end
		end
	end
	for _, e in ipairs(lus) do
		local trouve = Trouver(e, true) or Trouver(e, false)
		if trouve then
			if not trouve.b and e.b then trouve.b = e.b n = n + 1 end
		else
			table.insert(evenements, e)
			local s = Signature(e)
			index[s] = index[s] or {}
			table.insert(index[s], e)
			trouve, n = e, n + 1
		end
		pris[trouve] = true
	end
	return n
end

function Opus.ReleverJournal ()
	if not (GetNumGuildEvents and GetGuildEventInfo) or not Opus.db then return 0 end
	local maintenant, lus = Maintenant(), {}
	for i = 1, GetNumGuildEvents() or 0 do
		local q, a, b, grade, an, mois, jour, heure = GetGuildEventInfo(i)
		if TYPES[q] and a then
			lus[#lus + 1] = { t = maintenant - IlYA(an, mois, jour, heure), q = q, a = Opus.Court(a), b = b and Opus.Court(b), g = grade }
		end
	end
	local n = Fusionner(lus)
	local limite, garde = maintenant - CONSERVATION, {}
	for _, e in ipairs(Opus.db.journal.evenements) do
		if e.t >= limite then garde[#garde + 1] = e end
	end
	Opus.db.journal.evenements = garde
	Opus.db.journal.releve = time()
	if n > 0 and Opus.Rafraichir then Opus.Rafraichir() end
	return n
end

-- le serveur répond par GUILD_EVENT_LOG_UPDATE ; on redemande toutes les 10 minutes tant qu'on est en guilde
function Opus.DemanderJournal ()
	if IsInGuild() and QueryGuildEventLog then QueryGuildEventLog() end
end
Opus.Ecoute("GUILD_EVENT_LOG_UPDATE", function () Opus.ReleverJournal() end)
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if Opus.journalLance then return end
	Opus.journalLance = true
	C_Timer.After(10, Opus.DemanderJournal)
	C_Timer.NewTicker(600, Opus.DemanderJournal)
end)

------------------------------------------------------------------------
-- lecture
------------------------------------------------------------------------

-- l'arrivée la plus récente d'un membre (en secondes), pour dater un essai sans note d'officier
function Opus.ArriveeJournal (nom)
	local t
	for _, e in ipairs(Opus.db.journal.evenements) do
		if e.q == "join" and e.a == nom and (not t or e.t > t) then t = e.t end
	end
	return t and t * 3600
end

-- quand un membre est passé à ce grade (promotion ou rétrogradation la plus récente vers lui), en secondes
function Opus.PassageJournal (nom, grade)
	local t
	for _, e in ipairs(Opus.db.journal.evenements) do
		if (e.q == "promote" or e.q == "demote") and e.b == nom and e.g == grade and (not t or e.t > t) then t = e.t end
	end
	return t and t * 3600
end

-- les événements, du plus récent au plus ancien ; filtre : "tout", "mouvements" (arrivées, départs) ou "grades"
local FILTRES = {
	mouvements = { invite = true, join = true, remove = true, quit = true },
	grades = { promote = true, demote = true },
}
function Opus.Evenements (filtre)
	local liste, f = {}, FILTRES[filtre]
	for _, e in ipairs(Opus.db.journal.evenements) do
		if not f or f[e.q] then liste[#liste + 1] = e end
	end
	table.sort(liste, function (x, y) return x.t > y.t end)
	return liste
end

-- un événement en clair ; nom(n) colore un nom (classe des membres encore là)
function Opus.Phrase (e, nom)
	local a, b = nom(e.a), e.b and nom(e.b) or Opus.Gris("(nom inconnu du jeu)")
	if e.q == "join" then return Opus.Vert("Arrivée") .. " · " .. a .. " rejoint la guilde"
	elseif e.q == "invite" then return Opus.Gris("Invitation") .. " · " .. b .. " invité par " .. a
	elseif e.q == "promote" then return Opus.Normal("Promotion") .. " · " .. b .. " passe " .. Opus.Blanc(e.g or "?") .. ", par " .. a
	elseif e.q == "demote" then return Opus.Gris("Rétrogradation") .. " · " .. b .. " passe " .. Opus.Blanc(e.g or "?") .. ", par " .. a
	elseif e.q == "remove" then return Opus.Rouge("Renvoi") .. " · " .. b .. " renvoyé par " .. a
	elseif e.q == "quit" then return Opus.Rouge("Départ") .. " · " .. a .. " quitte la guilde" end
	return e.q
end

Opus.Commande("journal", "journal", "ouvre la fenêtre sur le journal de guilde (arrivées, départs, grades)", function ()
	Opus.DemanderJournal()
	Opus.OuvrirGuilde("tout")
end)
