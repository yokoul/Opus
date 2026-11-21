# OpusLootSystem : contrat entre le site et l'addon

Brouillon du 20 novembre 2026. Ce document fixe ce que le site Opus (opus.yokoul.xyz) et l'addon s'échangent pour le
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
| `E` | id, tier, date, version des tables | En-tête. `id` est cité par le rapport ; `version des tables` change quand le site corrige une table de butin. |
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
OLS1:I:E;i-2026-12-09-a;T1;1765230000;1~P;50;25;15;10~J;Basara Nore;tank;0.5;1;0;main~J;Kibrom Felheart;heal;0;0.2;0.4;reroll~W;19019;Basara Nore:1,Kibrom Felheart:3~S;Kibrom Felheart,Basara Nore~#1a2b3c4d
```

## Rapport (addon → site)

Un enregistrement `E` d'en-tête (id du rapport, id de l'instantané utilisé, maître du butin, début, fin), puis un
enregistrement par événement. Chaque événement commence par sa lettre, son identifiant et sa date :
l'identifiant est `<maître du butin>/<début du raid>/<numéro d'ordre>`.

| Lettre | Événement | Champs propres |
| --- | --- | --- |
| `T` | Objet tombé | boss, itemID, présents (liste des noms complets) |
| `O` | Proposition | id de `T`, candidat retenu, détail du score de chaque candidat |
| `X` | Objection | id de `O`, auteur |
| `V` | Vote | id de `X`, pour, contre, abstentions, quorum atteint (0/1) |
| `D` | Décision des officiers | id de `O`, attributaire, officier, motif |
| `A` | Attribution | id de `T`, attributaire, voie (`wish`, `sk`, `de` ou `banque`) |
| `M` | Remise | id de `A`, destinataire de l'échange, mode (`echange`, `ramasse`) |
| `K` | Écart constaté | id de `A`, nature (`autre_destinataire`, `pas_remis`, `delai_proche`) |
| `C` | Correction | voir ci-dessous |

`T` porte les présents parce que le site en a besoin pour compter les prios perdues : un candidat absent ne perd rien.

## Objets dont personne ne veut

Un objet sans candidat en wishlist, que personne ne prend en Suicide King dans le délai, ne compte pour personne. Il
part par l'une de deux voies, au choix du maître du butin :

- **`de`, désenchantement** : l'objet va au premier désenchanteur désigné (`Z`) présent dans le raid. L'addon le
  propose ; le maître du butin peut en choisir un autre.
- **`banque`** : l'objet va à la banque de guilde, par exemple un objet lié quand équipé qu'on préfère vendre.

Ces deux voies ne touchent aucun compteur et ne déplacent personne dans la liste Suicide King. La remise suit le même
chemin que les autres (`M`, et un écart `K` si l'objet n'est pas remis).

Ce que deviennent les composants (dépôt à la banque, redistribution) n'est pas encore fixé.

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
| `compteur` | Un ajustement direct d'un compteur, en dernier recours. | compteur, valeur |

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

## Décisions

- Les compteurs « dernier loot » et « gain » se calculent sur tout le tier, pour commencer ; on ajustera à l'usage.
- Le quorum du vote est une part des présents non candidats (la part reste à fixer).
- Un seul officier valide un rapport.

## Questions ouvertes

- La part du quorum.
- Ce que deviennent les composants issus du désenchantement.
