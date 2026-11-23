-- RaidRemise.lua : le maître du butin remet chaque objet attribué par échange, et l'addon note les écarts
-- À l'ouverture d'un échange avec un attributaire, l'objet qu'il doit recevoir est posé tout seul dans l'échange.
-- Quand le jeu annonce l'échange terminé, la remise est notée (événement M) ; un objet attribué qui part à quelqu'un
-- d'autre est un écart (K « autre_destinataire »). Chaque minute, l'addon lit le temps d'échange restant des objets
-- pas encore remis (l'infobulle du jeu) et prévient sous 20 minutes (K « delai_proche »).
-- Un objet attribué au maître du butin lui-même est remis d'office (mode « ramasse ») ; un objet donné depuis le corps
-- par le menu du maître du butin (« Donner », RaidButin.lua) l'est en mode « maitre ».
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local ALERTE = 20 * 60              -- secondes d'échange restantes sous lesquelles on prévient

local function IdDe (lien) return tonumber((lien or ""):match("item:(%d+)")) end

-- les attributions qui attendent leur remise (attribuées ou au désenchantement, pas encore remises)
function Raid.ARemettre ()
	local liste = {}
	for _, a in ipairs(Raid.attributions) do
		if (a.etat == "attribue" or a.etat == "de") and a.attributaire and not a.remis then liste[#liste + 1] = a end
	end
	return liste
end

local function Remettre (a, dest, mode)
	a.remis = dest
	Raid.Noter("M", { attribution = a.evenementA, destinataire = dest, mode = mode })
	if Raid.RafraichirButin then Raid.RafraichirButin() end
end

Raid.Remettre = Remettre

-- appelé à chaque attribution (Attribution.lua, SuicideKing.lua)
function Raid.ApresAttribution (a)
	if a.attributaire and a.attributaire == Raid.MonNom() then Remettre(a, a.attributaire, "ramasse") end
end

------------------------------------------------------------------------
-- les sacs
------------------------------------------------------------------------

local Slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local ItemId = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local Prendre = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

-- les emplacements des sacs qui contiennent cet objet
local function Trouver (id)
	local ou = {}
	for sac = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, Slots(sac) or 0 do
			if ItemId(sac, slot) == id then ou[#ou + 1] = { sac, slot } end
		end
	end
	return ou
end

-- Le temps d'échange restant d'un objet des sacs, en secondes, d'après son infobulle ; nil s'il n'en a pas.
local MOTIF = BIND_TRADE_TIME_REMAINING and BIND_TRADE_TIME_REMAINING:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
local function TempsRestant (sac, slot)
	if not MOTIF or not C_TooltipInfo or not C_TooltipInfo.GetBagItem then return nil end
	local ok, info = pcall(C_TooltipInfo.GetBagItem, sac, slot)
	if not ok or not info or not info.lines then return nil end
	for _, ligne in ipairs(info.lines) do
		local duree = ligne.leftText and ligne.leftText:match(MOTIF)
		if duree then
			local h = tonumber(duree:match("(%d+)%s*[hH]")) or 0
			local m = tonumber(duree:match("(%d+)%s*[mM]")) or 0
			return h * 3600 + m * 60
		end
	end
	return nil
end

------------------------------------------------------------------------
-- l'échange
------------------------------------------------------------------------

local echange                       -- { dest, objets = { itemID… } }, relevé à chaque acceptation

local function Partenaire ()
	local nom = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() or UnitName("NPC")
	local m = nom and Raid.Identifier(nom, true)
	return m and m.nom or (nom and Raid.Court(nom))
end

Raid.Ecoute("TRADE_SHOW", function ()
	echange = nil
	local dest = Partenaire()
	if not dest or Raid.db.reglages.echangeAuto == false then return end
	-- les objets dus à ce partenaire, posés dans les cases libres de l'échange
	C_Timer.After(0.3, function ()
		local case = 1
		for _, a in ipairs(Raid.ARemettre()) do
			if a.attributaire == dest then
				local ou = Trouver(a.id)[1]
				while case <= 6 and GetTradePlayerItemLink(case) do case = case + 1 end
				if ou and case <= 6 then
					ClearCursor()
					Prendre(ou[1], ou[2])
					ClickTradeButton(case)
					Msg(a.lien .. " posé dans l'échange pour " .. dest .. " (#" .. a.n .. ").")
					case = case + 1
				elseif not ou then
					Msg(a.lien .. " pour " .. dest .. " n'est pas dans tes sacs.")
				end
			end
		end
	end)
end)

Raid.Ecoute("TRADE_ACCEPT_UPDATE", function (moi)
	if moi ~= 1 and moi ~= true then return end
	local objets = {}
	for i = 1, MAX_TRADABLE_ITEMS or 6 do
		local id = IdDe(GetTradePlayerItemLink(i))
		if id then objets[#objets + 1] = id end
	end
	echange = { dest = Partenaire(), objets = objets }
end)

Raid.Ecoute("UI_INFO_MESSAGE", function (_, message)
	if message ~= ERR_TRADE_COMPLETE or not echange then return end
	local e = echange
	echange = nil
	if not e.dest then return end
	for _, id in ipairs(e.objets) do
		-- l'attribution de cet objet pour ce destinataire, sinon la première de cet objet : un écart
		local voulue, autre
		for _, a in ipairs(Raid.ARemettre()) do
			if a.id == id then
				if a.attributaire == e.dest then voulue = voulue or a else autre = autre or a end
			end
		end
		if voulue then
			Remettre(voulue, e.dest, "echange")
		elseif autre then
			Remettre(autre, e.dest, "echange")
			Raid.Noter("K", { attribution = autre.evenementA, nature = "autre_destinataire", detail = e.dest })
			Msg("|cffff5555écart|r : " .. autre.lien .. " était attribué à " .. autre.attributaire .. ", remis à " .. e.dest .. ". À corriger sur le site si c'était voulu.")
		end
	end
end)

------------------------------------------------------------------------
-- le temps d'échange
------------------------------------------------------------------------

C_Timer.NewTicker(60, function ()
	for _, a in ipairs(Raid.ARemettre()) do
		if not a.alerte then
			for _, ou in ipairs(Trouver(a.id)) do
				local reste = TempsRestant(ou[1], ou[2])
				if reste and reste < ALERTE then
					a.alerte = true
					Raid.Noter("K", { attribution = a.evenementA, nature = "delai_proche", detail = tostring(reste) })
					Msg(string.format("|cffff5555plus que %d min|r pour remettre %s à %s (#%d) : passé ce délai, l'objet ne s'échange plus.",
						math.floor(reste / 60), a.lien, a.attributaire, a.n))
					if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
					break
				end
			end
		end
	end
end)

Raid.Commande("remises", "remises", "les objets attribués pas encore remis", function ()
	local liste = Raid.ARemettre()
	if #liste == 0 then Msg("rien à remettre.") return end
	Msg("à remettre :")
	for _, a in ipairs(liste) do DEFAULT_CHAT_FRAME:AddMessage(string.format("  #%d %s à %s", a.n, a.lien, a.attributaire)) end
end)

Raid.Commande("echangeauto", "echangeauto on|off", "poser tout seul l'objet dû dans l'échange avec son attributaire", function (texte)
	local v = (texte or ""):lower()
	if v == "on" or v == "off" then Raid.db.reglages.echangeAuto = v == "on" end
	Msg("échange automatique : " .. (Raid.db.reglages.echangeAuto == false and "off" or "on") .. ".")
end)
