-- Essais.lua : suivi des membres à l'essai (Apprenti, Aspirant)
-- La date d'arrivée vit dans la note d'officier (« Essai 18/11/26 »), visible de tous les officiers.
local _, Opus = ...
local Msg = Opus.Msg

local MOTIF = "Essai (%d%d?)/(%d%d?)/(%d%d)"
local NOTE_MAX = 31   -- longueur maximale d'une note de guilde

local function Formate (t) return date("Essai %d/%m/%y", t) end

local function LitDate (note)
	local j, m, a = (note or ""):match(MOTIF)
	if not j then return nil end
	return time({ year = 2000 + tonumber(a), month = tonumber(m), day = tonumber(j), hour = 12 })
end

-- date d'entrée en essai : note d'officier, sinon arrivée vue en jeu
function Opus.DebutEssai (m)
	local t = LitDate(m.noteOff)
	if t then return t, "note" end
	local vu = Opus.db.arrivees[m.nom]
	if vu then return vu, "vu" end
	return nil
end

-- liste des essais, les plus anciens d'abord
function Opus.Essais ()
	local liste, maintenant = {}, time()
	for _, m in ipairs(Opus.Membres()) do
		local g = Opus.GRADES[m.grade]
		if g and g.essai and g.nom == m.nomGrade then
			local debut, source = Opus.DebutEssai(m)
			m.debut, m.source = debut, source
			m.duree = Opus.db.dureeEssai[g.nom] or 14
			m.jours = debut and math.floor((maintenant - debut) / 86400) or nil
			m.echu = m.jours and m.jours >= m.duree
			liste[#liste + 1] = m
		end
	end
	table.sort(liste, function (a, b) return (a.jours or -1) > (b.jours or -1) end)
	return liste
end

-- Écrire une note d'officier est réservé à l'interface de Blizzard (C_GuildInfo.SetNote est protégée) : l'addon
-- retient la date de son côté et prépare le texte de la note, à copier puis coller dans la fiche du membre.

-- longueur en caractères (un « é » compte pour un, pas pour deux octets)
local function Longueur (t) return strlenutf8 and strlenutf8(t) or #t end

StaticPopupDialogs["OPUS_NOTE"] = {
	text = "Note d'officier de |cffffd100%s|r :\nCtrl+C, puis colle-la dans sa fiche (Guilde > clic sur le membre).",
	button1 = OKAY, hasEditBox = true, editBoxWidth = 260,
	OnShow = function (self, d)
		local boite = self.editBox or self.EditBox
		boite:SetText(d.note)
		local trop = Longueur(d.note) - NOTE_MAX
		if trop > 0 then
			Msg(("note de %s trop longue de %d caractère(s) : raccourcis la remarque dans la boîte avant de copier."):format(d.nom, trop))
		end
		boite:HighlightText() boite:SetFocus()
	end,
	-- le bouton compte les caractères restants (la note d'officier en tient 31)
	EditBoxOnTextChanged = function (self)
		local popup = self:GetParent()
		local bouton = popup.button1 or (popup.ButtonContainer and popup.ButtonContainer.Button1)
		local reste = NOTE_MAX - Longueur(self:GetText())
		if bouton then bouton:SetText(reste >= 0 and (OKAY .. " (" .. reste .. ")") or ("|cffff6060" .. -reste .. " de trop|r")) end
	end,
	EditBoxOnEnterPressed = function (self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function (self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function Opus.Dater (m)
	local debut = Opus.DebutEssai(m)
	if not debut then
		debut = time()
		Opus.db.arrivees[m.nom] = debut
		if Opus.Rafraichir then Opus.Rafraichir() end
	end
	local reste = (m.noteOff or ""):gsub(MOTIF, ""):gsub("^%s+", ""):gsub("%s+$", "")
	local note = Formate(debut)
	if reste ~= "" then note = note .. " " .. reste end
	StaticPopup_Show("OPUS_NOTE", m.nom, nil, { nom = m.nom, note = note })
end

------------------------------------------------------------------------
-- arrivées vues en jeu
------------------------------------------------------------------------

local function MotifDe (fmt)
	if not fmt then return nil end
	return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
end

Opus.Ecoute("CHAT_MSG_SYSTEM", function (texte)
	local motif = MotifDe(ERR_GUILD_JOIN_S)
	local nom = motif and texte:match(motif)
	if not nom or not Opus.db then return end
	nom = Opus.Court(nom)
	Opus.db.arrivees[nom] = time()
	Msg(nom .. " a rejoint la guilde : à dater dans la fenêtre des essais (/opus).")
end)

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

Opus.Commande("essais", "essais", "liste des membres à l'essai dans la discussion", function ()
	local liste = Opus.Essais()
	if #liste == 0 then Msg("aucun membre à l'essai.") return end
	Msg(#liste .. " membre(s) à l'essai :")
	for _, m in ipairs(liste) do
		local etat = m.jours and (("%d j / %d"):format(m.jours, m.duree) .. (m.echu and " |cffff6060échu|r" or "")) or "|cffaaaaaadate inconnue|r"
		DEFAULT_CHAT_FRAME:AddMessage(("  %s (%s) — %s"):format(m.nom, m.nomGrade, etat))
	end
end)

Opus.Commande("duree", "duree apprenti|aspirant <jours>", "durée des essais (14 jours par défaut)", function (s)
	local qui, n = s:lower():match("^(%a+)%s+(%d+)$")
	local nom = (qui == "apprenti" and "Apprenti") or (qui == "aspirant" and "Aspirant")
	if not nom then Msg("exemple : /opus duree apprenti 21") return end
	Opus.db.dureeEssai[nom] = tonumber(n)
	Msg("essai " .. nom .. " : " .. n .. " jours.")
end)
