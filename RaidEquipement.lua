-- RaidEquipement.lua : ce que chaque candidat porte à l'emplacement de l'objet, pour comparer avant de décider
-- Sert aussi au butin de groupe en donjon (ButinGroupe.lua). Chaque client inspecte lui-même les membres du groupe, un à la fois, hors combat et à portée d'inspection, et garde
-- leur équipement quelques minutes : la fiche des officiers et les boutons de vote le comparent à l'objet. Les
-- candidats de l'objet en cours passent devant, et sont relus s'ils datent un peu.
local _, Opus = ...
local Raid = Opus.Raid

-- les emplacements à comparer : une arme à une main se compare aux deux mains, une à deux mains aussi
local CASES = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo

Raid.equipe = {}                    -- [nom] = { t = GetTime() de la lecture, [case] = "id" ou "id:suffixe" ou "0" }

-- les cases d'un objet, ou nil (jeton, recette, objet pas équipable)
function Raid.CasesDe (id)
	local emplacement = Instant and select(4, Instant(id))
	return emplacement and CASES[emplacement]
end

-- « id », « id:suffixe » (les « … de l'ours »), « 0 » si rien
local function Objet (unite, case)
	local lien = GetInventoryItemLink(unite, case)
	local champs = lien and lien:match("item:([%-%d:]+)")
	if not champs then
		local id = GetInventoryItemID and GetInventoryItemID(unite, case)
		return id and tostring(id) or "0"
	end
	local f = { strsplit(":", champs) }
	local suffixe = tonumber(f[7] or "") or 0
	return suffixe ~= 0 and (f[1] .. ":" .. suffixe) or f[1]
end
local function Porte (case) return Objet("player", case) end

------------------------------------------------------------------------
-- l'inspection du groupe
------------------------------------------------------------------------

local FRAIS = 300                   -- secondes : un équipement plus vieux est relu
local FRAIS_CANDIDAT = 60           -- pour un candidat de l'objet en cours
local ATTENTE = 3                   -- secondes sans réponse : on passe au suivant
local TOUTES = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local enCours                       -- { guid, unite, nom, depuis }
local prioritaires = {}             -- [nom] = true : les candidats de l'objet en cours

-- les candidats d'un objet passent devant (fenêtre du butin, fiche, annonce)
function Raid.Prioriser (noms)
	for _, nom in ipairs(noms or {}) do prioritaires[nom] = true end
end
function Raid.PrioriserObjets (ids)
	local s = Raid.db and Raid.db.instantane and Raid.db.instantane.souhaits
	if not s then return end
	for _, id in ipairs(ids) do
		for _, c in ipairs(s[tonumber(id)] or {}) do prioritaires[c.nom] = true end
	end
end

local function Unites ()
	local u = {}
	if IsInRaid() then for k = 1, GetNumGroupMembers() do u[#u + 1] = "raid" .. k end
	else for k = 1, GetNumSubgroupMembers() do u[#u + 1] = "party" .. k end end
	return u
end

-- le suivant à inspecter : un candidat d'abord, puis le plus ancien
local function Suivant ()
	local meilleur, sonAge, sonRang
	local maintenant = GetTime()
	for _, unite in ipairs(Unites()) do
		if not UnitIsUnit(unite, "player") and UnitIsConnected(unite) and CanInspect(unite) and CheckInteractDistance(unite, 1) then
			local nom = Raid.Court(GetUnitName(unite, true))
			local e = nom and Raid.equipe[nom]
			local age = e and (maintenant - e.t) or math.huge
			local rang = prioritaires[nom] and 1 or 2
			if age > (rang == 1 and FRAIS_CANDIDAT or FRAIS) and (not meilleur or rang < sonRang or (rang == sonRang and age > sonAge)) then
				meilleur, sonAge, sonRang = unite, age, rang
			end
		end
	end
	return meilleur
end

local function Libre ()
	-- pas pendant que le joueur inspecte lui-même quelqu'un
	return not (InspectFrame and InspectFrame:IsShown())
end

C_Timer.NewTicker(1.5, function ()
	if enCours and GetTime() - enCours.depuis < ATTENTE then return end
	enCours = nil
	if not IsInGroup() or InCombatLockdown() or not Libre() then return end
	-- seulement en raid, ou en groupe pendant une soirée (l'essai en donjon) ou avec la comparaison du butin de groupe
	if not IsInRaid() and not (Raid.db and Raid.db.ouverte) and #(Raid.annonces or {}) == 0
		and not (Opus.ButinGroupeActif and Opus.ButinGroupeActif()) then return end
	local unite = Suivant()
	if not unite then return end
	enCours = { guid = UnitGUID(unite), unite = unite, nom = Raid.Court(GetUnitName(unite, true)), depuis = GetTime() }
	NotifyInspect(unite)
end)

Raid.Ecoute("INSPECT_READY", function (guid)
	local c = enCours
	if not c or guid ~= c.guid then return end
	enCours = nil
	-- l'unité a pu changer (quelqu'un a quitté le raid) : on vérifie que c'est toujours la même personne
	if UnitGUID(c.unite) ~= guid then return end
	local t = { t = GetTime() }
	for _, case in ipairs(TOUTES) do t[case] = Objet(c.unite, case) end
	Raid.equipe[c.nom] = t
	prioritaires[c.nom] = nil
	if Libre() and ClearInspectPlayer then ClearInspectPlayer() end
	if Raid.RafraichirFiche then Raid.RafraichirFiche() end
end)

local function Niveau (id)
	local ilvl = Info and select(4, Info(id))
	if not ilvl and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return ilvl
end

-- La comparaison pour un joueur et un objet :
--   nil si l'objet ne s'équipe pas ; { inconnu = true } s'il n'a pas encore été inspecté (hors de portée…) ;
--   sinon { cases = { { id, lien, niveau } ou { vide = true } … }, niveau = celui de l'objet, ecart = objet − le plus
--   faible porté (bagues, bijoux, armes : on remplace le moins bon), ou nil si un niveau manque encore }
function Raid.Comparer (nom, id)
	local cases = Raid.CasesDe(id)
	if not cases then return nil end
	local moi = nom == Raid.MonNom()
	local porte = Raid.equipe[nom]
	if not moi and not porte then return { inconnu = true } end
	local r = { cases = {}, niveau = Niveau(id) }
	local plusBas, manque
	for _, c in ipairs(cases) do
		local objet = moi and Porte(c) or porte[c]
		if not objet then return { inconnu = true } end
		local oid = tonumber(objet:match("^%d+"))
		if not oid or oid == 0 then
			r.cases[#r.cases + 1] = { vide = true }
			plusBas = 0
		else
			local suffixe = objet:match(":(%-?%d+)$")
			local n = Niveau(oid)
			r.cases[#r.cases + 1] = { id = oid, lien = "item:" .. oid .. ":0:0:0:0:0:" .. (suffixe or 0), niveau = n }
			if n then plusBas = plusBas and math.min(plusBas, n) or n else manque = true end
		end
	end
	if r.niveau and plusBas and not manque then r.ecart = r.niveau - plusBas
	elseif r.niveau and plusBas == 0 then r.ecart = r.niveau end
	return r
end

-- « +7 », « −3 », « = » (couleurs), « vide », « ? »
function Raid.TexteEcart (r)
	if not r then return "" end
	if r.inconnu then return Opus.Gris("?") end
	local vide = true
	for _, c in ipairs(r.cases) do if not c.vide then vide = false end end
	if vide then return "|cff40ff40vide|r" end
	if not r.ecart then return Opus.Gris("…") end
	if r.ecart > 0 then return "|cff40ff40+" .. r.ecart .. "|r" end
	if r.ecart < 0 then return "|cffff5050−" .. -r.ecart .. "|r" end
	return Opus.Gris("=")
end

-- Les lignes d'infobulle : ce qu'il porte, niveau par niveau, face à l'objet
function Raid.InfobulleEquipement (nom, id)
	local r = Raid.Comparer(nom, id)
	if not r then return end
	if r.inconnu then GameTooltip:AddLine("Équipement pas encore inspecté (hors de portée, ou en combat).", 0.6, 0.6, 0.6) return end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Porte à cet emplacement", r.niveau and ("objet : niv. " .. r.niveau) or "", 1, 0.82, 0, 0.8, 0.8, 0.8)
	for _, c in ipairs(r.cases) do
		if c.vide then GameTooltip:AddLine("rien", 0.25, 1, 0.25)
		else
			local nomObjet, _, qualite = Info(c.lien)
			if not nomObjet then nomObjet, _, qualite = Info(c.id) end
			local q = qualite and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualite]
			GameTooltip:AddDoubleLine(nomObjet or ("objet " .. c.id), c.niveau and ("niv. " .. c.niveau) or "",
				q and q.r or 1, q and q.g or 1, q and q.b or 1, 0.8, 0.8, 0.8)
		end
	end
	if r.ecart then GameTooltip:AddLine("écart : " .. Raid.TexteEcart(r), 1, 1, 1) end
end

-- les noms d'objets arrivés après coup
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function () if Raid.RafraichirFiche then Raid.RafraichirFiche() end end)
