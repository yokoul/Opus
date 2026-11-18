-- Banque.lua : participation de chacun à la banque de guilde, relevée dans ses journaux
-- Le jeu ne garde que les dernières opérations de chaque onglet et de l'or, sans identifiant ni date exacte : juste
-- « il y a N heures ». L'addon relève les journaux à chaque ouverture de la banque et fusionne les relevés : une
-- opération déjà vue (même joueur, même objet ou montant, à une heure près) n'est pas comptée deux fois. Plus la
-- banque est ouverte souvent, moins il en échappe.
local _, Opus = ...
local Msg = Opus.Msg

local CONSERVATION = 400 * 24          -- en heures : un peu plus d'un an
local TYPES_OR = { deposit = "or+", withdraw = "or-", withdrawal = "or-", repair = "rep" }
local TYPES_OBJET = { deposit = "obj+", withdraw = "obj-" }

-- les opérations sont datées en heures depuis l'époque Unix
local function Maintenant () return math.floor(time() / 3600) end
local function IlYA (an, mois, jour, heure) return ((an or 0) * 365 + (mois or 0) * 30 + (jour or 0)) * 24 + (heure or 0) end

local function Signature (e)
	return table.concat({ e.q, e.nom, e.c or "", e.id or "", e.n or "", e.tab or "" }, "|")
end

-- ajoute les opérations lues qui ne sont pas déjà connues ; renvoie le nombre d'ajouts
local function Fusionner (lus)
	local evenements, index, pris, ajouts = Opus.db.banque.evenements, {}, {}, 0
	for _, e in ipairs(evenements) do
		local s = Signature(e)
		index[s] = index[s] or {}
		table.insert(index[s], e)
	end
	for _, e in ipairs(lus) do
		local s, trouve = Signature(e), nil
		for _, v in ipairs(index[s] or {}) do
			if not pris[v] and math.abs(v.t - e.t) <= 1 then trouve = v break end
		end
		if not trouve then
			table.insert(evenements, e)
			index[s] = index[s] or {}
			table.insert(index[s], e)
			trouve, ajouts = e, ajouts + 1
		end
		pris[trouve] = true
	end
	return ajouts
end

local function Purger ()
	local limite, garde = Maintenant() - CONSERVATION, {}
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.t >= limite then garde[#garde + 1] = e end
	end
	Opus.db.banque.evenements = garde
end

-- lit les journaux tels que le jeu les a envoyés (banque ouverte seulement : sinon ils peuvent être faux)
function Opus.ReleverBanque ()
	if not Opus.banqueOuverte then return 0 end
	local maintenant, lus = Maintenant(), {}
	if GetNumGuildBankMoneyTransactions and GetGuildBankMoneyTransaction then
		for i = 1, GetNumGuildBankMoneyTransactions() or 0 do
			local type, nom, cuivre, an, mois, jour, heure = GetGuildBankMoneyTransaction(i)
			local q = TYPES_OR[type]
			if q and nom and cuivre then
				lus[#lus + 1] = { t = maintenant - IlYA(an, mois, jour, heure), q = q, nom = Opus.Court(nom), c = cuivre }
			end
		end
	end
	if GetNumGuildBankTransactions and GetGuildBankTransaction then
		for tab = 1, GetNumGuildBankTabs() or 0 do
			for i = 1, GetNumGuildBankTransactions(tab) or 0 do
				local type, nom, lien, n, _, _, an, mois, jour, heure = GetGuildBankTransaction(tab, i)
				local q = TYPES_OBJET[type]
				if q and nom and lien then
					lus[#lus + 1] = {
						t = maintenant - IlYA(an, mois, jour, heure), q = q, nom = Opus.Court(nom),
						id = tonumber(lien:match("item:(%d+)")), o = lien:match("%[(.-)%]"), n = n or 1, tab = tab,
					}
				end
			end
		end
	end
	local ajouts = Fusionner(lus)
	Purger()
	Opus.db.banque.releve = time()
	return ajouts, #lus
end

-- demande au serveur les journaux de chaque onglet puis celui de l'or, un par un comme l'interface de Blizzard
local function Demander ()
	if not QueryGuildBankLog then return end
	local n = GetNumGuildBankTabs() or 0
	for tab = 1, n + 1 do
		C_Timer.After(tab * 0.4, function ()
			if not Opus.banqueOuverte then return end
			QueryGuildBankLog(tab <= n and tab or (MAX_GUILDBANK_TABS or 6) + 1)
		end)
	end
end

-- chaque journal reçu déclenche un relevé, regroupé : on attend que les réponses se calment
local attente, nouveaux = nil, 0
Opus.Ecoute("GUILDBANKLOG_UPDATE", function ()
	if not Opus.banqueOuverte or not Opus.db then return end
	if attente then attente:Cancel() end
	attente = C_Timer.NewTimer(1.5, function ()
		attente = nil
		local ajouts = Opus.ReleverBanque()
		nouveaux = nouveaux + ajouts
		if Opus.Rafraichir then Opus.Rafraichir() end
	end)
end)

local function Ouverte ()
	nouveaux = 0
	C_Timer.After(0.5, Demander)
end
local GUILDBANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
Opus.Ecoute("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function (t) if t == GUILDBANKER then Ouverte() end end)
Opus.Ecoute("GUILDBANKFRAME_OPENED", Ouverte)

local function Fermee ()
	if nouveaux > 0 then Msg(("banque : %d nouvelle(s) opération(s) relevée(s)."):format(nouveaux)) end
	nouveaux = 0
end
Opus.Ecoute("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function (t) if t == GUILDBANKER then Fermee() end end)
Opus.Ecoute("GUILDBANKFRAME_CLOSED", Fermee)

------------------------------------------------------------------------
-- bilan par joueur
------------------------------------------------------------------------

-- { nom, orPlus, orMoins, rep (cuivre), objPlus, objMoins (unités), dernier (heure), ev = { opérations } }
function Opus.Participation (jours)
	local depuis = jours and (Maintenant() - jours * 24) or -math.huge
	local par, liste = {}, {}
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.t >= depuis then
			local p = par[e.nom]
			if not p then
				p = { nom = e.nom, orPlus = 0, orMoins = 0, rep = 0, objPlus = 0, objMoins = 0, dernier = 0, ev = {} }
				par[e.nom] = p
				liste[#liste + 1] = p
			end
			if e.q == "or+" then p.orPlus = p.orPlus + e.c
			elseif e.q == "or-" then p.orMoins = p.orMoins + e.c
			elseif e.q == "rep" then p.rep = p.rep + e.c
			elseif e.q == "obj+" then p.objPlus = p.objPlus + e.n
			elseif e.q == "obj-" then p.objMoins = p.objMoins + e.n end
			p.dernier = math.max(p.dernier, e.t)
			p.ev[#p.ev + 1] = e
		end
	end
	for _, p in ipairs(liste) do table.sort(p.ev, function (a, b) return a.t > b.t end) end
	return liste
end

-- « 3 h », « 2 j », « 5 sem. »
function Opus.Depuis (heure)
	local h = Maintenant() - heure
	if h < 1 then return "< 1 h" elseif h < 48 then return h .. " h" elseif h < 24 * 21 then return math.floor(h / 24) .. " j" end
	return math.floor(h / (24 * 7)) .. " sem."
end

-- montant compact pour un tableau : l'unité la plus grosse seulement (le détail est dans l'infobulle)
local PO = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local PA = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local PC = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function Opus.Or (cuivre)
	if not cuivre or cuivre == 0 then return "|cff666666–|r" end
	if cuivre >= 10000 then return math.floor(cuivre / 10000 + 0.5) .. PO
	elseif cuivre >= 100 then return math.floor(cuivre / 100 + 0.5) .. PA end
	return cuivre .. PC
end
function Opus.OrDetail (cuivre)
	return GetCoinTextureString and GetCoinTextureString(cuivre) or Opus.Or(cuivre)
end

-- une opération en clair, pour les infobulles
local LIBELLES = { ["or+"] = "dépôt", ["or-"] = "retrait", rep = "réparations", ["obj+"] = "dépôt", ["obj-"] = "retrait" }
function Opus.Operation (e)
	local quoi = e.c and Opus.OrDetail(e.c) or ((e.n or 1) .. " × " .. (e.o or ("objet " .. tostring(e.id))))
	local onglet = e.tab and Opus.ONGLETS[e.tab] and (" (" .. Opus.ONGLETS[e.tab] .. ")") or ""
	return ("il y a %s · %s %s%s"):format(Opus.Depuis(e.t), LIBELLES[e.q] or e.q, quoi, onglet)
end

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

-- ce que ce client sait faire avec la banque : pour vérifier sur Forever
Opus.Commande("diagbanque", "diagbanque", "ce que le jeu donne des journaux de la banque (à lancer banque ouverte)", function ()
	local function Existe (nom) return _G[nom] and "|cff60ff60oui|r" or "|cffff6060non|r" end
	Msg("banque " .. (Opus.banqueOuverte and "ouverte" or "|cffff6060fermée|r") .. " ; MAX_GUILDBANK_TABS = " .. tostring(MAX_GUILDBANK_TABS))
	for _, nom in ipairs { "QueryGuildBankLog", "GetNumGuildBankTabs", "GetNumGuildBankTransactions", "GetGuildBankTransaction",
		"GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction" } do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. nom .. " : " .. Existe(nom))
	end
	if not Opus.banqueOuverte then return end
	DEFAULT_CHAT_FRAME:AddMessage(("  onglets : %s ; opérations d'or : %s"):format(tostring(GetNumGuildBankTabs()),
		tostring(GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions())))
	for tab = 1, GetNumGuildBankTabs() or 0 do
		DEFAULT_CHAT_FRAME:AddMessage(("  onglet %d : %s opération(s)"):format(tab, tostring(GetNumGuildBankTransactions and GetNumGuildBankTransactions(tab))))
	end
	local ajouts, lus = Opus.ReleverBanque()
	DEFAULT_CHAT_FRAME:AddMessage(("  relevé : %d lue(s), %d nouvelle(s), %d en mémoire."):format(lus or 0, ajouts or 0, #Opus.db.banque.evenements))
end)

Opus.Commande("banque", "banque", "ouvre la fenêtre sur la participation à la banque", function ()
	Opus.db.page = "banque"
	Opus.Fenetre(true)
end)
