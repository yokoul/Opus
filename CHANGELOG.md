# Opus — notes de mise à jour

Outils de guilde pour WoW Forever, faits pour la guilde **Opus** (royaume PvE, Europe).
Contact : **Illustre Inconnu** en jeu, ou le Discord de la guilde : https://discord.gg/XtSksuFU6v

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
