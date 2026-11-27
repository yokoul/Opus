-- RaidButin.lua : quand le maître du butin ouvre un corps, la proposition de chaque objet, et son annonce au raid
-- L'annonce part sur un clic (ou une commande tapée) : le jeu restreint les messages qu'un addon envoie de lui-même.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

-- La police des fenêtres du jeu n'a pas les flèches (« → » s'affiche en carré) : « » » partout, même dans le canal raid.
local MAX_ANNONCE = 250             -- le jeu refuse un message de discussion au-delà de 255 octets

local function ItemID (lien) return tonumber((lien or ""):match("item:(%d+)")) end

-- Le texte annoncé au raid pour un objet : le proposé, puis les suivants tant que le message tient, et la fin donnée
-- (la consigne d'objection, Attribution.lua).
function Raid.TexteAnnonce (lien, r, fin)
	if not r then return nil end
	if #r.candidats == 0 then
		if #r.absents > 0 then
			return lien .. " : " .. (#r.absents > 1 and #r.absents .. " candidats en wishlist, absents" or "le seul candidat en wishlist est absent") .. " » Suicide King."
		end
		return lien .. " : dans aucune wishlist » Suicide King."
	end
	local c1 = r.candidats[1]
	local texte = lien .. " » " .. c1.nom .. " (" .. Raid.Score(c1.score) .. ", rang " .. c1.rang .. ")"
	if r.egalite then texte = texte .. " ex aequo, le maître du butin tranche" end
	fin = "." .. (fin or string.format(" Objection possible %s.", Raid.TexteDuree(Raid.Duree("objection"))))
	local suite = {}
	for n = 2, #r.candidats do
		local c = r.candidats[n]
		local essai = " Puis : " .. table.concat(suite, ", ") .. (#suite > 0 and ", " or "") .. c.nom .. " (" .. Raid.Score(c.score) .. ")"
		if #texte + #essai + #fin > MAX_ANNONCE then break end
		suite[#suite + 1] = c.nom .. " (" .. Raid.Score(c.score) .. ")"
	end
	if #suite > 0 then texte = texte .. ". Puis : " .. table.concat(suite, ", ") end
	if #(texte .. fin) > MAX_ANNONCE then return texte .. fin:sub(1, MAX_ANNONCE - #texte) end
	return texte .. fin
end

-- au raid, au groupe, ou dans sa seule fenêtre de discussion hors groupe (pour essayer)
function Raid.Annoncer (texte)
	local canal = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
	-- le jeu refuse un message trop long : on coupe la fin (un motif long), jamais le lien du début
	texte = "[Opus] " .. texte
	if #texte > 255 then texte = texte:sub(1, 252):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
	if canal then SendChatMessage(texte, canal) else Msg("(hors groupe, rien n'est envoyé) " .. texte:sub(8)) end
end

-- le détail du calcul, pour le maître du butin seulement
local function Detail (lien, r)
	Msg(lien .. " : " .. (#r.candidats == 0 and "aucun candidat présent." or ("proposition à " .. r.candidats[1].nom .. (r.egalite and " (ex aequo)" or "") .. ".")))
	for _, c in ipairs(r.candidats) do
		local t = c.termes
		DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (%s, %s) — %s : rang %d (prio %.2f), prios perdues %.2f, dernier loot %.2f, gain %.2f",
			c.nom, c.role, c.perso, Raid.Score(c.score), c.rang, t.perso, t.perdues, t.dernier, t.gain))
	end
	if #r.absents > 0 then DEFAULT_CHAT_FRAME:AddMessage("  absents : " .. table.concat(r.absents, ", ")) end
end

------------------------------------------------------------------------
-- la fenêtre du butin : les objets du corps ouvert, leur proposition, « Annoncer »
------------------------------------------------------------------------

local f, lignes = nil, {}
local relance = false               -- un rafraîchissement déjà prévu (noms d'objets attendus)
local objets = {}                   -- { lien, id, slot, source, attribution } du dernier corps ouvert
local corpsOuvert = false           -- la fenêtre de butin du jeu est ouverte : « Donner » est possible
local attente = {}                  -- [slot] = { a, dest } : donné par le menu du maître du butin, en attente du jeu

-- Ce qui est attribué et attend encore sur le corps ouvert : Opus le donne tout seul (comme Gargul), par le menu du
-- maître du butin, dès l'attribution si le corps est ouvert, sinon quand on le rouvre. « Donner » ne reste qu'après
-- un refus du jeu (gagnant trop loin, pas éligible…), pour réessayer.
local function ADonner (o)
	local a = o.attribution
	return a and corpsOuvert and o.slot and not a.donne and (a.etat == "attribue" or a.etat == "de" or a.etat == "banque")
end
local function Destinataire (a)
	if a.etat == "banque" or not a.attributaire or a.attributaire == "" then return Raid.MonNom() end
	return a.attributaire
end

local LARGEUR = 600
local HAUT_LIGNE = 48

local function Construire ()
	f = Raid.Cadre("OpusRaidButin")
	f:SetSize(LARGEUR, 120) f:SetPoint("TOPLEFT", 260, -140)
	f:SetTitle("Opus : butin")
	-- à droite du titre : le boss et ce qui reste à faire sur ce corps
	f.resume = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.resume:SetPoint("TOPRIGHT", -32, -10) f.resume:SetJustifyH("RIGHT")
	-- en bas : le désenchanteur de la soirée (parmi les présents, sinon la liste de l'instantané) et les réglages en cours
	f.filetBas = f.Inset:CreateTexture(nil, "ARTWORK")
	f.filetBas:SetHeight(1) f.filetBas:SetPoint("BOTTOMLEFT", 8, 34) f.filetBas:SetPoint("BOTTOMRIGHT", -8, 34)
	f.filetBas:SetColorTexture(0.83, 0.69, 0.22, 0.28)
	f.deTexte = f.Inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.deTexte:SetPoint("BOTTOMLEFT", 12, 13) f.deTexte:SetText("Désenchanteur")
	f.deChoix = {}
	f.deMenu = Opus.Menu(f.Inset, 200, f.deChoix,
		function () return Raid.db.reglages.desenchanteur or "" end,
		function (v) Raid.db.reglages.desenchanteur = v ~= "" and v or nil Raid.RafraichirButin() end)
	f.deMenu:SetPoint("LEFT", f.deTexte, "RIGHT", 8, 0)
	f.reglages = f.Inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.reglages:SetPoint("BOTTOMRIGHT", -12, 13) f.reglages:SetJustifyH("RIGHT")
	tinsert(UISpecialFrames, "OpusRaidButin")
	f:Hide()
end

local function Chrono (a)
	local reste = math.max(0, math.floor((a.fin or 0) - GetTime()))
	return string.format("%d:%02d", math.floor(reste / 60), reste % 60)
end

-- l'action principale d'une ligne : donner, trancher, ou annoncer
local function Principal (self)
	local o = self.objet
	if not o then return end
	if ADonner(o) then Raid.Donner(o) return end
	local a = o.attribution
	if a and a.etat == "trancher" then Raid.OuvrirDecision(a) return end
	if not a then Raid.AnnoncerObjet(o) end
end

local function BullePrincipal (self)
	local o = self.objet
	if not o then return end
	Raid.Ancrer(self)
	if ADonner(o) then
		GameTooltip:AddLine("Donner à " .. Destinataire(o.attribution), 1, 1, 1)
		GameTooltip:AddLine("Par le menu du maître du butin, sans échange. La remise est notée au rapport.", nil, nil, nil, true)
	elseif o.attribution and o.attribution.etat == "trancher" then
		GameTooltip:AddLine("Trancher", 1, 1, 1)
		GameTooltip:AddLine("Égalité au vote : les officiers décident, avec un motif.", nil, nil, nil, true)
	elseif not self:IsEnabled() then
		GameTooltip:AddLine(self.raison or "", 1, 1, 1, true)
	else
		GameTooltip:AddLine("Annoncer au raid", 1, 1, 1)
		GameTooltip:AddLine(Raid.TexteAnnonce(o.lien, Raid.Proposer(o.id, Raid.Presents())) or "", nil, nil, nil, true)
		GameTooltip:AddLine("Puis " .. Raid.TexteDuree(Raid.Duree("objection")) .. " pour objecter (« !objection »), et un vote s'il y a objection.", nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function Ligne (n)
	if lignes[n] then return lignes[n] end
	local l = CreateFrame("Frame", nil, f.Inset)
	l:SetSize(LARGEUR - 28, HAUT_LIGNE - 4) l:SetPoint("TOPLEFT", 10, -8 - (n - 1) * HAUT_LIGNE)
	l.icone = Raid.Icone(l, 36)
	l.icone:SetPoint("LEFT", 0, 0)
	l.objet = CreateFrame("Button", nil, l)
	l.objet:SetSize(230, 16) l.objet:SetPoint("TOPLEFT", 44, -2)
	l.objet.texte = l.objet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.objet.texte:SetPoint("LEFT") l.objet.texte:SetJustifyH("LEFT") l.objet.texte:SetWordWrap(false)
	l.objet:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lien, self.id) end)
	l.objet:SetScript("OnLeave", GameTooltip_Hide)
	l.etat = Raid.Pastille(l)
	l.detail = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.detail:SetPoint("TOPLEFT", 44, -21) l.detail:SetWidth(300) l.detail:SetJustifyH("LEFT") l.detail:SetWordWrap(false)
	l.compte = Raid.Compte(l, 300)
	l.compte:SetPoint("TOPLEFT", 44, -37)
	l.principal = Raid.Bouton(l, "Annoncer", 92, Principal, "prim")
	l.principal.bulle = BullePrincipal
	-- les détails de l'objet (RaidFiche.lua) : les candidats, leurs scores, ce qu'ils portent, ce qu'ils ont reçu
	l.fiche = Raid.Bouton(l, "Détails", 70, function (self) Raid.OuvrirFiche(self.objet) end, "sec")
	l.fiche.bulle = function (self)
		Raid.Ancrer(self)
		GameTooltip:AddLine("Détails de l'objet", 1, 1, 1)
		GameTooltip:AddLine("Les candidats présents (ou, hors liste, ceux qui peuvent le porter), leur score, ce qu'ils portent et ce que l'objet leur changerait, ce qu'ils ont déjà reçu.", nil, nil, nil, true)
		GameTooltip:Show()
	end
	-- « Désenchanter » : hors liste, droit au désenchanteur, sans annonce
	l.de = Raid.Bouton(l, "Désenchanter", 96, function (self)
		local o = self.objet
		if not o or o.attribution then return end
		local a = Raid.DesenchanterObjet(o)
		if a then o.attribution = a end
		Raid.RafraichirButin()
	end, "sec")
	l.de.bulle = function (self)
		Raid.Ancrer(self)
		GameTooltip:AddLine("Désenchanter", 1, 1, 1)
		if not self:IsEnabled() then GameTooltip:AddLine(self.raison or "", nil, nil, nil, true)
		else
			local qui = Raid.Desenchanteur()
			GameTooltip:AddLine(qui and ("Donné à " .. qui .. ", sans annonce ni Suicide King. Noté au rapport.")
				or "Aucun désenchanteur présent : l'objet ira à la banque (à toi). Choisis-en un en bas de la fenêtre.", nil, nil, nil, true)
		end
		GameTooltip:Show()
	end
	lignes[n] = l
	return l
end

-- les boutons visibles, posés de droite à gauche
local function Ranger (l)
	local precedent
	for _, b in ipairs({ l.principal, l.fiche, l.de }) do
		if b:IsShown() then
			b:ClearAllPoints()
			if precedent then b:SetPoint("RIGHT", precedent, "LEFT", -6, 0) else b:SetPoint("RIGHT", 0, 0) end
			precedent = b
		end
	end
end

-- L'état d'un objet : sa pastille (texte, sens), la ligne de détail, et l'action principale ({ texte, actif, raison }).
local function EtatObjet (o, presents)
	local a = o.attribution
	if not a then
		local r = Raid.Proposer(o.id, presents)
		local c1 = r and r.candidats[1]
		if not r then return "sans liste", "afaire", "pas d'instantané : l'annonce lance un Suicide King", { "Annoncer", true }, r end
		if c1 then
			local autres = #r.candidats - 1
			return "en liste", "neutre", "proposé : |cffffffff" .. c1.nom .. "|r · " .. Raid.Score(c1.score) .. (r.egalite and " (ex aequo)" or "")
				.. (autres > 0 and (" · " .. autres .. " autre" .. (autres > 1 and "s" or "")) or ""), { "Annoncer", true }, r
		end
		return "hors liste", "neutre", "personne de présent ne l'a en liste : Suicide King, ou désenchanter", { "Annoncer", true }, r
	end
	local dest = a.attributaire and a.attributaire ~= "" and a.attributaire
	if ADonner(o) then
		return "à donner", "afaire", "#" .. a.n .. " » |cffffffff" .. Destinataire(a) .. "|r" .. (o.tente and " · encore sur le corps : réessaie, ou remets-le par échange" or ""), { "Donner", true }
	end
	if a.etat == "delai" then return "objections " .. Chrono(a), "cours", "proposé : |cffffffff" .. (a.propose or "?") .. "|r" end
	if a.etat == "vote" then return "vote " .. Chrono(a), "cours", (Raid.EtatAttribution(a):gsub("^#%d+ ", ""):gsub("^vote %d+:%d+ ?:? ?", "")) end
	if a.etat == "sk" then
		local n = 0
		for _ in pairs(a.interesses or {}) do n = n + 1 end
		local tete = Raid.ClassementSK and Raid.ClassementSK(a)[1]
		return "Suicide King " .. Chrono(a), "cours", (n == 0 and "personne de déclaré" or (n .. " déclaré" .. (n > 1 and "s" or "")))
			.. (tete and (" · en tête : |cffffffff" .. tete .. "|r") or "")
	end
	if a.etat == "trancher" then return "à trancher", "afaire", "égalité au vote : aux officiers", { "Trancher…", true } end
	if a.etat == "banque" then return "banque", "neutre", "#" .. a.n .. " » banque de guilde" end
	local vers = a.etat == "de" and ("désenchantement (" .. (dest or "?") .. ")") or (dest or "?")
	if a.remis then return "remis", "fait", "#" .. a.n .. " » |cffffffff" .. vers .. "|r" .. (a.remis ~= a.attributaire and (" · remis à " .. a.remis) or "") end
	return "à remettre", "afaire", "#" .. a.n .. " » |cffffffff" .. vers .. "|r · par échange"
end

-- Met les lignes à jour : avant l'annonce, la proposition ; après, l'état de l'attribution (délai, vote…).
function Raid.RafraichirButin ()
	-- attribué et sur le corps ouvert : on le donne, une fois (un refus laisse le bouton « Donner »), fenêtre ou volet
	for _, o in ipairs(objets) do
		if ADonner(o) and not o.tente then o.tente = true Raid.Donner(o) end
	end
	if not f or not f:IsShown() then
		if Raid.RafraichirFiche then Raid.RafraichirFiche() end
		return
	end
	local presents = Raid.Presents()
	local attendre = false
	-- les choix du désenchanteur : « Auto » (la liste de l'instantané) et les présents
	wipe(f.deChoix)
	local i = Raid.db.instantane
	local auto
	for _, nom in ipairs(i and i.de or {}) do if not presents or presents[nom] then auto = nom break end end
	f.deChoix[1] = { "", "Auto" .. (auto and (" (" .. auto .. ")") or " (personne : banque)") }
	local noms = {}
	for nom in pairs(presents or { [Raid.MonNom()] = true }) do noms[#noms + 1] = nom end
	table.sort(noms)
	for _, nom in ipairs(noms) do f.deChoix[#f.deChoix + 1] = { nom, nom } end
	f.deMenu:GenerateMenu()
	f.reglages:SetText((Raid.Detaillees() and "annonces détaillées" or "annonces courtes") .. " · Suicide King " .. Raid.TexteDuree(Raid.Duree("sk")))
	local enCours, aAnnoncer, aFaire = 0, 0, 0
	for n, o in ipairs(objets) do
		local l = Ligne(n)
		local a = o.attribution
		o.lien = Raid.LienAJour(o.lien, o.id)
		if not o.lien:find("|H", 1, true) then attendre = true end
		l.objet.id, l.objet.lien = o.id, o.lien
		l.principal.objet, l.fiche.objet, l.de.objet = o, o, o
		Raid.PoserIcone(l.icone, o.id, o.lien)
		-- le nom sans crochets, dans la couleur de sa qualité ; la pastille juste après
		l.objet.texte:SetText((o.lien:gsub("%[(.-)%]", "%1")))
		l.etat:ClearAllPoints()
		l.etat:SetPoint("TOPLEFT", 44 + math.min(l.objet.texte:GetStringWidth(), 230) + 8, -1)
		local etat, sens, detail, action, r = EtatObjet(o, presents)
		Raid.PoserPastille(l.etat, etat, sens)
		l.detail:SetText(detail or "")
		Raid.PoserCompte(l.compte, (a and (a.etat == "delai" or a.etat == "vote" or a.etat == "sk")) and a or nil)
		l.principal:SetShown(action ~= nil)
		if action then
			l.principal:SetText(action[1]) l.principal:SetEnabled(action[2]) l.principal.raison = action[3]
		end
		l.fiche:Show()
		l.de:SetShown(not a)
		if not a then
			local libre = r == nil or #r.candidats == 0
			l.de:SetEnabled(libre)
			l.de.raison = not libre and ("En liste chez " .. r.candidats[1].nom .. " : annonce-le.") or nil
		end
		Ranger(l)
		if not a then aAnnoncer = aAnnoncer + 1
		elseif sens == "cours" then enCours = enCours + 1
		elseif sens == "afaire" then aFaire = aFaire + 1 end
		l:Show()
	end
	local morceaux = {}
	if Raid.dernierBoss and Raid.dernierBoss ~= "" then morceaux[1] = Raid.dernierBoss end
	morceaux[#morceaux + 1] = #objets .. " objet" .. (#objets > 1 and "s" or "")
	if enCours > 0 then morceaux[#morceaux + 1] = enCours .. " en cours" end
	if aAnnoncer > 0 then morceaux[#morceaux + 1] = aAnnoncer .. " à annoncer" end
	if aFaire > 0 then morceaux[#morceaux + 1] = "|cffffcc33" .. aFaire .. " à faire|r" end
	f.resume:SetText(table.concat(morceaux, " · "))
	if Raid.RafraichirFiche then Raid.RafraichirFiche() end
	-- un nom pas encore reçu du serveur : on repasse dans un instant
	if attendre and not relance then
		relance = true
		C_Timer.After(1, function () relance = false Raid.RafraichirButin() end)
	end
end

-- Annonce l'objet d'une ligne de la fenêtre (ou de sa fiche) et lance le délai d'objection.
function Raid.AnnoncerObjet (o)
	if o.attribution then return end
	local a = Raid.Lancer(o)
	if a then o.attribution = a end
	Raid.RafraichirButin()
end

function Raid.MontrerButin ()
	if not f then Construire() end
	for _, l in ipairs(lignes) do l:Hide() end
	if #objets == 0 then Msg("aucun objet relevé : ouvre le corps du boss en maître du butin.") f:Hide() return end
	f:SetHeight(84 + #objets * HAUT_LIGNE)
	f:Show()
	Raid.RafraichirButin()
end

-- les comptes à rebours de la fenêtre
C_Timer.NewTicker(1, function ()
	for _, o in ipairs(objets) do
		if o.attribution and (o.attribution.etat == "delai" or o.attribution.etat == "vote" or o.attribution.etat == "sk") then Raid.RafraichirButin() return end
	end
end)

-- l'emplacement actuel d'un objet sur le corps ouvert (il bouge quand on en ramasse un autre)
local function SlotDe (o)
	for slot = 1, GetNumLootItems() or 0 do
		local source = GetLootSourceInfo and GetLootSourceInfo(slot)
		if ItemID(GetLootSlotLink(slot)) == o.id and source == o.source then return slot end
	end
end

-- l'objet attribué passe au gagnant (ou au maître du butin pour la banque) par le menu du maître du butin
function Raid.Donner (o)
	local a = o.attribution
	local dest = Destinataire(a)
	local slot = corpsOuvert and SlotDe(o)
	if not slot or not GetMasterLootCandidate or not GiveMasterLoot then return end
	for i = 1, 40 do
		local c = GetMasterLootCandidate(slot, i)
		if c and Raid.Court(c) == dest then
			attente[slot] = { a = a, dest = dest }
			GiveMasterLoot(slot, i)
			return
		end
	end
	Msg(dest .. " ne peut pas recevoir " .. o.lien .. " depuis ce corps (trop loin, hors ligne ou pas éligible). « Donner » pour réessayer, ou ramasse-le et remets-le par échange.")
end

------------------------------------------------------------------------
-- les règles fixes du maître du butin : « tous les scarabées vont chez Bob ». Une règle vise un objet (son numéro) ou
-- un morceau de nom (« scarabée ») ; elle l'envoie à un joueur, au désenchanteur (« de ») ou au maître du butin
-- (« banque »). À l'ouverture d'un corps, ces objets partent tout seuls, sans annonce ; il faut que le seuil de butin
-- du groupe les laisse au maître du butin (un objet sous le seuil ne se donne pas par son menu).
------------------------------------------------------------------------

local function Regles ()
	Raid.db.reglages.regles = Raid.db.reglages.regles or {}
	return Raid.db.reglages.regles
end
local function RegleDe (id, nom)
	local bas = (nom or ""):lower()
	for _, r in ipairs(Regles()) do
		if (r.id and r.id == id) or (r.motif and bas ~= "" and bas:find(r.motif, 1, true)) then return r end
	end
end
-- à qui va l'objet d'une règle : le joueur s'il est là, le désenchanteur, ou le maître du butin ; nil s'il manque
local function DestinationDe (r)
	local presents = Raid.Presents()
	if r.dest == "de" then return Raid.Desenchanteur() or Raid.MonNom() end
	if r.dest == "banque" or r.dest == "moi" then return Raid.MonNom() end
	if not presents or presents[r.dest] then return r.dest end
end
local function DonnerSlot (slot, dest)
	if not GetMasterLootCandidate or not GiveMasterLoot then return false end
	for i = 1, 40 do
		local c = GetMasterLootCandidate(slot, i)
		if c and Raid.Court(c) == dest then GiveMasterLoot(slot, i) return true end
	end
	return false
end
-- appliquées aux objets du corps ouvert ; rend ceux qui restent à traiter à la main
local function AppliquerRegles (releves)
	if #Regles() == 0 then return releves end
	local reste = {}
	for _, o in ipairs(releves) do
		local _, nom = GetLootSlotInfo(o.slot)
		local r = RegleDe(o.id, nom)
		local dest = r and DestinationDe(r)
		if r and dest and DonnerSlot(o.slot, dest) then
			Msg(o.lien .. " » " .. dest .. " (règle).")
		else
			if r then Msg(o.lien .. " : la règle vise " .. r.dest .. ", qui ne peut pas le recevoir d'ici (absent, trop loin, ou objet sous le seuil de butin).") end
			reste[#reste + 1] = o
		end
	end
	return reste
end

-- les objets d'un corps, au-dessus du seuil de butin du groupe (épique par défaut), ceux d'une liste, ceux d'une règle
local function Relever ()
	local seuil = (GetLootThreshold and GetLootThreshold()) or 4
	local releves = {}
	for slot = 1, GetNumLootItems() or 0 do
		local lien = GetLootSlotLink(slot)
		local id = ItemID(lien)
		if id then
			local _, nom, _, _, qualite = GetLootSlotInfo(slot)
			local voulu = Raid.db.instantane and Raid.db.instantane.souhaits[id]
			local source = GetLootSourceInfo and GetLootSourceInfo(slot)
			-- un seuil abaissé pour les règles ne doit pas remplir le volet de tout le vert du corps : sous l'épique,
			-- seulement ce qu'une liste ou une règle vise
			local plancher = #Regles() > 0 and math.max(seuil, 4) or seuil
			local retenu = (qualite and qualite >= plancher) or voulu or RegleDe(id, nom)
			if retenu then releves[#releves + 1] = { lien = lien, id = id, slot = slot, source = source } end
		end
	end
	return releves
end

-- Un corps rouvert : chaque objet déjà annoncé retrouve son attribution (même objet, même corps), au lieu de repartir
-- comme un nouveau butin.
local function Rattacher (releves)
	local pris = {}
	for _, o in ipairs(releves) do
		for _, a in ipairs(Raid.attributions) do
			if not pris[a] and not a.donne and o.source and a.id == o.id and a.source == o.source then
				pris[a], o.attribution = true, a
				break
			end
		end
	end
end

-- Les objets montrés : ceux d'avant qui ne sont pas terminés, puis les nouveaux (un corps rouvert n'ajoute rien).
local function Garder (nouveaux)
	local garde = {}
	for _, o in ipairs(objets) do
		local a = o.attribution
		if not a or a.etat == "delai" or a.etat == "vote" or a.etat == "trancher" or a.etat == "sk" then garde[#garde + 1] = o end
	end
	for _, o in ipairs(nouveaux) do
		local deja = false
		for _, g in ipairs(garde) do
			-- la même attribution, ou le même objet pas encore annoncé : la ligne existe, elle reprend l'emplacement
			if (o.attribution and g.attribution == o.attribution) or (not o.attribution and not g.attribution and g.lien == o.lien) then
				deja = true
				g.slot, g.source, g.tente = o.slot or g.slot, o.source or g.source, nil
			end
		end
		if not deja then garde[#garde + 1] = o end
	end
	-- un objet annoncé par la commande remplace sa ligne pas encore annoncée
	for _, o in ipairs(nouveaux) do
		if o.attribution then
			for k = #objets, 1, -1 do
				local g = objets[k]
				if g.lien == o.lien and not g.attribution then
					for i = #garde, 1, -1 do if garde[i] == g then table.remove(garde, i) end end
				end
			end
		end
	end
	objets = garde
end

-- /opus raid diag : pourquoi la fenêtre du butin s'ouvre (ou pas) sur un corps
local dernierCorps
local dernierAvis                   -- le dernier corps pour lequel on a dit « pas de soirée »
Raid.Commande("diag", "diag", "pourquoi la fenêtre du butin s'ouvre ou non sur un corps", function ()
	local lire = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
	local ok, m, p, r = false, nil, nil, nil
	if lire then ok, m, p, r = pcall(lire) end
	local actif, raison = Raid.Actif()
	local function OuiNon (v) return v and "|cff40ff40oui|r" or "|cffff5555non|r" end
	Msg("diagnostic du butin (Opus " .. Opus.version .. (Opus.build and (", " .. Opus.build) or "") .. ") :")
	if Raid.AncienActif and Raid.AncienActif() then DEFAULT_CHAT_FRAME:AddMessage("  " .. Raid.AVERTI_ANCIEN) end
	-- les fichiers ajoutés depuis la dernière sortie : absents, le jeu n'a pas été relancé depuis la mise à jour
	if not Raid.Comparer or not Opus.ReglagesButin or not Opus.ButinGroupeActif then
		DEFAULT_CHAT_FRAME:AddMessage("  |cffff5555des fichiers de l'addon ne sont pas chargés : quitte le jeu et relance-le (un /reload ne suffit pas après une mise à jour qui ajoute des fichiers).|r")
	end
	DEFAULT_CHAT_FRAME:AddMessage(string.format("  mode de butin : %s (groupe %s, raid %s)%s", tostring(m), tostring(p), tostring(r),
		lire and (ok and "" or " — lecture impossible") or " — aucune fonction pour le lire"))
	DEFAULT_CHAT_FRAME:AddMessage("  en groupe : " .. OuiNon(IsInGroup()) .. ", en raid : " .. OuiNon(IsInRaid())
		.. ", maître du butin : " .. OuiNon(Raid.EstMaitreButin()) .. ", droit de gérer : " .. OuiNon(Raid.PeutGerer()))
	DEFAULT_CHAT_FRAME:AddMessage("  soirée active : " .. OuiNon(actif) .. (raison and (" (" .. raison .. ")") or "")
		.. ", seuil de butin : " .. tostring(GetLootThreshold and GetLootThreshold()))
	DEFAULT_CHAT_FRAME:AddMessage("  instantané : " .. (Raid.db.instantane and Raid.db.instantane.id or "aucun")
		.. ", dernier corps ouvert : " .. (dernierCorps or "aucun depuis le chargement"))
	DEFAULT_CHAT_FRAME:AddMessage(string.format("  durées sur ce client : objection %s, vote %s, Suicide King %s",
		Raid.TexteDuree(Raid.Duree("objection")), Raid.TexteDuree(Raid.Duree("vote")), Raid.TexteDuree(Raid.Duree("sk"))))
	-- la dernière erreur du volet (Volet.lua), gardée d'une session à l'autre
	if OpusDB and OpusDB.erreurVolet then
		DEFAULT_CHAT_FRAME:AddMessage("  dernière erreur du volet : |cffff8080" .. OpusDB.erreurVolet:gsub("\n", " · ") .. "|r")
	end
end)

Raid.Ecoute("LOOT_OPENED", function ()
	dernierCorps = string.format("%s, %d objet(s), %d retenu(s)", date("%H:%M:%S"), GetNumLootItems() or 0, #Relever())
	-- seulement dans une soirée de guilde ouverte (Raid.lua) : jamais dans le raid d'une autre guilde ; en groupe,
	-- pour l'essai en donjon (/opus raid essai)
	if not IsInGroup() or not Raid.EstMaitreButin() or not Raid.PeutGerer() then return end
	local actif, raison = Raid.Actif()
	if not actif then
		-- maître du butin d'un groupe sans soirée de guilde : on le dit (une fois par corps), au lieu de ne rien montrer
		if #Relever() > 0 and dernierAvis ~= dernierCorps then
			dernierAvis = dernierCorps
			Msg(raison .. " : la fenêtre du butin d'Opus ne s'ouvre pas.")
		end
		return
	end
	corpsOuvert = true
	wipe(attente)
	for _, o in ipairs(objets) do o.slot = nil end
	local releves = Relever()
	if #releves == 0 then return end
	Rattacher(releves)
	-- les objets d'une règle partent tout de suite (pas ceux déjà annoncés)
	local libres, annonces = {}, {}
	for _, o in ipairs(releves) do if o.attribution then annonces[#annonces + 1] = o else libres[#libres + 1] = o end end
	releves = AppliquerRegles(libres)
	for _, o in ipairs(annonces) do releves[#releves + 1] = o end
	if #releves == 0 then return end
	Garder(releves)
	Raid.MontrerButin()
	local ids = {}
	for _, o in ipairs(releves) do ids[#ids + 1] = o.id end
	Raid.PrioriserObjets(ids)
end)

-- un objet quitte le corps : donné (remise notée), ou ramassé à la main par le maître du butin (il suit par échange)
Raid.Ecoute("LOOT_SLOT_CLEARED", function (slot)
	local d = attente[slot]
	attente[slot] = nil
	for _, o in ipairs(objets) do
		if o.slot == slot then
			local a = d and d.a or o.attribution
			if a and (a.etat == "attribue" or a.etat == "de" or a.etat == "banque") then
				a.donne = true
				if d and not a.remis and Raid.Remettre then Raid.Remettre(a, d.dest, "maitre") end
			end
			o.slot = nil
			-- pas encore annoncé : donné par le menu du jeu, ou ramassé ; il n'a plus rien à faire dans la liste
			if not o.attribution then o.parti = true end
		end
	end
	for k = #objets, 1, -1 do if objets[k].parti then table.remove(objets, k) end end
	if f and f:IsShown() then
		if #objets == 0 then f:Hide() else Raid.MontrerButin() end
	end
	Raid.RafraichirButin()
end)

-- Alt+clic sur un objet des sacs (maître du butin, soirée ouverte) : il rejoint les objets du butin, à annoncer (un
-- objet ramassé, ou gardé après le corps) ; l'annonce reste un geste à part.
function Raid.AjouterAuButin (lien)
	local id = ItemID(lien)
	if not id then return end
	for _, o in ipairs(objets) do if o.lien == lien and not o.attribution then Raid.MontrerButin() return end end
	Garder({ { lien = lien, id = id } })
	Raid.MontrerButin()
	Raid.PrioriserObjets({ id })
end
if hooksecurefunc and HandleModifiedItemClick then
	hooksecurefunc("HandleModifiedItemClick", function (lien)
		if type(lien) ~= "string" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
		if not lien:find("|Hitem:", 1, true) or not IsInGroup() or not Raid.EstMaitreButin() or not Raid.PeutGerer() then return end
		if not Raid.Actif() then return end
		Raid.AjouterAuButin(lien)
	end)
end

-- /opus raid regle : les règles fixes
Raid.Commande("regle", "regle [objet ou nom] [joueur|de|banque]", "les règles fixes : « /opus raid regle scarabée Bob », un lien ou un itemID marche aussi ; « /opus raid regle retirer 2 »", function (texte)
	texte = strtrim(texte or "")
	local liste = Regles()
	if texte == "" then
		if #liste == 0 then Msg("aucune règle. Exemple : /opus raid regle scarabée Bob (ou de, banque).") return end
		Msg("règles du butin :")
		for k, r in ipairs(liste) do
			DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s » %s", k, r.id and (Raid.LienDe(r.id)) or ("« " .. r.motif .. " »"),
				r.dest == "de" and "désenchanteur" or r.dest == "banque" and "banque (toi)" or r.dest))
		end
		return
	end
	local k = tonumber(texte:match("^retirer%s+(%d+)$"))
	if k then
		if liste[k] then table.remove(liste, k) Msg("règle " .. k .. " retirée.") else Msg("pas de règle " .. k .. ".") end
		return
	end
	local lien = texte:match("|c%x+|Hitem:.-|h.-|h|r")
	local quoi, dest
	if lien then quoi, dest = lien, strtrim((texte:gsub("|c%x+|Hitem:.-|h.-|h|r", "", 1)))
	else quoi, dest = texte:match("^(.-)%s+(%S+)$") end
	if not quoi or not dest or dest == "" or quoi == "" then Msg("usage : /opus raid regle <objet ou morceau de nom> <joueur|de|banque>") return end
	local d = dest:lower()
	dest = (d == "de" or d == "banque" or d == "moi") and d or (dest:sub(1, 1):upper() .. dest:sub(2))
	local id = lien and ItemID(lien) or tonumber(quoi)
	liste[#liste + 1] = id and { id = id, dest = dest } or { motif = quoi:lower(), dest = dest }
	Msg(string.format("règle ajoutée : %s » %s. Pense au seuil de butin du groupe s'il s'agit d'objets sous l'épique.",
		id and Raid.LienDe(id) or ("« " .. quoi:lower() .. " »"), dest))
end)

-- pour le volet (Volet.lua) : l'état d'un objet, son action principale, et s'il peut partir au désenchantement
Raid.EtatObjet = EtatObjet
function Raid.ActionObjet (o) Principal({ objet = o }) end
function Raid.DesenchanterLibre (o, r)
	if o.attribution then return false end
	return r == nil or #r.candidats == 0
end
function Raid.DesenchanterLigne (o)
	if not o or o.attribution then return end
	local a = Raid.DesenchanterObjet(o)
	if a then o.attribution = a end
	Raid.RafraichirButin()
end

-- les objets et les lignes de la fenêtre (simulations hors jeu)
function Raid.ObjetsDuCorps () return objets end
function Raid.LignesDuButin () return lignes, f end

Raid.Ecoute("LOOT_CLOSED", function ()
	corpsOuvert = false
	wipe(attente)
	for _, o in ipairs(objets) do o.slot = nil end
	Raid.RafraichirButin()
end)

------------------------------------------------------------------------
-- commandes
------------------------------------------------------------------------

-- Le lien d'un objet par son itemID : le jeu ne le connaît pas toujours tout de suite ; on le lui demande, et la
-- fenêtre se met à jour quand il arrive (GET_ITEM_INFO_RECEIVED).
local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function Raid.LienDe (id)
	local _, lien = Info(id)
	if lien then return lien end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return "objet " .. id
end

Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function (id)
	local change = false
	for _, o in ipairs(objets) do
		if o.id == id and not o.lien:find("|H", 1, true) then
			local _, lien = Info(id)
			if lien then o.lien, change = lien, true end
		end
	end
	if change and f and f:IsShown() then Raid.MontrerButin() end
	if Raid.RafraichirVote then Raid.RafraichirVote() end
	if Raid.RafraichirFiche then Raid.RafraichirFiche() end
end)

local function LireObjet (texte)
	local lien = (texte or ""):match("|c%x+|Hitem:.-|h.-|h|r")
	local id = ItemID(lien) or tonumber(texte)
	if not id then return nil end
	return lien or ("objet " .. id), id
end

Raid.Commande("proposer", "proposer <lien ou itemID>", "le calcul détaillé de la proposition (pour toi seul)", function (texte)
	local lien, id = LireObjet(texte)
	if not id then Msg("usage : /opus raid proposer <lien de l'objet ou itemID>") return end
	local r = Raid.Proposer(id, Raid.Presents())
	if not r then Msg("aucun instantané importé.") return end
	Detail(lien, r)
end)

Raid.Commande("annoncer", "annoncer <lien>", "annoncer au raid la proposition pour un objet, et lancer le délai d'objection", function (texte)
	if not Raid.PeutGerer() then Msg("annonce " .. Raid.QuiPeut() .. ".") return end
	local lien, id = LireObjet(texte)
	if not id then Msg("usage : /opus raid annoncer <lien de l'objet>") return end
	local o = { lien = lien, id = id }
	o.attribution = Raid.Lancer(o)
	if not o.attribution then return end
	Garder({ o })
	Raid.MontrerButin()
end)

-- /opus raid butin : la fenêtre du dernier corps ; /opus raid butin <liens ou itemID…> : la même fenêtre avec ces objets,
-- pour essayer sans raid (sans lien, le nom de l'objet vient du cache du jeu, et peut manquer la première fois)
Raid.Commande("butin", "butin [liens ou itemID…]", "la fenêtre du butin : le dernier corps ouvert, ou les objets donnés (essai sans raid)", function (texte)
	local essai = {}
	for lien in (texte or ""):gmatch("|c%x+|Hitem:.-|h.-|h|r") do essai[#essai + 1] = { lien = lien, id = ItemID(lien) } end
	if #essai == 0 then
		for chiffres in (texte or ""):gmatch("%d+") do
			local id = tonumber(chiffres)
			essai[#essai + 1] = { lien = Raid.LienDe(id), id = id }
		end
	end
	if #essai > 0 then objets = essai end
	Raid.MontrerButin()
end)
