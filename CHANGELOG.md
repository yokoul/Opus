# Opus — notes de mise à jour

Outils de guilde pour WoW Forever, faits pour la guilde **Opus** (royaume PvE, Europe).
Contact : **Illustre Inconnu** en jeu, ou le Discord de la guilde : https://discord.gg/XtSksuFU6v

## 0.33.0

### Raids : le volet du butin
- Le volet latéral remplace les fenêtres des annonces et du butin. Une languette au bord gauche de l'écran (à glisser vers le haut ou le bas) dit l'état d'un coup d'œil : gemme pâle quand rien ne se passe, or quand des objets circulent, rubis quand une décision t'attend. Une banderole en sort pour décider en un clic (Je le veux, Passer, les noms d'un vote, Le laisser) et suit le tour jusqu'au résultat ; le volet garde le butin de la soirée, ligne par ligne, avec l'explication de chaque décision. Épinglable (il reste ouvert, même en combat). /opus volet ancien rend les fenêtres d'avant.
- Le maître du butin retrouve dans le volet les objets du corps, qui s'ouvre de lui-même avec le corps, et les attributions en cours ou à remettre : Annoncer, Donner, Trancher, Clore le délai ou le tour, Donner à…, Désenchanter ou Pour la banque, Détails (la fiche de l'objet s'ouvre collée au volet).
- L'infobulle de l'objet au survol d'une ligne ou de la banderole (Maj+clic : le lien dans la discussion). Les infobulles s'ouvrent au-dessus de l'élément survolé.

### Raids : l'attribution
- Le vote suit WishVote. Une objection, avec son motif, ouvre un vote entre les candidats présents : chacun vote pour celui qui le mérite selon lui (dans le volet, ou « !vote n k » dans le canal raid). Votent tous les présents sauf ceux qui ont l'objet en liste. Quorum atteint, le candidat en tête reçoit l'objet ; une égalité passe aux officiers ; sans quorum, la proposition tient.
- Les officiers peuvent trancher à tout moment, toujours avec un motif. La fiche de l'objet montre les candidats présents (classe, rang et rôle, score décomposé, ce qu'ils ont déjà reçu, comparaison d'équipement), les voix pendant un vote, et permet d'annoncer ou de trancher en un clic.
- « Je le laisse » : un candidat peut renoncer à un objet pendant le délai ou le vote, au profit d'un autre candidat présent ou du suivant du calcul (« !laisse n [nom] »).
- Suicide King : chacun voit qui s'est déclaré et qui est en tête ; « Passer » (ou « !passe n ») ; le tour finit dès que tous les présents ont répondu. Le maître du butin peut se déclarer lui aussi. Entre déclarés hors liste, le premier déclaré passe devant.
- Le maître du butin peut abréger un tour : « Clore le délai » donne l'objet au proposé quand personne n'a objecté, « Clore le tour » finit un Suicide King avec les déclarés du moment.
- Sans instantané (import oublié, bridge en panne), le butin ne bloque plus : « Annoncer » lance un Suicide King direct, « Donner à… » donne l'objet à un présent choisi dans un menu (aussi pour un objet que personne de présent n'a en liste), le désenchantement reste possible ; tout est noté au rapport.
- Un objet que personne de présent n'a en liste peut partir droit au désenchanteur, choisi parmi les présents. Règles fixes du maître du butin : « /opus raid regle scarabée Bob » (ou « de », « banque ») ; ces objets partent tout seuls à l'ouverture du corps.
- L'objet attribué est donné tout seul depuis le corps, par le menu du maître du butin ; si le jeu refuse, « Donner » permet de réessayer, l'échange reste possible. Alt+clic sur un objet des sacs l'ajoute au volet, à annoncer.
- Les durées des tours se règlent dans Réglages, vue « Butin » (objection de 1 à 5 min, vote de 1 à 3 min, Suicide King de 30 s à 2 min), avec la part de la guilde pour ouvrir une soirée, l'échange automatique et les annonces au raid (courtes par défaut, détaillées au choix).

### Raids : la soirée
- Un rechargement ne ferme plus la soirée de guilde. Le maître du butin retrouve ses attributions telles quelles (les tours reprennent avec le temps qui leur restait), et un joueur qui recharge ou arrive en cours de soirée retrouve les annonces.
- La comparaison d'équipement : chaque client inspecte les membres du raid (hors combat, à portée). Avec Pawn, le verdict est le gain de l'objet dans la meilleure spé de chacun (« +53 % »), sinon l'écart de niveau d'objet ; au survol, ce que l'objet change caractéristique par caractéristique, face à la pièce qu'il remplacerait.
- Infobulle des objets : qui l'a en liste (et à quel rang), et à qui il est allé ce soir.
- L'onglet Raids : « Ce soir » résume la soirée, l'instantané, les objets du soir et le rapport ; « Ma liste » donne un bloc par perso (statut, rôle, soirées, prios perdues, dernier loot, place au Suicide King, objets reçus).
- /opus raid essai pour essayer une soirée en donjon à quelques-uns (rien ne part au site) ; /opus raid oublier efface l'instantané pour essayer sans.

### Donjons
- « Comparer le butin en donjon » (Réglages, vue « Butin », éteint par défaut : sans lui, Opus ne montre rien en donjon). Sous chaque cadre de jet du jeu, une ligne discrète compte les choix (dé, pièce, désenchantement, passer) puis nomme le gagnant et son jet ; un clic montre la liste : le jet de chacun et ce que l'objet lui vaut, ou « ne peut pas ». La bande reste jusqu'au résultat, même après ton choix. Les jets du donjon se suivent aussi dans le volet, avec une courte banderole de résultat quand tu as jeté les dés. Tout est lu en jeu : ça marche avec des joueurs sans Opus. /opus volet essai donjon pour essayer seul.

### Corrections
- Roster : le filtre « Raiders » compte aussi le Magister et les Architectes.
- Raids : l'infobulle d'un candidat ne lève plus d'erreur quand Pawn calcule son gain.
- Un souci d'affichage du volet ne se répète plus dans la discussion : il est dit une fois, et /opus raid diag en donne le détail à signaler sur le Discord.

## 0.32.0
- Raids : avec le bridge, le rapport de la soirée part tout seul au site à la déconnexion (ou au /reload), sans copier-coller. Il est déposé à la fermeture de la soirée de guilde (ou en quittant le raid), et complété s'il change encore ; les essais hors groupe ne partent pas. L'export à coller reste possible sans bridge.

## 0.31.1
- Raids : « Ma liste » et « Historique » restaient vides en jeu (le texte n'était pas affiché, et la barre de défilement débordait de la fenêtre).

## 0.31.0
- Raids : l'onglet a trois vues. « Ce soir » (la soirée de guilde, l'instantané, les annonces du soir, le rapport), « Ma liste » (tes listes de souhaits avec leurs rangs et les objets déjà reçus, tes soirées, tes prios perdues, ton dernier loot et ta place au Suicide King) et « Historique » (les soirées validées des paliers en cours : qui était là, chaque objet et comment il est parti ; l'infobulle de l'objet au survol). Ma liste et l'historique viennent du site par le client opus-bridge, mis à jour à chaque connexion.
- Raids : avec le bridge, le maître du butin ou un officier importe l'instantané d'un clic (« Du bridge »), sans copier-coller.
- Envies : à la connexion, les envies en cours arrivent en 10 à 20 secondes au lieu d'une minute (le rattrapage part dès que la liste de guilde est chargée, en tête de file).

## 0.30.0
- Raids : l'addon Opus Raid rejoint Opus. Le butin des raids de guilde suit les règles publiées sur opus-guild.eu (page Raids) : listes de souhaits validées sur le site, proposition calculée quand un objet tombe, 3 minutes pour faire objection, vote des non-candidats, décision motivée des officiers, Suicide King pour ce que personne n'a en liste, puis désenchantement ou banque, remise par échange. Si Opus Raid est encore installé, désactive-le : Opus reprend ses données à la première connexion.
- Raids : nouvel onglet « Raids ». La soirée de guilde (l'ouvrir, la fermer, son état), l'instantané du site (importer, détail), les annonces du soir, ta liste de souhaits et ta place au Suicide King, et le rapport à rendre au site. Les fenêtres du butin, des attributions et de la décision des officiers restent à part, elles s'ouvrent en pleine soirée.
- Raids : l'addon ne s'engage que dans une soirée de guilde. Le maître du butin ou un officier l'ouvre de lui-même, et seulement si au moins 80 % du raid est de la guilde (réglable par les officiers : /opus raid seuil). Si le raid passe sous ce seuil en cours de soirée, tout est suspendu jusqu'à ce qu'il redevienne un raid de guilde ; quitter le raid ferme la soirée. Chez les joueurs, seule une annonce d'un membre de la guilde ouvre la fenêtre des attributions.
- Raids : les commandes passent sous /opus raid (/opus raid aide pour la liste) ; /opusraid reste un raccourci.
- Réglages : « À propos » n'est plus un onglet mais une vue de l'onglet Réglages (et /opus apropos), pour laisser la place à « Raids ».

## 0.29.0
- Groupe : les expéditions prévues sur Discord (forum Raid-Helper de la guilde) arrivent en jeu avec le client **opus-bridge** (à installer depuis opus-guild.eu/pont, une ligne à coller). Une envie qui a son expédition porte un badge Discord dans l'angle de sa carte (date, meneur et inscrits au survol) ; les expéditions sans envie en jeu sont listées sous les envies.
- Envies : avec le client opus-bridge, chaque donjon d'une envie devient une expédition sur Discord (à l'heure déduite du créneau : maintenant, ce soir 20 h 30, ce week-end samedi 14 h), et un « Moi aussi » une inscription à l'expédition déjà prévue. Retirer ou clore son envie rend sa place sur Discord, et annule l'expédition si elle reste vide.
- Envies : une envie retirée ou close laisse une trace de 7 jours dans les sauvegardes (OpusDB.retraits), que le client lit ; une envie arrivée à sa fin n'en laisse pas.

## 0.28.3
- Banque, Contenu : la photo des onglets n'arrivait plus chez les autres membres depuis la 0.27.0 (son message portait la même lettre que celui des liaisons Discord, qui le recevait à sa place) : seul celui qui était passé à la banque voyait la grille. Les photos partent sous une nouvelle lettre, et celles des versions 0.27.0 à 0.28.2 sont lues aussi.
- Banque, Contenu : ouvrir la vue sans photo (ou avec une photo de plus d'une heure) la demande aussitôt aux membres en ligne, au lieu d'attendre la minute qui suit la connexion.
- Noms : deux membres au même prénom (Basara Auberdine et Basara Nore, Kibrom Felheart et Kibrom Stormheart…) ne sont plus confondus. Un nom écrit « Prénom-Nom » est rangé en « Prénom Nom », et un prénom seul n'est attribué que s'il ne désigne qu'un membre (ou qu'un membre en ligne).
- Réglages, Diagnostics : bouton « Noms » (/opus diagnoms), comment le jeu écrit les noms ; le relevé est aussi gardé dans les sauvegardes.
- Infobulles : survoler un membre dans Guilde > Par voie ou En ligne pouvait lever une erreur Lua (« bad argument #1 to 'SetText' »). Une infobulle que le jeu refuse ne s'affiche simplement pas, et le refus est noté dans les sauvegardes (OpusDB.diagBulle) pour en trouver la cause.

## 0.28.2
- Réglages, « Teinte des boutons » : en plus du bouton du jeu (par défaut), des boutons aux teintes des planches de la guilde (pétrole de la bannière, écarlate noble, vert de gris, aubergine, ardoise froide, bronze fumé), en relief avec un filet doré ; au prochain /reload.
- Réglages : le texte des diagnostics ne passe plus sous les boutons.

## 0.28.1
- Notifications : un clic droit passe la notification (sans ouvrir la fiche ni l'onglet), maj + clic droit passe aussi celles en attente ; leur nombre s'affiche en bas.
- Envies : « Clore pour mon groupe », dans le menu « Mon envie » de la carte (donjon fait ou abandonné), clôt ton envie sur ce donjon et celles des membres de ton groupe qui en avaient une ; la carte disparaît quand plus personne n'y a d'envie. Sans envie sur ce donjon mais en groupe avec des intéressés, « Moi aussi » le propose aussi.
- Envies : « Former le groupe » disparaît (il recopiait la carte dans « Ton groupe », en double). La carte a son propre bouton « Inviter les dispo » : la composition d'abord, puis les autres disponibles maintenant et en ligne, quatre au plus. La notification « Groupe complet possible » ouvre la carte.
- Onglet Groupe : le panneau « Ton groupe » disparaît, il venait d'avant les envies. Un groupe se monte par une envie (« J'ai besoin d'un donjon… ») et sa carte, qui invite. Le choix du donjon passe en tête de « En ligne à ta portée » et règle la tranche de niveaux des membres proposés ; « Écrire » et « Proposer » restent, et un membre déjà dans ton groupe est signalé.
- Une envie « jusqu'à ce soir » publiée tard dure au moins deux heures (près de minuit, elle expirait presque aussitôt).

## 0.28.0
- Envies : « PL accepté ». Une case du formulaire (et du menu « Mon envie ») dit que le groupe veut bien d'un 60, ou d'un grand, pour le booster dans le donjon, quitte à perdre l'XP des monstres (gris pour lui). La carte l'affiche, les grands qui s'y joignent apparaissent en doré « booste » au lieu du rouge, leur repère sur la barre de niveaux aussi, et la notification comme l'annonce en /g le précisent.

## 0.27.1
- Guilde et Roster : les vues et les filtres passent aussi en onglets dans le bandeau (Par voie, En ligne, Calendrier, Journal, Grades ; Tous, Niveau 60, Raiders, En ligne).
- Les onglets du haut sont posés sur un filet doré, pour les distinguer des onglets de navigation du bas.

## 0.27.0
- Banque : les vues (Participation, Contenu, Journal, Prêts, Sorties) passent en onglets dans le bandeau, à la place du menu ; la ligne d'état (relevé, photo, nombre) passe sous le contenu.
- Contenu : vue en grille, comme la banque du jeu (98 cases, un onglet à la fois), ou en liste. La recherche et « Pour moi » éteignent ce qui ne correspond pas. La photo garde maintenant la case de chaque objet ; une photo de la 0.26.0 se refait au prochain passage à la banque.

## 0.26.0
- Banque, vue « Contenu » : ce que contient chaque onglet, sans aller à la banque. À l'ouverture de la banque, l'addon photographie chaque onglet visible et partage la photo à la guilde. Recherche par nom, filtre par onglet ; le survol montre l'infobulle de l'objet (avec celle de Pawn s'il est installé), maj-clic le met dans la discussion. Chacun ne voit que les onglets que son grade peut voir d'après la grille.
- « Pour moi » : ce que ta classe peut porter à ton niveau (ou dans 5 niveaux) et qui vaut mieux que ce que tu portes, d'après Pawn s'il est installé, sinon d'après le niveau d'objet ; les améliorations d'abord.
- Banque, vue « Journal » : toutes les entrées et sorties, objets, or ou tout, filtrables par onglet et par nom de joueur ou d'objet.

## 0.25.4
- Banque : la vue « Remises » devient « Sorties » (sorties d'objets), « remise » prêtant à confusion avec une réduction.

## 0.25.3
- Banque : un onglet payé avec l'or de la guilde était compté deux fois (le jeu inscrit le retrait pour l'onglet, puis l'achat). Seul l'achat compte ; les relevés de la 0.25.1 sont oubliés et relus au prochain passage à la banque.
- `/opus diagbanque` (banque ouverte) affiche le solde et le journal de l'or tel que le jeu le donne.

## 0.25.2
- Notifications : elles restent 10 secondes au lieu de 4, réglable dans l'onglet Réglages (5, 10 ou 20 secondes, ou jusqu'à un clic) ; le survol les retient toujours.
- Montées de niveau : chaque niveau annoncé s'affiche aussi en notification en haut de l'écran ; un clic ouvre la fiche du membre. Les annonces restent chez toi, jamais en /g.

## 0.25.1
- Banque : le solde réel de la banque s'affiche sous le tableau de participation, lu à chaque passage à la banque et partagé à toute la guilde (le total du tableau n'additionne que les opérations des joueurs).
- Banque : l'achat d'un onglet est relevé dans le journal (« achat d'onglet ») et affiché à côté du solde ; il ne compte plus comme un retrait du joueur qui l'a acheté.

## 0.25.0
- Banque : l'onglet a trois vues, « Participation », « Prêts » et « Remises » (menu en haut à gauche).
- Prêts : le chef et les officiers notent un prêt dans un sens ou dans l'autre, « la guilde lui doit » (un joueur a avancé de l'or) ou « il doit à la guilde ». Le dépôt qui fait le prêt est retrouvé à la banque et y est relié : il ne compte pas comme cotisation. Chaque remboursement s'ajoute au prêt, avec le reste dû. L'addon propose comme remboursements les dépôts d'un débiteur et les retraits d'un créancier (clic sur le prêt pour les confirmer), et demande à un officier qui envoie de l'or à un créancier, par courrier ou par échange, s'il faut le compter.
- Remises : un objet retiré de la banque puis envoyé par courrier ou par échange est noté tout seul, avec qui l'a donné, à qui et comment, un autre de ses personnages compris. Tes retraits pas encore remis restent affichés deux semaines, avec « Remis à… » (en main propre) et « Gardé ».
- Prêts et remises sont visibles de toute la guilde, partagés entre les addons, avec rattrapage à la connexion.
- Banque : les journaux sont redemandés après chaque retrait, pour que l'objet soit connu avant d'être envoyé.

## 0.24.9
- Envies : rôle, créneau et retrait se règlent donjon par donjon. Une envie qui couvre plusieurs donjons est découpée quand tu la modifies depuis une carte : seul ce donjon change, les autres gardent l'envie d'origine.

## 0.24.8
- Envies : sur un donjon où tu as déjà une envie, le menu de la carte devient « Mon envie » : changer ton rôle ou ton créneau met l'envie à jour tout de suite (et la partage), « Retirer mon envie » y est aussi. Le menu n'affiche plus le rôle choisi en guise de titre.

## 0.24.7
- Groupe : un seul bouton pour prévenir la guilde. « J'ai besoin d'un donjon… » reprend le donjon choisi dans « Ton groupe » ; « Proposer à la guilde » disparaît.

## 0.24.6
- Envies : choisis avec quel rôle tu viens. Le formulaire coche tous les rôles que tu sais jouer (décoche pour n'en garder qu'un) ; « Moi aussi » propose le rôle en haut du menu avant le créneau.

## 0.24.5
- Groupe : le donjon choisi dans « Ton groupe » est expliqué (il règle qui t'est proposé plus bas).
- Envies : une nouvelle envie remplace tes envies précédentes sur les mêmes donjons au lieu de s'y ajouter, et une carte ne montre qu'une ligne par joueur (disponible maintenant d'abord).

## 0.24.4
- Envies : les places d'une carte montrent aussi la composition prévue. Pleine : quelqu'un est disponible maintenant ; à demi teintée : un intéressé s'y est déclaré pour un autre créneau (ton envie compte, toi compris) ; grisée : personne. Au survol, qui tient la place.

## 0.24.3
- Donjons : noms et tranches recommandées lus dans la recherche de groupe du jeu (ses activités, par leur numéro), avec un relevé du 19/11/2026 si le jeu ne répond pas. Ce sont les tranches du jeu (et de Dungeon Journal), pas celles du guide Wowhead, qui s'en écartent par endroits. Le jeu n'impose aucun niveau pour entrer. `/opus diagdonjons` enregistre ce que le jeu donne dans les données sauvegardées (visible après /reload).

## 0.24.2
- Donjons : la liste des 35 donjons de Forever (dont les nouveaux : salle des Thanes, ruines de Lordaeron, Excavations des Paluns, Dalaran, cité Submergée, bastion Krol'dok, prison d'Alcaz, repaire des Noiregueules, terrasse du Façonneur); plus de doublons venus du jeu d'origine ni de raids.
- Monstres gris : la barre de niveaux montre en rouge la zone où les monstres du donjon deviennent gris (13 niveaux au-dessus de son maximum) ; les autres joueurs (ton groupe, ou les intéressés d'une envie) y ont leur repère, rouge s'ils feraient perdre l'XP à tout le groupe. Leur niveau passe aussi en rouge, avec l'explication dans la bulle.

## 0.24.1
- Groupe : « Chercher en /g » et « Annoncer mon envie en /g » n'envoient plus rien d'eux-mêmes : le texte s'ouvre dans la discussion de guilde, à relire et envoyer. L'annonce d'une envie renvoie vers l'addon (onglet Groupe) plutôt que vers un chuchotement.

## 0.24.0
- **Onglet Groupe en une seule page** : « Ton groupe » en haut (le donjon et sa barre de niveaux, les cinq places, ce qui manque, l'alerte d'XP, inviter, chercher en /g, vider ; replié en une ligne tant que tu y es seul), puis les envies de donjon de la guilde en cartes (« Former le groupe » remplit la carte du haut), puis les membres en ligne à ta portée (un clic les place, Proposer, Écrire). Le choix du donjon montre tous les donjons, grisés hors de ton niveau.
- La page défile dans une hauteur fixe : la molette fait glisser les cartes au lieu d'en retirer, et la fenêtre ne change plus de taille en défilant.

## 0.23.2
- Envies : tes rôles apparaissent sur tes propres envies même avant la première publication de ta spé ; l'état d'une carte n'est plus coupé.

## 0.23.1
- Envies de donjon : une carte par donjon, comme la recherche de groupe du jeu. Les cinq places du groupe (pleines quand quelqu'un de disponible maintenant la tient), une barre de niveaux qui situe la tranche du donjon face au tien (vert : dans la tranche, jaune : à portée, gris : trop loin), puis les intéressés, les disponibles d'abord ; la note et le détail dans la bulle.
- Réglages : sans rôle déclaré, celui de ta spé est coché ; tu n'as plus qu'à ajouter ceux que tu sais jouer.

## 0.23.0
- **Envies de donjon** (onglet Groupe, bouton « Envies de donjon », ou `/opus envies`) : annonce que tu dois faire un ou plusieurs donjons (quêtes, objets, expérience, avec une note), quand tu es disponible (maintenant, ce soir, ce week-end, ou une précision libre) et combien de temps l'envie reste affichée (3 jours par défaut, jusqu'à ce soir pour « maintenant » et « ce soir »). Toute la guilde voit tous les donjons demandés, grisés hors de ton niveau (un reroll peut être du bon niveau), avec qui les veut, ses rôles, pourquoi et quand.
- « Moi aussi » sur un donjon : tu es partant, au créneau choisi. « Former » remplit le panneau de groupe avec ceux qui sont disponibles maintenant et en ligne ; « Annoncer en /g » prévient ceux qui n'ont pas l'addon.
- Une notification (quelques secondes, en haut de l'écran) annonce chaque nouvelle envie, et prévient quand un groupe complet est possible pour un donjon où tu es disponible. Réglable dans Réglages.

## 0.22.0
- **Plusieurs rôles** : dans Réglages, coche tout ce que tu sais jouer en donjon (un druide en dégâts qui soigne aussi) ; rien de coché, c'est le rôle de ta spé. Le groupe te place à une place libre de l'un de tes rôles, et une proposition te demande le rôle qui manque. Roster et Groupe montrent tous tes rôles (le principal en plus grand). `/opus role soin degats` fait la même chose.
- **Durée des essais** : devient un réglage de la guilde, partagé à tous et modifiable par le chef de guilde seulement (onglet Réglages, ou `/opus duree <grade> <jours>`), pour chaque grade d'essai de la grille.

## 0.21.0
- Guilde : **arrivées et départs en calendrier**, comme celui du jeu. Une case par jour avec le blason de classe de ceux qui arrivent (ligne verte) et de ceux qui partent (ligne rouge), le total du mois, et le détail du jour choisi en dessous (un clic sur un membre ouvre sa fiche). L'addon retient désormais la classe de chaque membre vu, pour garder son blason après son départ.

## 0.20.2
- Onglets dans l'ordre : Guilde, Roster, Groupe, Banque, Grades, Essais, Réglages, À propos.

## 0.20.1
- Guilde : le groupe « Commun » disparaît. Le chef et les officiers forment la « Direction » ; les autres grades sans voie (Pierre brute, les rerolls) ont leur propre groupe, à leur nom.
- Guilde : la colonne d'ancienneté est assez large pour « 05/11 (création) ».

## 0.20.0
- **Onglet Réglages** : ce qui ne se faisait que par `/opus` — annonce des montées de niveau, rôle, bouton de la minimap, durée des essais ; banque (synchroniser) et liaisons Discord (état, import) ; pour le chef et les officiers, restriction et cotisation, contrôle des droits, réglages à faire à la main ; diagnostics. Les commandes `/opus` restent.
- Onglets : Banque, Guilde, Roster, Groupe, Grades, Réglages, Essais, À propos (Essais passe juste avant À propos).

## 0.19.1
- **Niveaux** : l'addon note chaque montée de niveau des membres de la guilde (roster relu chaque minute) et annonce le niveau 60 dans la discussion et au milieu de l'écran, avec le son de montée de niveau. `/opus niveaux` règle les annonces : `60` (par défaut), `paliers` (10, 20… 60), `tous` ou `aucun`. Les dates passent d'un membre à l'autre : on retrouve à la connexion celles qu'on a manquées.
- Fiche d'un membre : bloc « Ses niveaux », avec le 60 mis en avant (ou le dernier niveau), et la liste complète en dépliant ; bloc « Ses persos », une ligne par perso du même joueur (classe, niveau, grade, connexion), un clic ouvre sa fiche.
- Guilde : la banque quitte la liste et la fiche (elle a son onglet) ; la liste montre à la place la dernière connexion avec la dernière zone connue, et « +N » à côté du pseudo Discord pour ses autres persos.

## 0.18.3
- Guilde : nouvelle colonne « Joueur » dans la liste des membres, avec le pseudo Discord de chacun (étoile sur son main, en gris sur un reroll), sans avoir à ouvrir sa fiche.
- Guilde : l'étoile d'un main est l'icône du jeu (marqueur de raid) ; l'emoji ⭐ s'affichait en carré.

## 0.18.2
- Guilde : dans la fiche, note publique et note d'officier côte à côte, chacune avec son bouton « Modifier » et sa boîte qui défile ; sans les droits d'officier, la note publique prend toute la largeur.

## 0.18.1
- Guilde : les notes longues restent dans une boîte de hauteur limitée de la fiche, qui défile à la molette (avec ascenseur), au lieu d'agrandir la fenêtre au-delà de l'écran.

## 0.18.0
- **Liaisons Discord** : avec le bot de la guilde, un officier colle le code de `/persoadmin export` (`/opus import`) ; l'addon le partage aux membres. La fiche d'un membre montre son pseudo Discord, s'il s'agit de son main ou d'un reroll, et ses autres persos. Le plafond de la banque du cœur couvre tous les persos d'un joueur relié, même sans l'addon. `/opus discord` : état des liaisons.
- **Notes de l'addon**, sans la limite de 31 caractères du jeu (jusqu'à 1000) : note publique, lue par tous (écrite par le chef, les officiers ou le joueur sur ses propres persos), et note d'officier, réservée au chef et aux officiers (canal des officiers, effacée chez qui perd ce grade). Boutons dans la fiche du membre ; rattrapées à la connexion.

## 0.17.2 — première version publique
Outils de guilde pour WoW Forever, faits pour la guilde Opus (PvE, EU) et configurables pour toute guilde.

- **Essais** : suivi des Apprentis et des Aspirants, jours restants et grades visés ; promotions et annulations en un clic par boutons sécurisés (selon tes droits), note d'officier préparée à coller ; dates d'essai partagées à ceux qui ne lisent pas les notes d'officier (à défaut, le passage au grade d'essai relevé dans le journal).
- **Banque** : qui a déposé ou retiré de l'or et des objets, qui a utilisé les réparations ; relevé à chaque ouverture et partagé entre les membres qui ont l'addon, il suffit que l'un d'eux passe à la banque. Avec la banque du cœur : une cotisation hebdomadaire entièrement volontaire, barème par niveau et plafond par joueur.
- **Guilde** : membres par voie, fiches (arrivée, histoire, banque, notes) et journal de guilde conservé un an.
- **Roster** : rôles, classes et spés annoncées par l'addon de chacun.
- **Groupe** : former un groupe de donjon avec les membres en ligne de la bonne tranche (avec Dungeon Journal), chuchotement tout prêt, proposition par fenêtre, annonce en guilde, alerte quand l'écart de niveau rend les monstres gris.
- **Grades** : grille des droits comparée en direct au jeu, éditeur de grade, restriction temporaire et cotisation, partagés par le chef et les officiers.
- Apparence native de Forever, bouton de minimap et compartiment d'addons ; `/opus` ouvre la fenêtre.

## 0.17.1
- Guilde : les icônes de classe s'affichent correctement en début de ligne.
- Guilde : l'ancienneté d'un membre arrivé avant le journal relevé affiche la date de création de la guilde (Opus) ou « avant le » début du journal (autres guildes), au lieu de « aujourd'hui ».
- Banque : le texte de la banque du cœur ne dépasse plus en bas de la fenêtre.

## 0.17.0
- Réglages de la guilde (chef et officiers, `/opus reglages` ou bouton dans l'onglet Grades) : restriction temporaire (date de fin, réparations et/ou retraits d'or coupés) et barème de la cotisation, partagés avec la grille.

## 0.16.0
- Banque : la banque du cœur, cotisation hebdomadaire **entièrement volontaire** qui finance les onglets de banque et les recettes rares. Repère par personnage selon son niveau, plafonné par joueur ; colonne « Semaine » (✓ quand c'est fait, jamais de rouge) et total de la semaine. La semaine commence au reset du mercredi.
- Les personnages d'un même joueur sont reconnus (ceux qui se connectent sur le même compte avec l'addon) pour le plafond.

## 0.15.0
- Nouvel onglet **Groupe** : la formation de groupe de donjon quitte le Roster.

## 0.14.0
- Nouvel onglet **À propos** : la guilde, le contact, le Discord et toutes les commandes.

## 0.13.0
- Groupe : changer de donjon prévient les membres déjà placés.
- Groupe : alerte d'XP quand l'écart de niveau rend les monstres gris (13 niveaux ou plus) — dans le groupe, la liste des candidats et la proposition.

## 0.12.0
- Groupe : « Écrire » ouvre un chuchotement avec la proposition déjà rédigée.
- Groupe : « Proposer » ouvre une fenêtre chez les membres qui ont l'addon (« Je viens ! » / « Pas cette fois ») ; une acceptation les place dans le groupe et propose l'invitation.

## 0.11.0
- Former un groupe de donjon : tranche de niveaux du donjon (avec l'addon Dungeon Journal, sinon ±3 niveaux), une place par rôle, invitation et annonce en guilde.
- `/opus role tank|soin|degats|auto` : déclarer son rôle quand la spé ne le dit pas (druide farouche…).

## 0.10.0
- Nouvel onglet **Roster** : rôles de la guilde, classes et spés (annoncées par l'addon de chacun), membres triables ; un clic ouvre la fiche.

## 0.9.0
- Grille configurable par guilde : éditeur de grade (rôle, voie, essai et sorties, droits, or, onglets), partagée par le chef et les officiers.
- Nouvel onglet **Guilde** : membres par voie, fiches (arrivée, histoire, banque, notes) et journal de guilde.
- Essais : les boutons n'apparaissent que si l'on a le droit en jeu ; dates d'essai partagées aux membres qui ne lisent pas les notes d'officier.

## 0.8.0
- Grades : une seule grille, rôle et voie de chaque grade expliqués ; restriction avant l'ouverture des raids appliquée d'office.

## 0.7.0
- Journal de guilde (arrivées, départs, grades) relevé et conservé un an.
- Bouton de minimap et entrée dans le compartiment d'addons.

## 0.6.0
- Fenêtre aux cadres natifs du client : médaillon à l'emblème, onglets, boutons et menus du jeu.

## 0.5.0
- Banque : les relevés sont partagés entre les membres qui ont l'addon (il suffit qu'un seul passe à la banque) ; rattrapage à la connexion.

## 0.4.0
- Banque : participation de chacun (or, réparations, objets), relevée dans les journaux de la banque de guilde.

## 0.1.0 à 0.3.0
- Suivi des membres à l'essai (Apprentis, Aspirants), promotions par boutons sécurisés (`/gpromote`), annulation, note d'officier préparée à coller.
- Contrôle des droits des grades face à la grille.
