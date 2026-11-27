-- RaidVote.lua : chez chaque joueur, la fenêtre des annonces du maître du butin, pour objecter et voter d'un clic
-- Elle s'ouvre à la première annonce et se referme quand tout est attribué. Un candidat à l'objet peut objecter, pas
-- voter. Le canal raid (« !objection »…) reste possible : le maître du butin compte une voix par joueur.
local _, Opus = ...
local Raid = Opus.Raid

local GARDER = 20                   -- secondes d'affichage d'un résultat

Raid.annonces = {}                  -- reçues, dans l'ordre : { ml, n, id, lien, propose, etat, fin, candidat, monVote… }

local f, lignes = nil, {}
local masquee = false               -- fermée par le joueur : elle ne revient qu'à la prochaine annonce

local function Trouver (ml, n)
	for _, a in ipairs(Raid.annonces) do if a.ml == ml and a.n == n then return a end end
end

local function Chrono (a)
	local reste = math.max(0, math.floor((a.fin or 0) - GetTime()))
	return string.format("%d:%02d", math.floor(reste / 60), reste % 60)
end

-- ce que l'objet m'apporterait, d'après Pawn (s'il est là) : « pour toi : +53 % (Équilibre) »
local function PourMoi (a)
	if not Raid.GainPawn or not Raid.Comparer then return "" end
	local _, classe = UnitClass("player")
	local g = Raid.GainPawn(Raid.Comparer(Raid.MonNom(), a.id), a.id, a.lien, classe)
	if not g then return "" end
	local p = math.floor(math.abs(g.pct) + 0.5)
	local texte = g.vide and "|cff40ff40emplacement vide|r" or p == 0 and "=" or ((g.pct > 0 and "|cff40ff40+" or "|cffff5a5a−") .. p .. " %|r")
	return "pour toi : " .. texte .. " (" .. g.spe .. ")"
end

-- L'état d'une annonce : sa pastille (texte, sens, comme dans la fenêtre du butin) et la ligne de détail.
local function Etat (a)
	if a.etat == "delai" then
		return "objections " .. Chrono(a), "cours", "proposé : |cffffffff" .. (a.propose or "?") .. "|r" .. (a.candidat and " · tu es candidat" or "")
	end
	if a.etat == "vote" then
		return "vote " .. Chrono(a), "cours", "objection de " .. (a.auteur or "?") .. (a.motif and (" (« " .. a.motif .. " »)") or "")
			.. (a.candidat and " · candidat, tu ne votes pas" or a.monVote and (" · ton vote : |cffffffff" .. a.monVote .. "|r") or " · à qui ?")
	end
	if a.etat == "sk" then
		local moi = PourMoi(a)
		return "Suicide King " .. Chrono(a), "cours", (a.veut and "tu es sur les rangs" or "hors liste") .. (moi ~= "" and (" · " .. moi) or "")
	end
	if a.etat == "attribue" then return "attribué", "fait", "à |cffffffff" .. (a.attributaire ~= "" and a.attributaire or "?") .. "|r" end
	if a.etat == "trancher" then return "aux officiers", "afaire", "égalité au vote : les officiers tranchent" end
	if a.etat == "de" then return "désenchanté", "de", a.attributaire ~= "" and ("par " .. a.attributaire) or "" end
	if a.etat == "banque" then return "banque", "neutre", "pour la banque de guilde" end
	return nil, nil, ""
end

local LARGEUR = 500

local function Construire ()
	f = Raid.Cadre("OpusRaidVote")
	f:SetSize(LARGEUR, 100) f:SetPoint("TOP", 0, -120)
	f:SetTitle("Opus : attributions")
	f:Hide()
	-- fermée (croix, Échap) avec des annonces en cours : elle attend la suivante
	tinsert(UISpecialFrames, "OpusRaidVote")
	f:SetScript("OnHide", function () masquee = #Raid.annonces > 0 end)
end

local function Repondre (mot, n, chat, quoi)
	if not Raid.Repondre(mot, n, quoi) then SendChatMessage(chat, IsInRaid() and "RAID" or "PARTY") end
end

local function Ligne (k)
	if lignes[k] then return lignes[k] end
	local l = CreateFrame("Frame", nil, f.Inset)
	l:SetSize(LARGEUR - 28, 44)
	l.icone = Raid.Icone(l, 36)
	l.icone:SetPoint("TOPLEFT", 0, -2)
	l.objet = CreateFrame("Button", nil, l)
	l.objet:SetSize(230, 16) l.objet:SetPoint("TOPLEFT", 44, -2)
	l.objet.texte = l.objet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.objet.texte:SetPoint("LEFT") l.objet.texte:SetJustifyH("LEFT") l.objet.texte:SetWordWrap(false)
	l.objet:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lien, self.id) end)
	l.objet:SetScript("OnLeave", GameTooltip_Hide)
	l.pastille = Raid.Pastille(l)
	l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.etat:SetPoint("TOPLEFT", 44, -21) l.etat:SetJustifyH("LEFT") l.etat:SetWordWrap(false)
	l.compte = Raid.Compte(l, 250)
	l.compte:SetPoint("TOPLEFT", 44, -37)
	l.objecter = Raid.Bouton(l, "Objecter", 90, function (self)
		Repondre("O", self.annonce.n, "!objection " .. self.annonce.n)
		self.annonce.objecte = true
		Raid.RafraichirVote()
	end, "sec")
	l.objecter:SetPoint("TOPRIGHT", 0, -8)
	l.veux = Raid.Bouton(l, "Je le veux", 100, function (self)
		Repondre("W", self.annonce.n, "!sk " .. self.annonce.n)
		self.annonce.veut = true
		Raid.RafraichirVote()
	end, "prim")
	l.veux:SetPoint("TOPRIGHT", 0, -8)
	-- « Passer » : pas intéressé par ce Suicide King ; le maître du butin le sait (le tour finit quand tous ont répondu),
	-- et la ligne s'en va
	l.passer = Raid.Bouton(l, "Passer", 70, function (self)
		local a = self.annonce
		Repondre("X", a.n, "!passe " .. a.n)
		a.finie = GetTime() - GARDER - 1
		Raid.RafraichirVote()
	end, "sec")
	l.passer:SetPoint("RIGHT", l.veux, "LEFT", -6, 0)
	-- le vote : un bouton par candidat, sous la ligne (créés à la demande)
	l.choix = {}
	lignes[k] = l
	return l
end

local PAR_RANG, LARGE_CHOIX = 3, 140

local function BoutonChoix (l, i)
	if l.choix[i] then return l.choix[i] end
	local b = Raid.Bouton(l, "", LARGE_CHOIX, function (self)
		local a = self.annonce
		Repondre("B", a.n, "!vote " .. a.n .. " " .. self.numero, self.nom)
		a.monVote = self.nom
		Raid.RafraichirVote()
	end, "sec")
	-- ce que le candidat porte à cet emplacement, face à l'objet
	b.bulle = function (self)
		Raid.Ancrer(self)
		GameTooltip:AddLine(self.nom, 1, 1, 1)
		Raid.InfobulleEquipement(self.nom, self.annonce.id, self.annonce.lien)
		GameTooltip:AddLine(self.annonce.monVote == self.nom and "Ton vote." or "Clic : voter pour lui.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end
	l.choix[i] = b
	return b
end

function Raid.RafraichirVote ()
	-- les résultats s'effacent après un moment
	for k = #Raid.annonces, 1, -1 do
		local a = Raid.annonces[k]
		if a.finie and GetTime() - a.finie > GARDER then table.remove(Raid.annonces, k) end
	end
	if #Raid.annonces == 0 then masquee = false if f then f:Hide() end return end
	if not f then Construire() end
	if masquee then return end
	for _, l in ipairs(lignes) do l:Hide() end
	local y = 8
	for k, a in ipairs(Raid.annonces) do
		local l = Ligne(k)
		a.lien = Raid.LienAJour(a.lien, a.id)
		l.objet.lien, l.objet.id = a.lien, a.id
		l.objet.texte:SetText((a.lien:gsub("%[(.-)%]", "%1")))
		Raid.PoserIcone(l.icone, a.id, a.lien)
		local texte, sens, detail = Etat(a)
		l.pastille:ClearAllPoints()
		l.pastille:SetPoint("TOPLEFT", 44 + math.min(l.objet.texte:GetStringWidth(), 230) + 8, -1)
		Raid.PoserPastille(l.pastille, texte, sens)
		l.etat:SetText(detail)
		Raid.PoserCompte(l.compte, (a.etat == "delai" or a.etat == "vote" or a.etat == "sk") and a or nil)
		l.objecter.annonce, l.veux.annonce, l.passer.annonce = a, a, a
		l.veux:SetShown(a.etat == "sk")
		l.veux:SetEnabled(not a.veut)
		l.veux:SetText(a.veut and "Sur les rangs" or "Je le veux")
		l.veux.raison = "Tu es sur les rangs : le mieux placé dans la liste Suicide King gagne."
		l.passer:SetShown(a.etat == "sk" and not a.veut)
		l.objecter:SetShown(a.etat == "delai")
		l.objecter:SetEnabled(not a.objecte)
		l.objecter:SetText(a.objecte and "Objecté" or "Objecter")
		l.objecter.raison = "Ton objection est partie."
		-- le détail prend la place que les boutons laissent
		l.etat:SetWidth(l.passer:IsShown() and 230 or (l.veux:IsShown() or l.objecter:IsShown()) and 320 or LARGEUR - 80)
		local vote = a.etat == "vote" and not a.candidat and a.choix and #a.choix > 0
		for _, b in ipairs(l.choix) do b:Hide() end
		local rangs = 0
		if vote then
			for i, nom in ipairs(a.choix) do
				local b = BoutonChoix(l, i)
				b.annonce, b.nom, b.numero = a, nom, i
				b:SetText(i .. ". " .. nom)
				b:SetGenre(a.monVote == nom and "prim" or "sec")
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 44 + ((i - 1) % PAR_RANG) * (LARGE_CHOIX + 6), -46 - math.floor((i - 1) / PAR_RANG) * 26)
				b:Show()
			end
			rangs = math.ceil(#a.choix / PAR_RANG)
		end
		l:ClearAllPoints() l:SetPoint("TOPLEFT", 10, -y)
		l:SetHeight(44 + rangs * 26)
		y = y + 48 + rangs * 26
		l:Show()
	end
	f:SetHeight(y + 30)
	f:Show()
end

-- un message du maître du butin (Comm.lua)
function Raid.RecevoirAnnonce (ml, c)
	local genre, n = c[1], tonumber(c[2])
	if not n then return end
	if genre == "S" then
		local id, secondes = tonumber(c[3]), tonumber(c[4])
		if not id or not secondes then return end
		local a = Trouver(ml, n)
		if not a then
			a = { ml = ml, n = n, id = id, lien = Raid.LienDe(id), propose = "" }
			Raid.annonces[#Raid.annonces + 1] = a
			masquee = false
		end
		a.etat, a.fin, a.duree = "sk", GetTime() + secondes, secondes
		if c[5] and c[5]:find("^item:") then a.chaine = c[5] end
	elseif genre == "A" then
		local id, secondes = tonumber(c[3]), tonumber(c[5])
		if not id or not secondes or Trouver(ml, n) then return end
		local moi, candidat = Raid.MonNom(), false
		for _, nom in ipairs(Raid.Liste(c[6])) do if nom == moi then candidat = true end end
		Raid.annonces[#Raid.annonces + 1] = { ml = ml, n = n, id = id, lien = Raid.LienDe(id), propose = c[4] or "?", etat = "delai", fin = GetTime() + secondes, duree = secondes, candidat = candidat,
			candidats = Raid.Liste(c[6]), chaine = (c[7] and c[7]:find("^item:")) and c[7] or nil }
		masquee = false
		-- leur équipement, pour comparer au moment du vote
		Raid.Prioriser(Raid.Liste(c[6]))
	else
		local a = Trouver(ml, n)
		-- un résultat d'une annonce qu'on n'a pas vue (rechargement, arrivée en cours de soirée) : il entre, déjà ancien
		if not a and genre == "R" and tonumber(c[5]) then
			a = { ml = ml, n = n, id = tonumber(c[5]), lien = Raid.LienDe(tonumber(c[5])), propose = "", resync = true }
			Raid.annonces[#Raid.annonces + 1] = a
		end
		if not a then return end
		if genre == "V" then
			masquee = false   -- un vote s'ouvre : la fenêtre revient, il faut pouvoir voter
			a.etat, a.fin, a.auteur, a.duree = "vote", GetTime() + (tonumber(c[3]) or 0), c[6], tonumber(c[3])
			a.choix = Raid.Liste(c[7])
			a.motif = (c[8] and c[8] ~= "") and c[8] or nil
		elseif genre == "K" then
			a.declares = Raid.Liste(c[3])
		elseif genre == "R" then
			a.avant = a.etat            -- d'où vient le résultat : délai sans objection, vote, Suicide King
			a.etat, a.attributaire = c[3] or "", c[4] or ""
			-- un résultat repris (rechargement) n'a pas à sortir de banderole
			if a.etat ~= "trancher" then a.finie = GetTime() - (a.resync and 30 or 0) end
		end
	end
	Raid.RafraichirVote()
end

-- comptes à rebours, effacement des résultats, noms d'objets arrivés après coup
C_Timer.NewTicker(1, function () if #Raid.annonces > 0 then Raid.RafraichirVote() end end)
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function (id)
	for _, a in ipairs(Raid.annonces) do
		if a.id == id and not a.lien:find("|H", 1, true) then a.lien = Raid.LienDe(id) end
	end
end)
