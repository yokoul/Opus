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

local function Construire ()
	f = Raid.Cadre("OpusRaidButin")
	f:SetSize(520, 120) f:SetPoint("TOPLEFT", 260, -140) f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Opus : butin")
	-- en bas : le désenchanteur de la soirée, parmi les présents (sinon la liste de l'instantané)
	f.deTexte = f.Inset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.deTexte:SetPoint("BOTTOMLEFT", 12, 14) f.deTexte:SetText("Désenchanteur :")
	f.deChoix = {}
	f.deMenu = Opus.Menu(f.Inset, 200, f.deChoix,
		function () return Raid.db.reglages.desenchanteur or "" end,
		function (v) Raid.db.reglages.desenchanteur = v ~= "" and v or nil Raid.RafraichirButin() end)
	f.deMenu:SetPoint("LEFT", f.deTexte, "RIGHT", 8, 0)
	tinsert(UISpecialFrames, "OpusRaidButin")
	f:Hide()
end

local function Ligne (n)
	if lignes[n] then return lignes[n] end
	local z = f.Inset
	local l = CreateFrame("Frame", nil, z)
	l:SetSize(490, 40) l:SetPoint("TOPLEFT", 10, -10 - (n - 1) * 44)
	l.icone = Raid.Icone(l, 36)
	l.icone:SetPoint("LEFT", 0, 0)
	l.objet = CreateFrame("Button", nil, l)
	l.objet:SetSize(226, 18) l.objet:SetPoint("TOPLEFT", 44, 0)
	l.objet.texte = l.objet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.objet.texte:SetAllPoints() l.objet.texte:SetJustifyH("LEFT")
	l.objet:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lien, self.id) end)
	l.objet:SetScript("OnLeave", GameTooltip_Hide)
	l.proposition = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.proposition:SetPoint("TOPLEFT", 44, -20) l.proposition:SetWidth(222) l.proposition:SetJustifyH("LEFT") l.proposition:SetWordWrap(false)
	l.annoncer = CreateFrame("Button", nil, l, "SharedButtonSmallTemplate")
	l.annoncer:SetSize(100, 24) l.annoncer:SetPoint("RIGHT", 0, 0) l.annoncer:SetText("Annoncer")
	l.annoncer:SetScript("OnClick", function (self)
		if ADonner(self.objet) then Raid.Donner(self.objet) return end
		if self.attribution and self.attribution.etat == "trancher" then Raid.OuvrirDecision(self.attribution) return end
		if self.attribution then return end
		Raid.AnnoncerObjet(self.objet)
	end)
	-- la fiche de décision de l'objet (RaidFiche.lua) : les candidats, leurs scores, ce qu'ils ont déjà reçu
	l.fiche = Opus.Bouton(l, "Fiche", 60, function (self) Raid.OuvrirFiche(self.objet) end)
	l.fiche:SetPoint("RIGHT", l.annoncer, "LEFT", -6, 0)
	Opus.Bulle(l.fiche, "Fiche de décision", "Les candidats présents, leur score décomposé et ce qu'ils ont déjà reçu ce soir et sur le palier.")
	-- « DE » : hors liste, droit au désenchanteur, sans annonce
	l.de = Opus.Bouton(l, "DE", 44, function (self)
		local o = self.objet
		if not o or o.attribution then return end
		local a = Raid.DesenchanterObjet(o)
		if a then o.attribution = a end
		Raid.RafraichirButin()
	end)
	l.de:SetPoint("RIGHT", l.fiche, "LEFT", -6, 0)
	l.de:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Désenchanter", 1, 1, 1)
		local qui = Raid.Desenchanteur()
		GameTooltip:AddLine(qui and ("Donné à " .. qui .. ", sans annonce ni Suicide King. Noté au rapport.")
			or "Aucun désenchanteur présent : l'objet ira à la banque (à toi). Choisis-en un en bas de la fenêtre.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	l.de:SetScript("OnLeave", GameTooltip_Hide)
	l.annoncer:SetScript("OnEnter", function (self)
		if ADonner(self.objet) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Donner à " .. Destinataire(self.attribution), 1, 1, 1)
			GameTooltip:AddLine("Par le menu du maître du butin, sans échange. La remise est notée au rapport.", nil, nil, nil, true)
			GameTooltip:Show()
			return
		end
		if self.attribution then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Annoncer au raid", 1, 1, 1)
		GameTooltip:AddLine(Raid.TexteAnnonce(self.lien, Raid.Proposer(self.id, Raid.Presents())) or "", nil, nil, nil, true)
		GameTooltip:AddLine("Puis " .. Raid.TexteDuree(Raid.Duree("objection")) .. " pour objecter (« !objection »), et un vote s'il y a objection.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	l.annoncer:SetScript("OnLeave", GameTooltip_Hide)
	lignes[n] = l
	return l
end

-- Met les lignes à jour : avant l'annonce, la proposition ; après, l'état de l'attribution (délai, vote…).
function Raid.RafraichirButin ()
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
	-- attribué et sur le corps ouvert : on le donne, une fois (un refus laisse le bouton « Donner »)
	for _, o in ipairs(objets) do
		if ADonner(o) and not o.tente then o.tente = true Raid.Donner(o) end
	end
	for n, o in ipairs(objets) do
		local l = Ligne(n)
		local a = o.attribution
		o.lien = Raid.LienAJour(o.lien, o.id)
		if not o.lien:find("|H", 1, true) then attendre = true end
		l.objet.id = o.id
		l.objet.lien, l.annoncer.lien, l.annoncer.id, l.annoncer.objet, l.annoncer.attribution = o.lien, o.lien, o.id, o, a
		l.fiche.objet, l.de.objet = o, o
		l.de:SetShown(not a)
		Raid.PoserIcone(l.icone, o.id, o.lien)
		l.objet.texte:SetText(o.lien)
		if a and ADonner(o) then
			l.proposition:SetText(Raid.EtatAttribution(a) .. " · |cffffd100encore sur le corps|r")
			l.annoncer:SetText("Donner")
			l.annoncer:SetEnabled(true)
		elseif a then
			l.proposition:SetText(Raid.EtatAttribution(a))
			l.annoncer:SetText(a.etat == "trancher" and "Trancher…" or a.etat == "delai" and "Objections" or a.etat == "vote" and "Vote" or a.etat == "sk" and "Suicide King" or "Terminé")
			l.annoncer:SetEnabled(a.etat == "trancher")
		else
			local r = Raid.Proposer(o.id, presents)
			local c1 = r and r.candidats[1]
			l.proposition:SetText(not r and "pas d'instantané : /opus raid import"
				or c1 and (c1.nom .. " — " .. Raid.Score(c1.score) .. (r.egalite and " (ex aequo)" or "") .. (#r.candidats > 1 and ("  · " .. (#r.candidats - 1) .. " autre" .. (#r.candidats > 2 and "s" or "")) or ""))
				or "aucun candidat présent » Suicide King")
			l.annoncer:SetText("Annoncer")
			l.annoncer:SetEnabled(r ~= nil)
			-- « DE » : seulement si personne de présent ne l'a en liste
			l.de:SetEnabled(r == nil or #r.candidats == 0)
		end
		l:Show()
	end
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
	f:SetHeight(76 + #objets * 44)
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
			Msg(o.lien .. " donné à " .. dest .. ".")
			return
		end
	end
	Msg(dest .. " ne peut pas recevoir " .. o.lien .. " depuis ce corps (trop loin, hors ligne ou pas éligible). « Donner » pour réessayer, ou ramasse-le et remets-le par échange.")
end

-- les objets d'un corps, au-dessus du seuil de butin du groupe (épique par défaut)
local function Relever ()
	local seuil = (GetLootThreshold and GetLootThreshold()) or 4
	local releves = {}
	for slot = 1, GetNumLootItems() or 0 do
		local lien = GetLootSlotLink(slot)
		local id = ItemID(lien)
		if id then
			local _, _, _, _, qualite = GetLootSlotInfo(slot)
			local voulu = Raid.db.instantane and Raid.db.instantane.souhaits[id]
			local source = GetLootSourceInfo and GetLootSourceInfo(slot)
			if (qualite and qualite >= seuil) or voulu then releves[#releves + 1] = { lien = lien, id = id, slot = slot, source = source } end
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
end)

Raid.Ecoute("LOOT_OPENED", function ()
	dernierCorps = string.format("%s, %d objet(s), %d retenu(s)", date("%H:%M:%S"), GetNumLootItems() or 0, #Relever())
	-- seulement dans une soirée de guilde ouverte (Raid.lua) : jamais dans le raid d'une autre guilde ; en groupe,
	-- pour l'essai en donjon (/opus raid essai)
	if not IsInGroup() or not Raid.EstMaitreButin() or not Raid.PeutGerer() or not Raid.Actif() then return end
	corpsOuvert = true
	wipe(attente)
	for _, o in ipairs(objets) do o.slot = nil end
	local releves = Relever()
	if #releves == 0 then return end
	Rattacher(releves)
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

-- les lignes de la fenêtre (simulations hors jeu)
function Raid.ObjetsDuCorps () return objets end

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
