// Two looks for the navigation map. The map swaps between them as you zoom (see styleForZoom): calm and uncluttered for the whole trip,
// then, from street level, everything Google knows (buildings, shops, landmarks, transit, plot labels). Google draws the detail itself;
// these styles only decide what is shown.
const String kNavStyleOverview = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"simplified"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f6d9a8"}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f3f1ec"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cfe3ee"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5f5f5f"}]}
]
''';

const String kNavStyleDetail = '''
[
  {"featureType":"poi","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"on"}]},
  {"featureType":"transit","stylers":[{"visibility":"on"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"on"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#2b2b2b"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"},{"weight":3}]},
  {"featureType":"road.local","elementType":"geometry.stroke","stylers":[{"color":"#e2ded5"}]}
]
''';
