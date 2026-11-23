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

-- tout le groupe, moi compris : { { unite, nom } … }
function Raid.Unites ()
	local liste = { { unite = "player", nom = Raid.MonNom() } }
	if IsInRaid() then
		for k = 1, GetNumGroupMembers() do
			local u = "raid" .. k
			if not UnitIsUnit(u, "player") then liste[#liste + 1] = { unite = u, nom = Raid.Court(GetUnitName(u, true)) } end
		end
	else
		for k = 1, GetNumSubgroupMembers() do liste[#liste + 1] = { unite = "party" .. k, nom = Raid.Court(GetUnitName("party" .. k, true)) } end
	end
	return liste
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
			plusBas, r.remplace = 0, #r.cases
		else
			local suffixe = objet:match(":(%-?%d+)$")
			local n = Niveau(oid)
			r.cases[#r.cases + 1] = { id = oid, lien = "item:" .. oid .. ":0:0:0:0:0:" .. (suffixe or 0), niveau = n }
			if n and (not plusBas or n < plusBas) then r.remplace = #r.cases end
			if n then plusBas = plusBas and math.min(plusBas, n) or n else manque = true end
		end
	end
	r.remplace = r.remplace or 1
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

-- Le nom d'une caractéristique : celui du jeu ; à défaut (Forever ne traduit pas tout, les résistances par exemple),
-- le nôtre ; sinon la clé rendue lisible (« ITEM_MOD_FIRE_RESISTANCE_SHORT » » « fire resistance »).
local NOMS = {
	ITEM_MOD_FIRE_RESISTANCE_SHORT = "Résistance au feu", ITEM_MOD_FROST_RESISTANCE_SHORT = "Résistance au givre",
	ITEM_MOD_NATURE_RESISTANCE_SHORT = "Résistance à la nature", ITEM_MOD_SHADOW_RESISTANCE_SHORT = "Résistance à l'ombre",
	ITEM_MOD_ARCANE_RESISTANCE_SHORT = "Résistance aux arcanes", ITEM_MOD_HOLY_RESISTANCE_SHORT = "Résistance au sacré",
}
function Raid.NomStat (cle)
	local n = _G[cle]
	if type(n) == "string" and n ~= "" then return n end
	if NOMS[cle] then return NOMS[cle] end
	return (cle:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower())
end

-- les caractéristiques d'un objet (suffixe compris) : { [clé du jeu] = valeur }
local StatsDe = (C_Item and C_Item.GetItemStats) or GetItemStats
local function Stats (lien)
	if not StatsDe or not lien then return nil end
	local ok, t = pcall(StatsDe, lien)
	return ok and type(t) == "table" and t or nil
end

-- Ce que l'objet change, caractéristique par caractéristique, face à la pièce qu'il remplacerait (la moins bonne des
-- deux pour bagues, bijoux, armes) : { { nom, ecart } … }, les plus grands écarts d'abord ; nil si le jeu ne dit rien
function Raid.EcartStats (r, id, lien)
	if not r or not r.cases then return nil end
	local nouveau = Stats((lien and lien:find("|H", 1, true)) and lien or ("item:" .. id))
	if not nouveau then return nil end
	local c = r.cases[r.remplace]
	local ancien = c and c.id and Stats(c.lien) or {}
	local ecarts = {}
	for cle in pairs(nouveau) do ecarts[cle] = true end
	for cle in pairs(ancien) do ecarts[cle] = true end
	local liste = {}
	for cle in pairs(ecarts) do
		local e = (nouveau[cle] or 0) - (ancien[cle] or 0)
		if math.abs(e) >= 0.05 then liste[#liste + 1] = { cle = cle, nom = Raid.NomStat(cle), ecart = e } end
	end
	table.sort(liste, function (a, b)
		if math.abs(a.ecart) ~= math.abs(b.ecart) then return math.abs(a.ecart) > math.abs(b.ecart) end
		return a.nom < b.nom
	end)
	return liste
end

------------------------------------------------------------------------
-- Pawn, s'il est là : ce que l'objet vaut vraiment pour la classe du joueur
------------------------------------------------------------------------

-- Le niveau d'objet ne dit pas la valeur d'une pièce (+5 aux sorts valent plus, pour un druide, que 5 d'Intelligence).
-- Pawn a des échelles par classe et par spé (« "Classic":DRUID1 »… celles de HawsJon, faites pour Classic et Forever) et
-- sait calculer n'importe laquelle, même si ce n'est pas la nôtre : pour chaque spé de la classe, l'objet face à la
-- pièce qu'il remplacerait (la moins bonne des deux pour bagues, bijoux, armes), et on garde la meilleure spé.

-- un vrai lien d'objet : le lien tel quel, une chaîne « item:… » (avec son suffixe) résolue, sinon par l'itemID
local function LienComplet (lien, id)
	if lien and lien:find("|H", 1, true) then return lien end
	local _, l = Info((lien and lien:find("^item:")) and lien or id)
	return l
end

local function ValeurPawn (lien, echelle)
	local ok, objet = pcall(PawnGetItemData, lien)
	if not ok or not objet then return nil end
	local ok2, v = pcall(PawnGetSingleValueFromItem, objet, echelle)
	return ok2 and tonumber(v) or nil
end

local echellesDe = {}
local function Echelles (classe)
	if echellesDe[classe] then return echellesDe[classe] end
	local t = {}
	for nom, e in pairs(PawnCommon.Scales) do
		if nom:match('^"Classic":' .. classe .. "%d*$") then
			t[#t + 1] = { nom = nom, spe = (e.LocalizedName or nom):match(":%s*(.+)$") or e.LocalizedName or nom }
		end
	end
	if #t > 0 then echellesDe[classe] = t end
	return t
end

-- r : la comparaison (Raid.Comparer) ; classe : « DRUID »… Rend { pct, spe, vide } pour la meilleure spé, ou nil (pas de
-- Pawn, objet pas encore connu du jeu, ou sans valeur pour cette classe).
function Raid.GainPawn (r, id, lien, classe)
	if not classe or not r or r.inconnu or not r.cases then return nil end
	if not PawnGetItemData or not PawnGetSingleValueFromItem or not PawnCommon or not PawnCommon.Scales then return nil end
	local nouveau = LienComplet(lien, id)
	if not nouveau then return nil end
	local meilleur
	for _, e in ipairs(Echelles(classe)) do
		local vn = ValeurPawn(nouveau, e.nom)
		if vn and vn > 0 then
			local va, manque = nil, false
			for _, c in ipairs(r.cases) do
				local v = 0
				if c.id then
					local l = LienComplet(c.lien, c.id)
					v = l and ValeurPawn(l, e.nom)
				end
				if v == nil then manque = true break end
				va = va and math.min(va, v) or v
			end
			if not manque and va then
				local g = va > 0 and { pct = (vn - va) / va * 100, spe = e.spe } or { pct = math.huge, spe = e.spe, vide = true }
				if not meilleur or g.pct > meilleur.pct then meilleur = g end
			end
		end
	end
	return meilleur
end

-- « +53 % », « −12 % », « vide »
local function TextePawn (g)
	if g.vide then return "vide" end
	local p = math.floor(math.abs(g.pct) + 0.5)
	if p == 0 then return "=" end
	return (g.pct > 0 and "+" or "−") .. p .. " %"
end

-- Les lignes d'infobulle : ce qu'il porte, niveau par niveau, face à l'objet, puis ce que ça change
function Raid.InfobulleEquipement (nom, id, lien, classe)
	local r = Raid.Comparer(nom, id)
	classe = classe or (Opus.db.classes and Opus.db.classes[nom])
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
	local g = Raid.GainPawn(r, id, lien, classe)
	if g then
		local c = (g.vide or g.pct > 0.5) and VERT or g.pct < -0.5 and ROUGE or GRIS
		GameTooltip:AddDoubleLine("Pawn, meilleure spé : " .. g.spe, TextePawn(g), 1, 0.82, 0, c[1], c[2], c[3])
	end
	if r.ecart then GameTooltip:AddLine("niveau d'objet : " .. Raid.TexteEcart(r), 0.6, 0.6, 0.6) end
	local stats = Raid.EcartStats(r, id, lien)
	if stats and #stats > 0 then
		GameTooltip:AddLine(#r.cases > 1 and "En remplaçant la moins bonne des deux :" or "En le portant :", 1, 0.82, 0)
		for k, s in ipairs(stats) do
			if k > 10 then break end
			local v = math.abs(s.ecart)
			v = (v == math.floor(v)) and tostring(v) or string.format("%.1f", v)
			if s.ecart > 0 then GameTooltip:AddDoubleLine(s.nom, "+" .. v, 0.8, 0.8, 0.8, 0.25, 1, 0.25)
			else GameTooltip:AddDoubleLine(s.nom, "−" .. v, 0.8, 0.8, 0.8, 1, 0.35, 0.35) end
		end
	elseif stats then GameTooltip:AddLine("mêmes caractéristiques", 0.6, 0.6, 0.6) end
end

------------------------------------------------------------------------
-- l'affichage en ligne : un verdict, puis les caractéristiques qui bougent le plus
------------------------------------------------------------------------

local VERT, ROUGE, GRIS = { 0.25, 1, 0.25 }, { 1, 0.35, 0.35 }, { 0.6, 0.6, 0.6 }

-- la case du verdict : l'écart de niveau d'objet sur fond teinté (+14 vert, −4 rouge, « vide », « = », « ? »)
function Raid.Verdict (parent)
	local v = CreateFrame("Frame", nil, parent)
	v:SetSize(44, 16)
	v.fond = v:CreateTexture(nil, "BACKGROUND") v.fond:SetAllPoints()
	v.texte = v:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	v.texte:SetAllPoints() v.texte:SetJustifyH("CENTER")
	return v
end
-- Avec Pawn (classe connue), le verdict est son gain dans la meilleure spé ; sinon l'écart de niveau d'objet, en gris :
-- un indice, pas un jugement.
function Raid.PoserVerdict (v, r, id, lien, classe)
	if not r then v:Hide() return end
	local texte, c, fond = "?", GRIS, 0.06
	local g = id and Raid.GainPawn(r, id, lien, classe)
	if g then
		texte = TextePawn(g)
		if g.vide or g.pct > 0.5 then c, fond = VERT, 0.14 elseif g.pct < -0.5 then c, fond = ROUGE, 0.14 end
	elseif not r.inconnu then
		local vide = true
		for _, x in ipairs(r.cases) do if not x.vide then vide = false end end
		if vide then texte, c, fond = "vide", VERT, 0.14
		elseif not r.ecart then texte = "…"
		elseif r.ecart > 0 then texte = "+" .. r.ecart
		elseif r.ecart < 0 then texte = "−" .. -r.ecart
		else texte = "=" end
	end
	v.texte:SetText(texte) v.texte:SetTextColor(c[1], c[2], c[3])
	v.fond:SetColorTexture(c[1], c[2], c[3], fond)
	v:Show()
end

-- les caractéristiques en abrégé, pour tenir sur une ligne (l'infobulle garde les noms entiers)
local ABREGE = {
	ITEM_MOD_STRENGTH_SHORT = "For", ITEM_MOD_AGILITY_SHORT = "Agi", ITEM_MOD_STAMINA_SHORT = "Endu",
	ITEM_MOD_INTELLECT_SHORT = "Int", ITEM_MOD_SPIRIT_SHORT = "Esp", ITEM_MOD_ATTACK_POWER_SHORT = "PA",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "PA dist", ITEM_MOD_SPELL_POWER_SHORT = "Sorts",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Sorts", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Soins",
	ITEM_MOD_CRIT_RATING_SHORT = "Crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "Crit sorts", ITEM_MOD_HIT_RATING_SHORT = "Toucher",
	ITEM_MOD_HIT_SPELL_RATING_SHORT = "Toucher sorts", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Déf",
	ITEM_MOD_DODGE_RATING_SHORT = "Esquive", ITEM_MOD_PARRY_RATING_SHORT = "Parade", ITEM_MOD_BLOCK_RATING_SHORT = "Blocage",
	ITEM_MOD_BLOCK_VALUE_SHORT = "Bloc", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", ITEM_MOD_MANA_REGENERATION_SHORT = "Mana/5",
	ITEM_MOD_HEALTH_REGENERATION_SHORT = "Vie/5",
	RESISTANCE1_NAME = "Rés sacré", RESISTANCE2_NAME = "Rés feu", RESISTANCE3_NAME = "Rés nature",
	RESISTANCE4_NAME = "Rés givre", RESISTANCE5_NAME = "Rés ombre", RESISTANCE6_NAME = "Rés arcanes",
	ITEM_MOD_HOLY_RESISTANCE_SHORT = "Rés sacré", ITEM_MOD_FIRE_RESISTANCE_SHORT = "Rés feu",
	ITEM_MOD_NATURE_RESISTANCE_SHORT = "Rés nature", ITEM_MOD_FROST_RESISTANCE_SHORT = "Rés givre",
	ITEM_MOD_SHADOW_RESISTANCE_SHORT = "Rés ombre", ITEM_MOD_ARCANE_RESISTANCE_SHORT = "Rés arcanes",
}
local CACHEES = { RESISTANCE0_NAME = true }    -- l'armure : elle suit le niveau d'objet, elle prendrait la place

-- n pastilles côte à côte : « +5 For » sur vert, « −5 Agi » sur rouge
function Raid.Pastilles (parent, n)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(1, 16)
	p.cases = {}
	for k = 1, n do
		local c = CreateFrame("Frame", nil, p)
		c:SetHeight(16)
		c.fond = c:CreateTexture(nil, "BACKGROUND") c.fond:SetAllPoints()
		c.texte = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		c.texte:SetPoint("LEFT", 4, 0)
		p.cases[k] = c
	end
	p.aucune = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.aucune:SetPoint("LEFT")
	return p
end
function Raid.PoserPastilles (p, r, id, lien)
	for _, c in ipairs(p.cases) do c:Hide() end
	p.aucune:SetText("")
	local stats = r and not r.inconnu and Raid.EcartStats(r, id, lien)
	if not stats then return end
	local k, x = 0, 0
	for _, s in ipairs(stats) do
		if k >= #p.cases then break end
		if not CACHEES[s.cle] then
			k = k + 1
			local c = p.cases[k]
			local v = math.abs(s.ecart)
			v = (v == math.floor(v)) and tostring(v) or string.format("%.1f", v)
			local col = s.ecart > 0 and VERT or ROUGE
			c.texte:SetText((s.ecart > 0 and "+" or "−") .. v .. " " .. (ABREGE[s.cle] or s.nom))
			c.texte:SetTextColor(col[1], col[2], col[3])
			c.fond:SetColorTexture(col[1], col[2], col[3], 0.09)
			local largeur = c.texte:GetStringWidth() + 8
			c:SetWidth(largeur)
			c:ClearAllPoints() c:SetPoint("LEFT", p, "LEFT", x, 0)
			x = x + largeur + 3
			c:Show()
		end
	end
	if k == 0 then p.aucune:SetText("mêmes caractéristiques") end
end

-- les noms d'objets arrivés après coup
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function () if Raid.RafraichirFiche then Raid.RafraichirFiche() end end)
