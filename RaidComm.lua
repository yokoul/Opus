-- RaidComm.lua : les annonces et les votes entre addons, par messages d'addon dans le raid (ou le groupe)
-- Le maître du butin diffuse :
--   A;n;itemID;proposé;secondes;candidat,candidat…;item:…   une annonce, le délai d'objection qui reste, l'objet complet
--   V;n;secondes;quorum;électeurs;auteur;candidats;motif   une objection : le vote est ouvert, entre ces candidats
--   S;n;itemID;secondes;item:…                        un Suicide King : les intéressés se déclarent
--   R;n;état;attributaire;itemID                      la fin : attribue, trancher, de ou banque
--   K;n;déclaré,déclaré…                              au Suicide King : les déclarés, du mieux placé au moins bien
-- Un joueur qui recharge envoie Q (où en est la soirée ?) : le maître du butin renvoie l'état des annonces.
-- Les joueurs lui répondent, sur le même canal : O;n;motif (objection), B;n;candidat (un vote), W;n (je le veux),
-- X;n (je passe, au Suicide King), L;n;nom (je le laisse, à ce candidat).
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

-- côté joueur : après un rechargement en groupe, demander l'état de la soirée au maître du butin
function Raid.DemanderEtat () return Envoyer("Q;0") end
Raid.Ecoute("PLAYER_ENTERING_WORLD", function (premiere, rechargement)
	if not (premiere or rechargement) then return end
	C_Timer.After(4, function () if IsInGroup() then Raid.DemanderEtat() end end)
end)

-- côté joueur (Vote.lua) : mot = « O » (objection, avec son motif), « B » (un vote, pour ce candidat) ou « W »
function Raid.Repondre (mot, n, quoi)
	return Envoyer(mot .. FS .. n .. (quoi and (FS .. tostring(quoi):gsub("[;~]", " ")) or ""))
end

local REPONSES = { O = "objection", B = "vote", P = "pour", W = "sk", X = "passe", L = "laisse" }

Raid.Ecoute("CHAT_MSG_ADDON", function (prefixe, message, canal, expediteur)
	if prefixe ~= PREFIXE then return end
	message, expediteur = Propre(message), Propre(expediteur)
	if not message or not expediteur then return end
	local c = { strsplit(FS, message) }
	local moi = Raid.MonNom()
	local m = Raid.Identifier(expediteur, true)
	local de = m and m.nom or Raid.Court(expediteur)
	-- « où en est la soirée ? » : le maître du butin renvoie l'état
	if c[1] == "Q" then
		if de ~= moi and #Raid.attributions > 0 and Raid.RenvoyerEtat then Raid.RenvoyerEtat() end
		return
	end
	-- une réponse d'un joueur : seul le client qui a annoncé l'écoute
	if REPONSES[c[1]] then
		if #Raid.attributions > 0 then Raid.Recevoir(REPONSES[c[1]], tonumber(c[2]), expediteur, c[3]) end
		return
	end
	-- nos propres annonces nous reviennent : seul le Suicide King (et son résultat) passe, le maître du butin peut aussi
	-- s'y déclarer d'un bouton ; le reste, il le suit dans sa fenêtre du butin et la fiche
	if de == moi and c[1] ~= "S" and c[1] ~= "R" and c[1] ~= "K" then return end
	-- une annonce ne compte que d'un membre de la guilde : un autre maître du butin n'ouvre rien chez nous
	if not m then return end
	if Raid.RecevoirAnnonce then Raid.RecevoirAnnonce(de, c) end
end)
