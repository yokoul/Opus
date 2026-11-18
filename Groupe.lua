-- Groupe.lua : former un groupe de donjon avec les membres en ligne de son niveau (vue « Former un groupe » du Roster)
-- Les donjons et leurs tranches de niveau viennent de l'addon Dungeon Journal s'il est installé (sa table
-- ForeverDungeonJournal_NS.DB, avec ses noms traduits) ; sans lui, la tranche est son propre niveau à ±3.
local _, Opus = ...

local ECART = 3
Opus.groupe = { donjon = nil, places = {} }     -- places[i] = nom du membre ; 1 tank, 2 soin, 3-5 dégâts
Opus.PLACES = { "tank", "soin", "degats", "degats", "degats" }

-- les donjons connus : { cle, nom, min, max }, du plus bas au plus haut
function Opus.Donjons ()
	local ns = _G.ForeverDungeonJournal_NS
	local liste = {}
	if ns and type(ns.DB) == "table" then
		for cle, d in pairs(ns.DB) do
			local niv = type(d) == "table" and type(d.level) == "string" and d.level or ""
			local a, b = niv:match("^(%d+)%s*%-%s*(%d+)$")
			if not a then a = niv:match("^(%d+)%+$") b = a and 60 end
			if a then
				local ok, nom = pcall(ns.LocalizeDungeonName or function (x) return x end, cle)
				liste[#liste + 1] = { cle = cle, nom = ok and nom or cle, min = tonumber(a), max = tonumber(b) }
			end
		end
	end
	table.sort(liste, function (x, y) if x.min ~= y.min then return x.min < y.min end return x.nom < y.nom end)
	return liste
end

-- la tranche de niveau visée : celle du donjon choisi, sinon son niveau à ±3
function Opus.Tranche ()
	local d = Opus.groupe.donjon
	if d then return d.min, d.max, d.nom end
	local n = UnitLevel("player")
	return math.max(1, n - ECART), n + ECART, nil
end

function Opus.DansLeGroupe (nom)
	for i = 1, #Opus.PLACES do if Opus.groupe.places[i] == nom then return i end end
	return nil
end

-- place un membre à une place de son rôle ; un rôle inconnu va d'abord en dégâts (le plus courant), pour laisser
-- tank et soin à ceux qui le sont, puis à n'importe quelle place libre
function Opus.AjouterAuGroupe (m)
	if Opus.DansLeGroupe(m.nom) then return end
	local role = Opus.RoleDe(Opus.db.spes[m.nom])
	local libre
	for i, r in ipairs(Opus.PLACES) do
		if not Opus.groupe.places[i] and r == (role or "degats") then libre = i break end
	end
	if not libre and not role then
		for i = 1, #Opus.PLACES do if not Opus.groupe.places[i] then libre = i break end end
	end
	if not libre then Opus.Msg(role and "plus de place pour ce rôle dans le groupe." or "le groupe est complet.") return end
	Opus.groupe.places[libre] = m.nom
	if Opus.Rafraichir then Opus.Rafraichir() end
end

function Opus.RetirerDuGroupe (i)
	Opus.groupe.places[i] = nil
	if Opus.Rafraichir then Opus.Rafraichir() end
end

function Opus.ViderGroupe ()
	Opus.groupe.places = {}
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- ce qui manque, en clair : « 1 soigneur, 2 dégâts »
local NOMS = { tank = { "tank", "tanks" }, soin = { "soigneur", "soigneurs" }, degats = { "dégâts", "dégâts" } }
function Opus.Manque ()
	local manque = { tank = 0, soin = 0, degats = 0 }
	for i, r in ipairs(Opus.PLACES) do if not Opus.groupe.places[i] then manque[r] = manque[r] + 1 end end
	local morceaux = {}
	for _, r in ipairs { "tank", "soin", "degats" } do
		if manque[r] > 0 then morceaux[#morceaux + 1] = manque[r] .. " " .. NOMS[r][manque[r] > 1 and 2 or 1] end
	end
	return table.concat(morceaux, ", ")
end

-- les commandes que les boutons sécurisés exécutent (une ligne par invitation ; 255 caractères au plus)
function Opus.MacroInvitations ()
	local moi, lignes = Opus.MonNom(), {}
	for i = 1, #Opus.PLACES do
		local nom = Opus.groupe.places[i]
		if nom and nom ~= moi and not UnitInParty(nom) then lignes[#lignes + 1] = "/invite " .. nom end
	end
	local texte = table.concat(lignes, "\n")
	return #texte <= 255 and texte or texte:sub(1, 255)
end

function Opus.MacroAnnonce ()
	local min, max, nom = Opus.Tranche()
	local manque = Opus.Manque()
	if manque == "" then return nil end
	local texte = ("/g [Opus] %s (niv. %d-%d) : il manque %s. Chuchotez %s !"):format(nom or "Groupe de donjon", min, max, manque, Opus.MonNom())
	return #texte <= 255 and texte or texte:sub(1, 255)
end
