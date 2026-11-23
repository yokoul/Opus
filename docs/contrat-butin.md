# OpusLootSystem : contrat entre le site et l'addon

Brouillon du 20 novembre 2026. Ce document fixe ce que le site Opus (opus-guild.eu) et l'addon s'échangent pour le
butin de raid. Il ne dépend pas des tables de butin, inconnues avant l'ouverture des raids (9 décembre 2026).

## Principes

- **Le site est la source de vérité.** Il garde les wishlists, les compteurs et tout l'historique. L'addon applique un
  instantané pendant la soirée et tient le journal de cette soirée, sans mémoire longue.
- **Seuls les officiers portent l'instantané.** Le maître du butin l'importe ; un second officier l'importe aussi pour
  reprendre la main si le premier se déconnecte. Le raid ne reçoit que l'annonce de chaque objet quand il tombe
  (candidats, scores, proposition). Une synchronisation plus large viendra si le besoin se confirme en raid.
- **Deux voies, une seule donnée.** Une chaîne à copier-coller marche sans rien installer ; le client de la barre des
  tâches (officiers seulement) écrit et lit les mêmes chaînes dans les SavedVariables, jeu fermé. Il reste un confort.
- **Le retour est un journal d'événements, jamais un état.** Chaque événement a un identifiant unique : soumettre deux
  fois le même rapport ne compte rien en double.
- **Rien ne s'efface, tout se corrige.** Une correction est un nouvel événement qui vise l'événement corrigé (voir plus
  bas). Le site recalcule les compteurs à partir de tous les événements, corrections comprises.
- **Un personnage se désigne par son nom complet** « Prénom Nom », tel que le roster l'écrit. Jamais le prénom seul :
  Basara, Kibrom et d'autres sont portés par plusieurs membres.

## Encodage commun

- Texte ASCII imprimable plus UTF-8 pour les noms, une chaîne par sens.
- Préfixe : `OLS1:I:` pour un instantané, `OLS1:R:` pour un rapport (`1` = version du contrat).
- Enregistrements séparés par `~`, champs par `;` (les mêmes séparateurs que les messages de l'addon ; aucun nom de
  personnage ne les contient). Une liste dans un champ se sépare par `,`.
- Les nombres sont en base 10, les dates en secondes Unix (UTC).
- Fin de chaîne : `~#` suivi de la somme de contrôle Adler-32 en hexadécimal, calculée sur tout ce qui précède `~#`.
  Une chaîne tronquée ou abîmée au collage est refusée en entier.

## Instantané (site → addon)

Chaque enregistrement commence par sa lettre.

| Lettre | Champs | Rôle |
| --- | --- | --- |
| `E` | id, tier, date, version des tables, taille des listes | En-tête. `id` est cité par le rapport ; `version des tables` change quand le site corrige une table de butin ; la taille des listes du palier sert au calcul de la prio perso. |
| `P` | prio perso, prios perdues, dernier loot, gain | Les poids en vigueur (50, 25, 15, 10 au départ). Un changement voté sur le site s'applique au prochain instantané. |
| `J` | nom complet, rôle, prios perdues, dernier loot, gain, `main` ou `reroll` | Un joueur et ses compteurs, déjà normalisés par le site (0 à 1), pour que l'addon ne fasse qu'une somme pondérée. Le rôle est celui de sa liste (`tank`, `heal`, `dps`). |
| `W` | itemID, liste de « nom complet:rang » | Les candidats d'un objet et leur rang dans leur wishlist validée. |
| `S` | liste ordonnée des noms complets | La liste Suicide King, du premier au dernier. |
| `Z` | liste des noms complets | Les désenchanteurs désignés, dans l'ordre de préférence. |

L'instantané couvre toute la guilde, pas seulement le raid du soir : un joueur absent n'est simplement pas candidat,
et rien ne bloque. Seules les incohérences internes refusent l'instantané (un candidat qui n'est pas dans les `J`, un
compteur hors bornes, un joueur en double, une somme de contrôle fausse).

Exemple (abrégé) :

```
OLS1:I:E;i-2026-12-09-a;T1;1765230000;1;12~P;50;25;15;10~J;Basara Nore;tank;0.5;1;0;main~J;Kibrom Felheart;heal;0;0.2;0.4;reroll~W;19019;Basara Nore:1,Kibrom Felheart:3~S;Kibrom Felheart,Basara Nore~#1a2b3c4d
```

## Par le bridge

Le client opus-bridge écrit dans `OpusBridgeFeed.raids` ce que le site prépare pour le membre connecté (`GET /bridge/feed`,
clés françaises) : `maj` (date de génération), `paliers` (les paliers en cours, du plus récent au plus ancien ; pour
chacun ses `listes` — perso, statut, rôle, objets avec leur rang et la date de réception, prios perdues, dernier loot
en soirées (-1 : jamais servi), rang et longueur du Suicide King, présences — et ses `soirees` validées, les 12 plus
récentes, avec les présents et les attributions dans l'ordre de la soirée), et pour un officier du butin
`instantanes`, la chaîne `OLS1:I:` de chaque palier, que l'onglet Raids importe d'un clic. L'instantané ainsi
apporté date de la dernière connexion.

Dans l'autre sens, le rapport part sans copier-coller. Opus dépose la chaîne `OLS1:R:` dans `OpusDB.raid.rapport`
(`chaine`, `id` de la soirée, `n` événements, `complet`, `t`) quand la soirée de guilde se ferme, à l'export, et à la
déconnexion ou au /reload (la soirée encore ouverte part alors sans les écarts « pas_remis », notés à sa fermeture).
Seule une soirée de guilde se dépose : une annonce faite en groupe, soirée ouverte, la marque (`soiree.guilde`) ; les
essais hors groupe restent en jeu. Le bridge l'envoie à `POST /bridge/report` (`{ text }`) dès que WoW a écrit le
fichier, et une seule fois par chaîne. Le site l'importe comme s'il était collé, dans le palier de son instantané (à
défaut, celui où le rapport est déjà, ou le seul palier ouvert), et seulement pour un officier du butin ; un refus
(422, avec son message) n'est pas renvoyé.

## Proposition calculée

Pour un objet, l'addon classe les candidats **présents dans le raid** par un score sur 100 :

```
score = P.perso × (taille − rang + 1) / taille
      + P.perdues × prios perdues + P.dernier × dernier loot + P.gain × gain
```

Les trois compteurs arrivent normalisés entre 0 et 1, **1 étant le plus méritant** : beaucoup de prios perdues, pas
de loot depuis longtemps, gros gain. En cas d'égalité, le meilleur rang passe devant, puis le plus de prios perdues ;
l'égalité est annoncée et le maître du butin tranche. Un objet sans candidat présent part en Suicide King.

### Objection et vote

Dans le canal raid, sans addon côté joueurs. Chaque annonce porte un numéro `n`. « !objection n [motif] » pendant 3
minutes, d'un joueur ou d'un officier, ouvre un vote de 2 minutes **entre les candidats présents** (dans l'ordre du
calcul, numérotés dans l'annonce du vote) : « !vote n k » (k, le numéro du candidat, ou son nom ; « !vote k » s'il n'y a
qu'un vote en cours). Votent tous les présents sauf les joueurs qui ont l'objet en liste, officiers compris, une voix
chacun ; le dernier vote compte. Quorum : la moitié des électeurs (arrondie au-dessus). Quorum atteint : le vote
s'applique, le candidat en tête reçoit l'objet ; une égalité en tête passe aux officiers. Pas de quorum : la
proposition du calcul s'applique.

Les officiers (le raid et le progress : rôle clé, boss bloquant, égalité) peuvent trancher **à tout moment** avant
l'attribution, pendant le délai comme pendant le vote, toujours avec un motif (`D`).

## Rapport (addon → site)

Un enregistrement `E` d'en-tête : id du rapport (`<maître du butin>/<début du raid>`), id de l'instantané utilisé,
maître du butin, début, fin. Puis un enregistrement par événement, dans l'ordre du journal. Chaque événement commence
par sa lettre, son identifiant et sa date ; l'identifiant est `<maître du butin>/<début du raid>/<numéro d'ordre>`.

| Lettre | Événement | Champs propres, dans l'ordre |
| --- | --- | --- |
| `T` | Objet tombé | boss, itemID, présents (liste des noms complets) |
| `O` | Proposition | id de `T`, candidat retenu, scores (liste de « nom:score », score avec un point décimal) |
| `X` | Objection | id de `O`, auteur |
| `V` | Vote | id de `X`, voix du proposé, voix des autres candidats, abstentions, quorum atteint (0/1), gagnant (vide : égalité ou pas de quorum), voix de chaque candidat `nom:voix,…` |
| `D` | Décision des officiers | id de `O` (vide après un rechargement en plein Suicide King), attributaire, officier, motif |
| `A` | Attribution | id de `T`, attributaire (vide pour la banque), voie (`wish`, `sk`, `de` ou `banque`) |
| `M` | Remise | id de `A`, destinataire, mode (`echange` : par échange ; `ramasse` : le maître du butin lui-même ; `maitre` : donné depuis le corps par le menu du maître du butin) |
| `K` | Écart constaté | id de `A`, nature (`autre_destinataire`, `pas_remis`, `delai_proche`), détail (le destinataire réel, l'attributaire, ou les secondes d'échange restantes) |
| `C` | Correction | voir ci-dessous |

Le même rapport peut s'exporter plusieurs fois dans la soirée : le site garde chaque événement par son identifiant et
n'ajoute que les nouveaux. Un `K` `pas_remis` noté à un export est résolu de lui-même si une remise `M` de la même
attribution arrive dans un export suivant.

`T` porte les présents parce que le site en a besoin pour compter les prios perdues : un candidat absent ne perd rien.

## Suicide King

Un objet sans candidat présent en wishlist part en Suicide King. Pendant 1 minute, les intéressés se déclarent
(fenêtre de l'addon, ou « !sk n » dans le canal raid). L'intéressé présent le plus haut dans la liste gagne et passe en
bas ; les autres gardent leur ordre ; un intéressé absent de la liste vient après tous ceux qui y sont, et y entre en
bas s'il gagne. La liste de la soirée part de l'instantané (`S`) ; le site la recalcule depuis les attributions `A`
de voie `sk`, dans l'ordre du rapport.

## Objets dont personne ne veut

Un objet sans candidat en wishlist, que personne ne prend en Suicide King dans le délai, ne compte pour personne. Il
part au désenchantement s'il y a un désenchanteur présent, sinon à la banque :

- **`de`, désenchantement** : l'objet va au premier désenchanteur désigné (`Z`) présent dans le raid. L'addon le
  propose ; le maître du butin peut en choisir un autre.
- **`banque`** : l'objet va à la banque de guilde, par exemple un objet lié quand équipé qu'on préfère vendre.

Ces deux voies ne touchent aucun compteur et ne déplacent personne dans la liste Suicide King. La remise suit le même
chemin que les autres (`M`, et un écart `K` si l'objet n'est pas remis).

Les composants de désenchantement vont à la banque de guilde, où les membres peuvent les demander (décision du
2026-11-22).

## Corrections

Les journaux ne voient pas tout : un objet remis à quelqu'un d'autre avec l'accord des officiers en vocal, un objet
qui change de mains entre deux joueurs, un butin ramassé hors de l'addon, une erreur de clic. Ces cas passent par un
événement `C`, jamais par une modification.

`C` : identifiant, date, événement visé (ou vide pour un ajout), nature, nouvelle valeur, auteur, motif, officiers
qui ont donné leur accord (liste, peut être vide).

| Nature | Usage | Nouvelle valeur |
| --- | --- | --- |
| `reattribution` | L'objet est allé à quelqu'un d'autre que l'attributaire. | nom complet |
| `annulation` | L'attribution ne compte pas (objet perdu, rendu). | vide |
| `ajout` | Un objet attribué sans que l'addon le voie. | itemID, attributaire, voie |
| `voie` | L'attribution est passée par la mauvaise voie (wishlist, Suicide King, désenchantement, banque). | `wish`, `sk`, `de` ou `banque` |
| `compteur` | Un ajustement direct des prios perdues d'un joueur, en dernier recours. | nom complet, écart (+1, −2…) |

| `confirmation` | Un écart `K` était voulu (l'événement visé est le `K`). | vide |

Le motif est obligatoire. Le site garde l'événement d'origine et la correction côte à côte : l'historique affiche
« corrigé » et le détail au survol.

### Où saisir une correction

1. **Sur le site, à la revue du rapport (première version).** Un rapport soumis passe par trois états : *importé*,
   *en revue*, *validé*. Pendant la revue, les officiers voient les attributions et les écarts `K`, et ajoutent les
   corrections. Seuls les rapports validés entrent dans les compteurs du prochain instantané. Un rapport validé peut
   encore recevoir une correction plus tard ; les compteurs sont alors recalculés.
2. **En jeu, plus tard.** Un bouton « Réattribuer » ou « Annuler » sur une attribution, chez le maître du butin, produit
   le même événement `C` dans le rapport. Le site n'a rien à changer pour l'accepter.

### Ce que l'addon détecte seul

Pour limiter la saisie, l'addon du maître du butin compare chaque remise à l'attribution :

- l'objet part par échange à quelqu'un d'autre que l'attributaire → `K` `autre_destinataire` ;
- l'objet n'est pas remis à la fin du raid → `K` `pas_remis` ;
- il reste moins de 20 minutes sur le temps d'échange → `K` `delai_proche`, et une alerte en jeu.

Chaque écart doit être résolu à la revue : par une correction, ou par une confirmation (« c'était voulu »). Un échange
entre deux joueurs, sans le maître du butin, reste invisible : il passe par une correction saisie à la main.

## Les compteurs

Le site les calcule à chaque instantané, à partir des rapports **validés** du palier, corrections comprises, dans
l'ordre des attributions (spécification WishVote, § 3). Les candidats d'un objet sont les joueurs présents (`T`) qui
l'ont dans leur wishlist validée.

- **Prios perdues** : +1 à chaque candidat présent quand l'objet part à un autre, quelle que soit la voie ; remise à 0
  quand le joueur reçoit un objet de sa wishlist. Un absent ne bouge pas. Normalisé : compteur ÷ le plus grand
  compteur de la guilde.
- **Dernier loot de wishlist** : le nombre de soirées validées du tier où le joueur était présent (dans la liste des
  présents d'au moins un objet tombé) depuis son dernier objet de wishlist ; 0 s'il l'a reçu à sa dernière soirée, une
  absence ne compte pas. Normalisé : soirées ÷ (le plus grand écart + 1) ; un joueur jamais servi vaut 1 et passe devant
  tous.
- **Gain** : 0 pour l'instant. Il dépend de l'équipement porté (bonus de set, écart de paliers), que le site ne
  connaît pas encore.
- **Liste Suicide King** : l'ordre de départ fixé par les officiers sur le site, puis, rapport après rapport, chaque
  gagnant d'une attribution `sk` passe en bas. L'instantané porte la liste qui en résulte (`S`) et les
  désenchanteurs (`Z`) ; chaque nom de `S` a son enregistrement `J`, wishlist ou pas.

## Décisions

- Les compteurs « dernier loot » et « gain » se calculent sur tout le tier, pour commencer ; on ajustera à l'usage.
- Le quorum du vote est la moitié des présents non candidats (arrondie au-dessus).
- Un seul officier valide un rapport.
- Les composants issus du désenchantement vont à la banque de guilde, où les membres peuvent les demander.
- Le Suicide King reste simple : le gagnant passe en bas de la liste à chaque attribution (variante confirmée le
  2026-11-22).
- Ces règles sont celles des raids de guilde (10 et 20). Les raids à 40 se feront en alliance, avec des règles propres
  définies avec l'alliance.
