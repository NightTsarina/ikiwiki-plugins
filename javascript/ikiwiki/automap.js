// vim:ts=2:sw=2:et:ai:sts=2:cinoptions=(0

var _defined_layers = new Array;
var _maps = new Array;

function load_file(path, type) {
  var req;
  if (window.XMLHttpRequest) {
    req = new XMLHttpRequest();
  } else {
    req = new ActiveXObject('Microsoft.XMLHTTP');
  }
  req.overrideMimeType(type);
  req.open('GET', path ,false);
  req.send();
  return req.responseText;
}

function load_layer(name, path, base_url, main_layer, cluster) {
  var text = load_file(path, 'application/json');
  if (! text)
    return;

  var data;
  if (window.JSON)
    data = JSON.parse(text);
  else
    data = eval(text);
  add_layer(name, data, base_url, main_layer, cluster);
}

function add_layer(name, data, base_url, main_layer, cluster) {
  _defined_layers[name] = {
    'data': data,
    'base_url': base_url,
    'main_layer': main_layer,
    'cluster': cluster,
  };
}

function create_map(name, layers) {
  var tiles = 'http://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
  var attrib = ('Map data &copy; <a href="http://openstreetmap.org">' +
                'OpenStreetMap</a> contributors, <a ' +
                'href="http://creativecommons.org/licenses/by-sa/2.0/">' +
                'CC-BY-SA</a>');

  var map = new L.Map(name);
  _maps[name] = map;
  map.fitWorld();  // Initial defined view, so things like openPopup work.

  var tiles = L.tileLayer(tiles, {attribution: attrib, maxZoom: 18});
  map.addLayer(tiles);

  var ids = new Array;
  var bounds = new L.LatLngBounds();

  layers = layers || [];
  for (var i = 0; i < layers.length; i++) {
    var layer_name = layers[i];
    if (!(layer_name in _defined_layers))
      continue;

    var layer = _defined_layers[layer_name];
    var create = layer['create'];
    var base_url = layer['base_url'];
    var main_layer = layer['main_layer'];

    var lg;
    if (layer['cluster']) {
      var options = {
        'spiderfyOnMaxZoom': false,
        'showCoverageOnHover': false,
        'zoomToBoundsOnClick': true,
        'disableClusteringAtZoom': 18
      };
      lg = new L.MarkerClusterGroup(options);
    } else {
      lg = new L.FeatureGroup();
    }
    map.addLayer(lg);

    for (var j = 0; j < layer['data'].length; j++) {
      item = layer['data'][j];
      if (item['id'] in ids)
        continue;
      ids[item['id']] = 1;

      var latlon = new L.LatLng(item['coord'][0], item['coord'][1]);
      var marker = new L.Marker(latlon);
      lg.addLayer(marker);

      var link = ('<a href="' + base_url + '/' + item['page'] + '">' +
                  item['title'] + '</a>');
      if (item['create']) {
        // FIXME
        link = ('<span class="createlink"><a href="' + base_url +
                '/ikiwiki.cgi?from=pubs&amp;do=create&amp;page=' +
                item['page'] + '" rel="nofollow">?</a>' + item['title'] +
                '</span>');
      }
      var text = '<b>' + link + '</b>';
      if ('prop' in item && 'address' in item['prop']) {
        text += '<br/>' + item['prop']['address'];
      }
      marker.bindPopup(text);
      if (main_layer) {
        marker.openPopup();
        bounds.extend(latlon);
      }
    }
  }
  if (bounds.isValid())
    map.fitBounds(bounds);
}

hook('onload', function() {
     run_hooks('map_layers');
     run_hooks('maps');
     });
