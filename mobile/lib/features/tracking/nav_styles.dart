// Two looks for the navigation map. The map swaps between them as you zoom (see styleForZoom), so the whole trip stays calm and the
// last few hundred metres show street names and landmarks. Google draws the street detail itself; these styles only decide what is shown.
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
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.medical","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.government","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.school","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.place_of_worship","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"transit.station","stylers":[{"visibility":"on"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#2b2b2b"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"},{"weight":3}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f6d9a8"}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.local","elementType":"geometry.stroke","stylers":[{"color":"#e2ded5"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e8e3d8"}]},
  {"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#d6d0c2"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#eef0e6"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cfe3ee"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#4a4a4a"}]}
]
''';
