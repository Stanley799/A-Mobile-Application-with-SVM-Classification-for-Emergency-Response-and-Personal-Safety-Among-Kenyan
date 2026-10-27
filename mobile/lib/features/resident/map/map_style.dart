// Emergency map style: no shops, restaurants, malls or transit clutter. Roads and water stay readable; our own pins are the loudest things.
const String kEmergencyMapStyle = '''
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
