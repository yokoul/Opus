-- RaidComm.lua : les annonces et les votes entre addons, par messages d'addon dans le raid (ou le groupe)
-- Le maître du butin diffuse :
--   A;n;itemID;proposé;secondes;candidat,candidat…   une annonce, et le délai d'objection qui reste
--   V;n;secondes;quorum;électeurs;auteur              une objection : le vote est ouvert
--   S;n;itemID;secondes                               un Suicide King : les intéressés se déclarent
--   R;n;état;attributaire                             la fin : attribue, trancher, de ou banque
-- Les joueurs lui répondent, sur le même canal : O;n (objection), P;n (pour), C;n (contre), W;n (je le veux).
-- Le canal raid (« !objection »…) reste ouvert à côté : un joueur sans addon, ou des messages d'addon bloqués en
-- instance, n'empêchent rien. Le maître du butin compte une voix par joueur, d'où qu'elle vienne.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local PREFIXE = "OpusRaid"
local FS = ";"
local R = (Enum and Enum.SendAddonMessageResult) or {}
local OK, VERROU = R.Success or 0, R.AddOnMessageLockdown or 11

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE) end

local function Propre (v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Canal () return IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil end

local averti = false
local function Envoyer (texte)
	local canal = Canal()
	if not canal or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIXE, texte, canal)
	if ok and (res == nil or res == true or res == OK) then return true end
	if not averti then
		averti = true
		Msg(res == VERROU and "messages d'addon bloqués ici : les joueurs objectent et votent dans le canal raid."
			or "message d'addon refusé (" .. tostring(res) .. ") : le canal raid prend le relais.")
	end
	return false
end

-- côté maître du butin (Attribution.lua)
function Raid.Diffuser (...)
	local champs = { ... }
	for k, v in ipairs(champs) do champs[k] = tostring(v):gsub("[;~]", " ") end
	return Envoyer(table.concat(champs, FS):sub(1, 250))
end

-- côté joueur (Vote.lua) : mot = « O », « P » ou « C »
function Raid.Repondre (mot, n) return Envoyer(mot .. FS .. n) end

local REPONSES = { O = "objection", P = "pour", C = "contre", W = "sk" }

Raid.Ecoute("CHAT_MSG_ADDON", function (prefixe, message, canal, expediteur)
	if prefixe ~= PREFIXE then return end
	message, expediteur = Propre(message), Propre(expediteur)
	if not message or not expediteur then return end
	local c = { strsplit(FS, message) }
	local moi = Raid.MonNom()
	local m = Raid.Identifier(expediteur, true)
	local de = m and m.nom or Raid.Court(expediteur)
	-- une réponse d'un joueur : seul le client qui a annoncé l'écoute
	if REPONSES[c[1]] then
		if #Raid.attributions > 0 then Raid.Recevoir(REPONSES[c[1]], tonumber(c[2]), expediteur) end
		return
	end
	if de == moi then return end -- nos propres annonces nous reviennent
	-- une annonce ne compte que d'un membre de la guilde : un autre maître du butin n'ouvre rien chez nous
	if not m then return end
	if Raid.RecevoirAnnonce then Raid.RecevoirAnnonce(de, c) end
end)
