-- Droits.lua : contrôle des droits réels de la guilde face à la grille, et application en un clic
local _, Opus = ...
local Msg, Safe = Opus.Msg, Opus.Safe

local function Drapeaux (rang)
	GuildControlSetRank(rang)
	if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
		return C_GuildInfo.GuildControlGetRankFlags(rang) or {}
	end
	return { GuildControlGetRankFlags() }
end

-- l'état réel d'un grade ; onglets seulement si la banque est ouverte
function Opus.Lire (rang)
	local f = Drapeaux(rang)
	local r = { nom = GuildControlGetRankName(rang), drapeaux = f }
	for _, d in ipairs(Opus.DROITS) do r[d.cle] = f[d.id] and true or false end
	r.or_ = Safe(GetGuildBankWithdrawGoldLimit) or 0
	if r.or_ < 0 then r.or_ = 0 end
	if Opus.banqueOuverte then
		r.onglets = {}
		local n = Safe(GetNumGuildBankTabs) or 0
		for t = 1, math.min(n, #Opus.ONGLETS) do
			local voir, deposer, _, retraits = GetGuildBankTabPermissions(t)
			r.onglets[t] = { voir = voir and true or false, deposer = deposer and true or false, retraits = retraits or 0 }
		end
	end
	return r
end

-- les grades du jeu correspondent-ils à la grille ?
function Opus.GradesConformes ()
	local n = GuildControlGetNumRanks() or 0
	local soucis = {}
	if n ~= #Opus.GRADES then soucis[#soucis + 1] = ("%d grades en jeu, %d dans la grille"):format(n, #Opus.GRADES) end
	for i = 1, math.min(n, #Opus.GRADES) do
		local nom = GuildControlGetRankName(i)
		if nom ~= Opus.GRADES[i].nom then soucis[#soucis + 1] = ("grade %d : « %s » en jeu, « %s » dans la grille"):format(i, tostring(nom), Opus.GRADES[i].nom) end
	end
	return #soucis == 0, soucis
end

local function OuiNon (b) return b and "oui" or "non" end

-- écarts : { rang, quoi, attendu, reel } ; impossibles : dépôt sans voir l'onglet
function Opus.Comparer (reglage)
	local ecarts, impossibles = {}, {}
	for rang = 2, math.min(GuildControlGetNumRanks() or 0, #Opus.GRADES) do
		local a, r = Opus.Attendu(rang, reglage), Opus.Lire(rang)
		local function E (quoi, att, reel) ecarts[#ecarts + 1] = { rang = rang, quoi = quoi, attendu = att, reel = reel } end
		for _, d in ipairs(Opus.DROITS) do
			if a[d.cle] ~= r[d.cle] then E(d.nom, OuiNon(a[d.cle]), OuiNon(r[d.cle])) end
		end
		if a.or_ ~= r.or_ then E("Plafond d'or par jour", a.or_ .. " po", r.or_ .. " po") end
		if r.onglets then
			for t, o in ipairs(a.onglets) do
				local reel = r.onglets[t]
				if reel then
					local nom = "Onglet " .. t .. " (" .. Opus.ONGLETS[t] .. ")"
					if o.voir ~= reel.voir then E(nom .. " : voir", OuiNon(o.voir), OuiNon(reel.voir)) end
					if o.voir then
						if o.deposer ~= reel.deposer then E(nom .. " : déposer", OuiNon(o.deposer), OuiNon(reel.deposer)) end
						if o.retraits ~= reel.retraits then E(nom .. " : retraits par jour", o.retraits, reel.retraits) end
					elseif o.deposer then
						impossibles[#impossibles + 1] = Opus.GRADES[rang].nom .. ", onglet " .. t
					end
				end
			end
		end
	end
	return ecarts, impossibles
end

function Opus.Rapport (reglage)
	reglage = reglage or Opus.db.reglage
	if not IsInGuild() then Msg("tu n'es pas en guilde.") return end
	local ok, soucis = Opus.GradesConformes()
	if not ok then
		Msg("|cffff6060les grades ne correspondent pas à la grille :|r")
		for _, s in ipairs(soucis) do DEFAULT_CHAT_FRAME:AddMessage("  " .. s) end
		return
	end
	local ecarts, impossibles = Opus.Comparer(reglage)
	Msg("contrôle « " .. Opus.REGLAGES[reglage] .. " »" .. (Opus.banqueOuverte and "" or " — |cffffd100ouvre la banque de guilde pour contrôler aussi les onglets|r"))
	if #ecarts == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("  |cff60ff60tout est conforme.|r")
	else
		local dernier
		for _, e in ipairs(ecarts) do
			if e.rang ~= dernier then DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. Opus.GRADES[e.rang].nom .. "|r") dernier = e.rang end
			DEFAULT_CHAT_FRAME:AddMessage(("    %s : %s au lieu de %s"):format(e.quoi, tostring(e.reel), tostring(e.attendu)))
		end
		DEFAULT_CHAT_FRAME:AddMessage(("  %d écart(s)."):format(#ecarts))
	end
	if #impossibles > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaaimpossible en jeu (déposer sans voir l'onglet) : " .. table.concat(impossibles, " ; ") .. "|r")
	end
	return ecarts
end

------------------------------------------------------------------------
-- application (Magister seulement, sur clic, grade par grade)
------------------------------------------------------------------------

function Opus.Appliquer (reglage)
	if not IsGuildLeader() then Msg("seul le Magister peut modifier les grades.") return end
	local ok, soucis = Opus.GradesConformes()
	if not ok then Msg("grades non conformes, rien n'est modifié : " .. table.concat(soucis, " ; ")) return end
	local avecOnglets = Opus.banqueOuverte
	local n = math.min(GuildControlGetNumRanks(), #Opus.GRADES)
	local function Grade (rang)
		local a, r = Opus.Attendu(rang, reglage), Opus.Lire(rang)
		GuildControlSetRank(rang)
		for _, d in ipairs(Opus.DROITS) do
			if a[d.cle] ~= r[d.cle] then GuildControlSetRankFlag(d.id, a[d.cle]) end
		end
		if a.or_ ~= r.or_ then
			SetGuildBankWithdrawGoldLimit(a.or_)
			GuildControlSaveRank(GuildControlGetRankName(rang))
		end
		if avecOnglets and r.onglets then
			for t, o in ipairs(a.onglets) do
				local reel = r.onglets[t]
				if reel then
					if o.voir ~= reel.voir then SetGuildBankTabPermissions(t, 1, o.voir) end
					if o.voir then
						if o.deposer ~= reel.deposer then SetGuildBankTabPermissions(t, 2, o.deposer) end
						if o.retraits ~= reel.retraits then SetGuildBankTabItemWithdraw(t, o.retraits) end
					end
				end
			end
		end
	end
	Msg("application de « " .. Opus.REGLAGES[reglage] .. " »" .. (avecOnglets and "" or " (sans les onglets : la banque n'est pas ouverte)") .. "…")
	for rang = 2, n do
		C_Timer.After((rang - 2) * 0.6, function () Grade(rang) end)
	end
	C_Timer.After((n - 1) * 0.6 + 2, function ()
		Opus.db.reglage = reglage
		Opus.Rapport(reglage)
	end)
end

StaticPopupDialogs["OPUS_APPLIQUER"] = {
	text = "Appliquer aux grades le préréglage :\n|cffffd100%s|r ?",
	button1 = YES, button2 = NO,
	OnAccept = function (_, reglage) Opus.Appliquer(reglage) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function Opus.DemanderAppliquer (reglage)
	StaticPopup_Show("OPUS_APPLIQUER", Opus.REGLAGES[reglage], nil, reglage)
end

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

local function Reglage (s)
	s = (s or ""):lower()
	if s == "raids" or s == "raid" then return "raids" elseif s == "phase" then return "phase" end
	return nil
end

Opus.Commande("controle", "controle [phase|raids]", "compare les droits réels à la grille", function (s)
	Opus.Rapport(Reglage(s) or Opus.db.reglage)
end)

Opus.Commande("appliquer", "appliquer phase|raids", "règle les grades selon la grille (Magister, avec confirmation)", function (s)
	local r = Reglage(s)
	if not r then Msg("préciser « phase » ou « raids ».") return end
	Opus.DemanderAppliquer(r)
end)

-- relevé brut de tous les droits, pour vérifier les numéros
Opus.Commande("diag", "diag", "relevé brut des droits de chaque grade", function ()
	for rang = 1, GuildControlGetNumRanks() or 0 do
		local f = Drapeaux(rang)
		local oui = {}
		for i = 1, 22 do if f[i] then oui[#oui + 1] = i end end
		DEFAULT_CHAT_FRAME:AddMessage(("|cffffd100%d %s|r : droits %s ; or %s"):format(rang, tostring(GuildControlGetRankName(rang)),
			#oui > 0 and table.concat(oui, ",") or "aucun", tostring(Safe(GetGuildBankWithdrawGoldLimit))))
	end
	for i = 1, 22 do
		local s = _G["GUILDCONTROL_OPTION" .. i]
		if s then DEFAULT_CHAT_FRAME:AddMessage(("  %d = %s"):format(i, s:gsub("\n", " "))) end
	end
end)
