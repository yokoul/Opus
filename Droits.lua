-- Droits.lua : contrôle des droits réels de la guilde face à la grille, et application en un clic
local _, Opus = ...
local Msg = Opus.Msg

-- Les droits d'un grade se lisent directement. Le plafond d'or et les onglets de banque, eux, ne se lisent que
-- pour le grade sélectionné dans l'interface de Blizzard : le sélectionner (GuildControlSetRank) est réservé à
-- cette interface, comme toute modification des grades. On ne contrôle donc que les droits, et le reste se
-- règle à la main d'après la fiche.
local function Drapeaux (rang)
	if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
		return C_GuildInfo.GuildControlGetRankFlags(rang)
	end
	return nil
end

-- l'état réel d'un grade (nil si le jeu ne donne pas ses droits)
function Opus.Lire (rang)
	local f = Drapeaux(rang)
	if not f then return nil end
	local r = { nom = GuildControlGetRankName(rang), drapeaux = f }
	for _, d in ipairs(Opus.DROITS) do r[d.cle] = f[d.id] and true or false end
	return r
end

-- la grille a-t-elle autant de grades que le jeu ? (les noms viennent du jeu : un grade renommé reste le même)
function Opus.GradesConformes ()
	local n, c = GuildControlGetNumRanks() or 0, Opus.Config()
	local m = c and #c.grades or 0
	if n ~= m then return false, { ("%d grades en jeu, %d dans la grille : reprends l'état du jeu pour la recaler"):format(n, m) } end
	return true, {}
end

local function OuiNon (b) return b and "oui" or "non" end

-- écarts : { rang, quoi, attendu, reel } ; nil si les droits ne se lisent pas
function Opus.Comparer ()
	local ecarts = {}
	for rang = 2, math.min(GuildControlGetNumRanks() or 0, #Opus.GRADES) do
		local a, r = Opus.Attendu(rang), Opus.Lire(rang)
		if not r then return nil end
		for _, d in ipairs(Opus.DROITS) do
			if a[d.cle] ~= r[d.cle] then
				ecarts[#ecarts + 1] = { rang = rang, cle = d.cle, quoi = d.nom, attendu = OuiNon(a[d.cle]), reel = OuiNon(r[d.cle]) }
			end
		end
	end
	return ecarts
end

function Opus.Rapport ()
	if not IsInGuild() then Msg("tu n'es pas en guilde.") return end
	local ok, soucis = Opus.GradesConformes()
	if not ok then
		Msg("|cffff6060les grades ne correspondent pas à la grille :|r")
		for _, s in ipairs(soucis) do DEFAULT_CHAT_FRAME:AddMessage("  " .. s) end
		return
	end
	local ecarts = Opus.Comparer()
	if not ecarts then Msg("le jeu ne donne pas les droits des grades sur ce client.") return end
	Msg("contrôle des droits" .. (Opus.Restriction() and (" (" .. Opus.Restriction().texte .. ")") or ""))
	if #ecarts == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("  |cff60ff60droits conformes.|r")
	else
		local dernier
		for _, e in ipairs(ecarts) do
			if e.rang ~= dernier then DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. Opus.GRADES[e.rang].nom .. "|r") dernier = e.rang end
			DEFAULT_CHAT_FRAME:AddMessage(("    %s : %s au lieu de %s"):format(e.quoi, tostring(e.reel), tostring(e.attendu)))
		end
		DEFAULT_CHAT_FRAME:AddMessage(("  %d écart(s), à corriger dans Guilde > Contrôle de guilde."):format(#ecarts))
	end
	DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaaplafond d'or et onglets de banque : illisibles pour un addon, voir la fiche.|r")
	return ecarts
end

------------------------------------------------------------------------
-- fiche : ce qu'il faut régler à la main, grade par grade
------------------------------------------------------------------------

local function Onglet (o)
	if o.voir then
		return (o.deposer and "voir, déposer" or "voir") .. (o.retraits > 0 and (", " .. o.retraits .. " retraits/j") or "")
	end
	return "fermé"
end

function Opus.Fiche ()
	Msg("fiche des grades (à régler dans Guilde > Paramètres de guilde)" .. (Opus.Restriction() and (", " .. Opus.Restriction().texte) or "") .. " :")
	for rang = 2, #Opus.GRADES do
		local a, oui = Opus.Attendu(rang), {}
		for _, d in ipairs(Opus.DROITS) do
			if a[d.cle] and d.cle ~= "ecouter" and d.cle ~= "parler" and d.cle ~= "retraitOr" then oui[#oui + 1] = d.nom end
		end
		DEFAULT_CHAT_FRAME:AddMessage(("  |cffffd100%s|r : %s ; or %d po/j"):format(Opus.GRADES[rang].nom,
			#oui > 0 and table.concat(oui, ", ") or "écouter et parler seulement", a.or_))
		local onglets = {}
		for t, o in ipairs(a.onglets) do onglets[#onglets + 1] = Opus.ONGLETS[t] .. " " .. Onglet(o) end
		DEFAULT_CHAT_FRAME:AddMessage("    |cffaaaaaa" .. table.concat(onglets, " · ") .. "|r")
	end
end

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

Opus.Commande("controle", "controle", "compare les droits réels à la grille", function () Opus.Rapport() end)
Opus.Commande("fiche", "fiche", "ce qu'il faut régler à la main, grade par grade", function () Opus.Fiche() end)

-- relevé brut de tous les droits, pour vérifier les numéros
Opus.Commande("diag", "diag", "relevé brut des droits de chaque grade", function ()
	for rang = 1, GuildControlGetNumRanks() or 0 do
		local f = Drapeaux(rang) or {}
		local oui = {}
		for i = 1, 22 do if f[i] then oui[#oui + 1] = i end end
		DEFAULT_CHAT_FRAME:AddMessage(("|cffffd100%d %s|r : droits %s"):format(rang, tostring(GuildControlGetRankName(rang)),
			#oui > 0 and table.concat(oui, ",") or "aucun"))
	end
	for i = 1, 22 do
		local s = _G["GUILDCONTROL_OPTION" .. i]
		if s then DEFAULT_CHAT_FRAME:AddMessage(("  %d = %s"):format(i, s:gsub("\n", " "))) end
	end
end)
