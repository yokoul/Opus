-- Specs.lua : la spécialisation de chacun, pour l'onglet Roster
-- Sur Forever, chaque classe a trois arbres de talents (comme à l'époque) et pas de spécialisation à choisir : la « spé »
-- d'un joueur est l'arbre où il a mis le plus de points. Le jeu ne la donne que pour soi (C_Traits, comme les en-têtes
-- d'arbres de la fenêtre des talents) : chaque membre qui a l'addon partage la sienne (Partage.lua), à la connexion,
-- quand ses talents changent, et quand un autre membre se connecte.
local _, Opus = ...

-- le rôle qu'un arbre laisse supposer (noms français et anglais) ; un arbre ambigu (druide farouche) reste « ? »
local ROLES = {
	["Protection"] = "tank",
	["Sacré"] = "soin", ["Holy"] = "soin", ["Discipline"] = "soin", ["Restauration"] = "soin", ["Restoration"] = "soin",
}
local AMBIGUS = { ["Combat farouche"] = true, ["Feral Combat"] = true, ["Farouche"] = true, ["Feral"] = true }

function Opus.RoleDeSpe (arbre)
	if not arbre then return nil end
	if ROLES[arbre] then return ROLES[arbre] end
	if AMBIGUS[arbre] then return nil end
	return "degats"
end

-- le rôle d'une spé connue : celui que le joueur a déclaré (/opus role), sinon celui que son arbre laisse supposer
function Opus.RoleDe (s)
	if not s then return nil end
	return s.role or Opus.RoleDeSpe(s.arbre)
end

-- la spé du joueur : { arbre, icone, points = "31/20/0" } ; nil tant qu'aucun point n'est placé ou que l'API manque
function Opus.MaSpe ()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return nil end
	local configID = C_ClassTalents.GetActiveConfigID()
	local info = configID and C_Traits.GetConfigInfo(configID)
	local arbre = info and info.treeIDs and info.treeIDs[1]
	if not arbre then return nil end
	local affichages = C_Traits.GetGroupDisplayInfoByTreeID(arbre) or {}
	local ids = {}
	for _, a in ipairs(affichages) do ids[#ids + 1] = a.groupID end
	local depenses = {}
	for _, g in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
		local c = g.currencyInfos and g.currencyInfos[1]
		depenses[g.traitNodeGroupID] = c and c.spent or 0
	end
	table.sort(affichages, function (a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	local meilleur, points = nil, {}
	for _, a in ipairs(affichages) do
		local p = depenses[a.groupID] or 0
		points[#points + 1] = p
		if p > 0 and (not meilleur or p > meilleur.p) then meilleur = { nom = a.displayName, icone = a.icon, p = p } end
	end
	if not meilleur then return nil end
	return { arbre = meilleur.nom, icone = meilleur.icone, points = table.concat(points, "/") }
end

-- retient la spé d'un membre (la sienne ou reçue) ; t = quand elle a été vue
function Opus.RetenirSpe (nom, s, t)
	local actuelle = Opus.db.spes[nom]
	if actuelle and actuelle.t and t and actuelle.t > t then return false end
	Opus.db.spes[nom] = { arbre = s.arbre, icone = s.icone, points = s.points, role = s.role, t = t or time() }
	return true
end

local envoyee
local function Publier (forcer)
	if not IsInGuild() or not Opus.db then return end
	local s = Opus.MaSpe()
	if not s then return end
	s.role = Opus.db.monRole
	local moi = Opus.MonNom()
	-- (avant 0.10.1, la spé était rangée sous le seul prénom)
	local prenom = Opus.Court(UnitName("player"))
	if prenom ~= moi then Opus.db.spes[prenom] = nil end
	Opus.RetenirSpe(moi, s)
	local cle = s.arbre .. s.points .. (s.role or "")
	if (forcer or cle ~= envoyee) and Opus.PartagerSpe then
		envoyee = cle
		Opus.PartagerSpe(moi, Opus.db.spes[moi])
	end
	if Opus.Rafraichir then Opus.Rafraichir() end
end
Opus.PublierSpe = Publier

-- les talents changent par rafales : on attend que ça se calme
local attente
local function Changement ()
	if attente then attente:Cancel() end
	attente = C_Timer.NewTimer(3, function () attente = nil Publier() end)
end
for _, ev in ipairs { "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" } do
	Opus.Ecoute(ev, Changement)
end
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if Opus.speLancee then return end
	Opus.speLancee = true
	C_Timer.After(40, function () Publier(true) end)
end)

local NOMS_ROLES = { tank = "tank", soin = "soigneur", degats = "dégâts" }
Opus.Commande("role", "role tank|soin|degats|auto", "ton rôle quand ta spé ne le dit pas (druide farouche…), partagé avec ta spé", function (s)
	s = (s or ""):lower():gsub("é", "e"):gsub("â", "a")
	if s == "soigneur" or s == "heal" then s = "soin" elseif s == "dps" or s == "degat" then s = "degats" end
	if s == "auto" then
		Opus.db.monRole = nil
		Opus.Msg("rôle : déduit de ta spé.")
	elseif NOMS_ROLES[s] then
		Opus.db.monRole = s
		Opus.Msg("rôle déclaré : " .. NOMS_ROLES[s] .. ".")
	else
		Opus.Msg("exemple : /opus role tank (ou soin, degats, auto).")
		return
	end
	Publier(true)
end)

Opus.Commande("diagspe", "diagspe", "la spécialisation que l'addon lit pour ton personnage", function ()
	local s = Opus.MaSpe()
	Opus.Msg(s and ("spé lue : %s (%s points)"):format(s.arbre, s.points) or "aucune spé lue (pas de points placés, ou l'API des talents manque).")
end)
