-- Cotisation.lua : la cotisation hebdomadaire, volontaire, qui finance les onglets de banque et les recettes rares
-- Le barème est par personnage, selon son niveau, plafonné par joueur (tous ses personnages ensemble). L'addon reconnaît
-- les personnages d'un même joueur : ses données sont par compte, donc il voit ceux qui se connectent sur ce compte ; chaque
-- joueur qui a l'addon partage sa liste (Partage.lua, « M »). La semaine part du reset européen, le mercredi à 4 h UTC.
local _, Opus = ...

-- barème d'Opus (cuivre) ; une autre guilde n'a pas de cotisation tant qu'elle n'en définit pas
Opus.COTISATION_OPUS = {
	tranches = { { min = 1, max = 19, montant = 0 }, { min = 20, max = 39, montant = 5000 }, { min = 40, max = 59, montant = 10000 }, { min = 60, max = 60, montant = 20000 } },
	plafond = 30000,
}

function Opus.Cotisation ()
	-- réglée dans la grille (Reglages.lua) : active ou non ; sinon, le barème d'Opus chez Opus
	local c = Opus.Config()
	if c and c.cotisation then return c.cotisation.actif and c.cotisation or nil end
	if GetGuildInfo("player") == "Opus" then return Opus.COTISATION_OPUS end
	return nil
end

-- début de la semaine en cours (secondes) : le dernier mercredi à 4 h UTC (le 1er janvier 1970 était un jeudi)
function Opus.DebutSemaine ()
	local jours = math.floor((time() - 4 * 3600) / 86400)
	local depuisMercredi = (jours - 6) % 7
	return (jours - depuisMercredi) * 86400 + 4 * 3600
end

-- ce que doit un personnage, selon son niveau
function Opus.DuPerso (niveau)
	local c = Opus.Cotisation()
	if not c then return 0 end
	for _, t in ipairs(c.tranches) do
		if niveau >= t.min and niveau <= t.max then return t.montant end
	end
	return 0
end

------------------------------------------------------------------------
-- les personnages d'un même joueur
------------------------------------------------------------------------

-- le joueur d'un personnage : son compte Discord s'il est relié (Lien.lua), y compris par un autre personnage du
-- même compte de jeu ; sinon le premier de ses personnages par ordre alphabétique (ou lui-même, seul)
function Opus.Joueur (nom)
	local id = Opus.DiscordId and Opus.DiscordId(nom)
	if id then return "d:" .. id end
	local premier = Opus.db.alts[nom]
	if premier and Opus.DiscordId then
		for n, p in pairs(Opus.db.alts) do
			id = p == premier and Opus.DiscordId(n)
			if id then return "d:" .. id end
		end
	end
	return premier or nom
end

local function Lier (noms)
	table.sort(noms)
	for _, n in ipairs(noms) do Opus.db.alts[n] = noms[1] end
end

-- ses propres personnages : ceux de la guilde qui se sont connectés sur ce compte
local function MesPersos ()
	local guilde, liste = GetGuildInfo("player"), {}
	local mien = Opus.db.mesPersos[guilde] or {}
	Opus.db.mesPersos[guilde] = mien
	mien[Opus.MonNom()] = true
	for nom in pairs(mien) do
		if Opus.TrouverMembre(nom) then liste[#liste + 1] = nom else mien[nom] = nil end
	end
	return liste
end

function Opus.PublierPersos ()
	if not IsInGuild() or not Opus.db then return end
	local liste = MesPersos()
	Lier(Opus.Copie(liste))
	if #liste > 1 and Opus.PartagerPersos then Opus.PartagerPersos(liste) end
end

function Opus.RecevoirPersos (noms, expediteur)
	local deLui = false
	for _, n in ipairs(noms) do if Opus.EstMembre(n, expediteur) then deLui = true end end
	if deLui and #noms > 1 then Lier(noms) end
end

Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if Opus.persosLance then return end
	Opus.persosLance = true
	C_Timer.After(45, Opus.PublierPersos)
end)

------------------------------------------------------------------------
-- où en est chacun cette semaine
------------------------------------------------------------------------

-- le barème en clair : « exonéré jusqu'au niveau 19, 50 pa de 20 à 39… plafonné à 3 po par joueur »
function Opus.BaremeTexte ()
	local c = Opus.Cotisation()
	if not c then return nil end
	local morceaux = {}
	for _, t in ipairs(c.tranches) do
		local niveaux = t.min == t.max and ("au " .. t.min) or ("de " .. t.min .. " à " .. t.max)
		morceaux[#morceaux + 1] = (t.montant > 0 and Opus.Or(t.montant) or "exonéré") .. " " .. niveaux
	end
	return table.concat(morceaux, ", ") .. (c.plafond and (", plafonné à " .. Opus.Or(c.plafond) .. " par joueur") or "")
end

-- « · semaine : 12 po versés par 5 joueurs » pour l'en-tête de l'onglet Banque
function Opus.SemaineTexte ()
	local etat = Opus.EtatCotisations()
	if not etat then return "" end
	local total, n = 0, 0
	for _, j in pairs(etat) do
		if j.verse > 0 then total, n = total + math.min(j.verse, j.du > 0 and j.du or j.verse), n + 1 end
	end
	return (" · semaine : %s par %d joueur(s)"):format(Opus.Or(total), n)
end

-- par joueur : { du, verse } ; le dû est la somme de ses personnages, plafonnée ; versé = ses dépôts d'or de la semaine
function Opus.EtatCotisations ()
	local c = Opus.Cotisation()
	if not c then return nil end
	local joueurs, debut = {}, math.floor(Opus.DebutSemaine() / 3600)
	for _, m in ipairs(Opus.Membres()) do
		local j = Opus.Joueur(m.nom)
		joueurs[j] = joueurs[j] or { du = 0, verse = 0, persos = {} }
		joueurs[j].du = joueurs[j].du + Opus.DuPerso(m.niveau)
		joueurs[j].persos[#joueurs[j].persos + 1] = m.nom
	end
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.q == "or+" and e.t >= debut then
			local j = joueurs[Opus.Joueur(e.nom)]
			if j then j.verse = j.verse + e.c end
		end
	end
	for _, j in pairs(joueurs) do j.du = math.min(j.du, c.plafond or j.du) end
	return joueurs
end
