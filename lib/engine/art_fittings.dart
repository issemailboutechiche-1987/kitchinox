// Accessoires de l'atelier : charnières, assemblages (vis et tourillons), suspension des meubles hauts,
// pieds des meubles bas, jonction entre caissons voisins. Le choix (par défaut pour tout le meuble, et par
// porte pour la charnière) commande l'usinage posé automatiquement et la liste de quincaillerie.
library;

/// Charnières de porte.
enum HingeType {
  applique('Charnière 110° en applique', 'la porte couvre le côté du caisson', 35),
  semiApplique('Charnière 110° semi-applique', 'deux portes sur un même côté (côté partagé)', 35),
  encloisonnee('Charnière 110° encloisonnée', 'la porte se loge entre les côtés', 35),
  grandAngle('Charnière 165° grand angle', 'ouverture totale (tiroirs intérieurs, angles)', 35),
  angle45('Charnière d’angle 45°', 'porte d’un meuble d’angle à pan coupé', 35),
  pushOpen('Charnière sans ressort + poussoir', 'porte sans poignée : on pousse pour ouvrir', 35),
  verre('Charnière pour porte en verre', 'pince sur le verre, sans perçage de la porte', 0),
  mini26('Mini-charnière Ø26', 'petites portes et façades fines (16 mm et moins)', 26),
  invisible('Charnière invisible à encastrer', 'aucune charnière visible, porte affleurante', 0),
  piano('Charnière piano (continue)', 'sur toute la hauteur : coffres, abattants légers', 0);

  final String label, usage;
  final int cup; // diamètre du boîtier percé dans la porte (0 : pas de boîtier)
  const HingeType(this.label, this.usage, this.cup);
}

/// Assemblage des panneaux de structure (chant contre face).
enum JointType {
  confirmat('Vis Confirmat Ø7 x 50 + tourillons', 'Vis Confirmat Ø7 x 50 mm', 'solide, démontable, tête visible (cache-vis)'),
  confirmat70('Vis Confirmat Ø7 x 70 + tourillons', 'Vis Confirmat Ø7 x 70 mm', 'panneaux épais (25 mm et plus)'),
  minifix('Excentrique Minifix Ø15 + tige + tourillons', 'Excentrique Minifix Ø15 + tige d’assemblage', 'démontable, rien de visible à l’extérieur'),
  visBois('Vis bois Ø4 x 40 + tourillons', 'Vis à bois agglo Ø4 x 40 mm', 'simple et économique'),
  euro('Vis euro Ø6,3 x 13 (quincaillerie système 32)', 'Vis euro Ø6,3 x 13 mm', 'fixation de quincaillerie dans les trous de 5 mm'),
  pocket('Vis à trou de poche Ø4 x 30', 'Vis pour trou de poche Ø4 x 30 mm', 'cachée sous le panneau, montage rapide'),
  tourillons('Tourillons collés seuls', '', 'collé, définitif'),
  lamello('Lamelles (biscuits) n° 20 collées', 'Lamelle bois n° 20', 'collé, alignement parfait des faces');

  final String label, screw, usage;
  const JointType(this.label, this.screw, this.usage);
}

/// Fixation des meubles hauts au mur.
enum HangType {
  boitier('Boîtiers de suspension réglables + rail', 'Boîtier de suspension réglable (gauche / droite)', 'Rail de suspension'),
  plaque('Plaques de suspension à visser', 'Plaque de suspension à visser', ''),
  tasseau('Tasseau biseauté (French cleat)', 'Tasseau biseauté 45°', ''),
  equerre('Équerres de fixation + chevilles', 'Équerre de fixation 40 x 40', '');

  final String label, item, rail;
  const HangType(this.label, this.item, this.rail);
}

/// Appui des meubles bas au sol.
enum FootType {
  verin('Pieds vérins réglables 100 à 150 mm', 'Pied vérin réglable 100 à 150 mm', 'Clip de plinthe'),
  metal('Pieds métal design', 'Pied métal design', ''),
  roulette('Roulettes avec frein', 'Roulette Ø50 avec frein', ''),
  socle('Socle en panneau (pas de pied)', '', '');

  final String label, item, clip;
  const FootType(this.label, this.item, this.clip);
}

/// Jonction de deux caissons posés côte à côte (côtés face contre face).
enum LinkType {
  visJonction('Vis de jonction (manchon) Ø5', 'Vis de jonction avec manchon Ø5 x 30'),
  boulon('Boulons M6 + écrous à griffes', 'Boulon M6 + écrou à griffes'),
  visBois('Vis bois Ø4 x 30 (définitif)', 'Vis à bois agglo Ø4 x 30 mm'),
  aucun('Pas de jonction', '');

  final String label, item;
  const LinkType(this.label, this.item);
}

/// Accessoires choisis pour le meuble de l'atelier.
class ArtFittings {
  HingeType hinge;
  JointType joint;
  HangType hang;
  FootType foot;
  LinkType link;
  ArtFittings({
    this.hinge = HingeType.applique,
    this.joint = JointType.confirmat,
    this.hang = HangType.boitier,
    this.foot = FootType.verin,
    this.link = LinkType.visJonction,
  });

  bool get isDefault =>
      hinge == HingeType.applique && joint == JointType.confirmat && hang == HangType.boitier && foot == FootType.verin && link == LinkType.visJonction;

  Map<String, dynamic> toJson() => {'hinge': hinge.name, 'joint': joint.name, 'hang': hang.name, 'foot': foot.name, 'link': link.name};

  static T _e<T extends Enum>(List<T> v, Object? n, T d) => v.where((x) => x.name == n).firstOrNull ?? d;
  factory ArtFittings.fromJson(Map<String, dynamic> j) => ArtFittings(
        hinge: _e(HingeType.values, j['hinge'], HingeType.applique),
        joint: _e(JointType.values, j['joint'], JointType.confirmat),
        hang: _e(HangType.values, j['hang'], HangType.boitier),
        foot: _e(FootType.values, j['foot'], FootType.verin),
        link: _e(LinkType.values, j['link'], LinkType.visJonction),
      );
}
