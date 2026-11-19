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

-- Date d'entrée en essai : la note d'officier (seuls les officiers la lisent), sinon la date partagée par un officier
-- (Opus.db.arrivees, synchronisée : Partage.lua), sinon le journal de guilde : le passage au grade d'essai, ou l'arrivée.
function Opus.DebutEssai (m)
	local t = LitDate(m.noteOff)
	if t then return t, "note" end
	local partagee = Opus.db.arrivees[m.nom]
	if partagee then return partagee, "partage" end
	-- le journal : son passage au grade d'essai (un Aspirant y a été promu), sinon son arrivée dans la guilde
	local grade = m.montee and m.montee.depuis or m.nomGrade
	local passage = Opus.PassageJournal and Opus.PassageJournal(m.nom, grade)
	if passage then return passage, "journal" end
	local arrivee = Opus.ArriveeJournal and Opus.ArriveeJournal(m.nom)
	if arrivee then return arrivee, "journal" end
	return nil
end

-- retient une date d'essai et la partage aux membres (qui, sans être officiers, ne lisent pas les notes)
function Opus.RetenirArrivee (nom, t)
	if Opus.db.arrivees[nom] == t then return end
	Opus.db.arrivees[nom] = t
	if Opus.PartagerArrivees then Opus.PartagerArrivees({ [nom] = t }) end
end

-- Le jeu promeut d'un grade à la fois : d'Aspirant à Itinérant, on passe par Sédentaire. Une montée commencée est
-- suivie jusqu'au grade visé (ou annulée jusqu'au grade de départ), pour que le membre reste dans la liste entre-temps.
function Opus.Monter (m, cible)
	local suivie = Opus.db.montees[m.nom]
	Opus.db.montees[m.nom] = { depuis = suivie and suivie.depuis or m.nomGrade, cible = cible }
end

local function MonteeEnCours (m)
	local suivie = Opus.db.montees[m.nom]
	if not suivie then return nil end
	local depuis, cible = Opus.RangDe(suivie.depuis), Opus.RangDe(suivie.cible)
	if not depuis or not cible or m.grade <= cible or m.grade >= depuis then
		Opus.db.montees[m.nom] = nil      -- arrivé, ou revenu au grade de départ
		return nil
	end
	return suivie
end

-- liste des essais (et des montées en cours), les plus anciens d'abord
function Opus.Essais ()
	local liste, maintenant = {}, time()
	for _, m in ipairs(Opus.Membres()) do
		local g = Opus.GRADES[m.grade]
		m.montee = MonteeEnCours(m)
		if m.montee then
			g = Opus.GRADES[Opus.RangDe(m.montee.depuis)]
		end
		if g and g.essai and (g.nom == m.nomGrade or m.montee) then
			local debut, source = Opus.DebutEssai(m)
			m.debut, m.source = debut, source
			-- un officier qui lit la date dans la note la transmet à ceux qui ne la voient pas
			if source == "note" then Opus.RetenirArrivee(m.nom, debut) end
			m.essai = g.nom          -- le grade d'essai d'origine, même en pleine montée
			m.duree = Opus.DureeEssai(g.nom)
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
		if bouton then bouton:SetText(reste >= 0 and (OKAY .. " (" .. reste .. ")") or RED_FONT_COLOR:WrapTextInColorCode(-reste .. " de trop")) end
	end,
	EditBoxOnEnterPressed = function (self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function (self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function Opus.Dater (m)
	local debut = Opus.DebutEssai(m) or time()
	Opus.RetenirArrivee(m.nom, debut)
	if Opus.Rafraichir then Opus.Rafraichir() end
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

-- la durée d'un essai : réglage de la guilde (grille, partagée), que seul le chef modifie ; à défaut, l'ancien réglage
-- local d'avant 0.22, puis 14 jours
function Opus.DureeEssai (nomGrade)
	local c, rang = Opus.Config(), Opus.RangDe(nomGrade)
	return c and c.durees and rang and c.durees[rang] or Opus.db.dureeEssai[nomGrade] or 14
end

-- les grades d'essai de la grille, dans l'ordre : { rang, nom }
function Opus.GradesEssai ()
	local liste = {}
	for rang, g in ipairs(Opus.GRADES or {}) do
		if g.essai then liste[#liste + 1] = { rang = rang, nom = g.nom } end
	end
	return liste
end

function Opus.ModifierDureeEssai (nomGrade, jours)
	if not IsGuildLeader() then Msg("seul le chef de guilde modifie la durée des essais.") return false end
	local rang = Opus.RangDe(nomGrade)
	local c = Opus.Config()
	if not rang or not c or not jours or jours < 1 or jours > 365 then return false end
	if c.durees and c.durees[rang] == jours then return true end
	local copie = Opus.Copie(c)
	copie.durees = copie.durees or {}
	copie.durees[rang] = jours
	Opus.EnregistrerConfig(copie)
	Msg("essai " .. nomGrade .. " : " .. jours .. " jours, partagé à la guilde.")
	return true
end

Opus.Commande("duree", "duree <grade d'essai> <jours>", "durée des essais, pour toute la guilde (14 jours par défaut ; chef de guilde)", function (s)
	local qui, n = (s or ""):match("^(.-)%s+(%d+)$")
	for _, g in ipairs(Opus.GradesEssai()) do
		if qui and Opus.Pli and Opus.Pli(g.nom) == Opus.Pli(qui) then Opus.ModifierDureeEssai(g.nom, tonumber(n)) return end
	end
	local noms = {}
	for _, g in ipairs(Opus.GradesEssai()) do noms[#noms + 1] = g.nom:lower() end
	Msg("exemple : /opus duree " .. (noms[1] or "apprenti") .. " 21" .. (#noms > 0 and Opus.Gris(" (grades d'essai : " .. table.concat(noms, ", ") .. ")") or ""))
end)
