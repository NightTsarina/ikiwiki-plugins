// vim:ts=2:sw=2:et:ai:sts=2:cinoptions=(0

var _automap_layers = new Array;
var _automap_maps = new Array;
var _automap_map_data = new Array;

var _icons = new Array;
var _iconpath;
var _basepath;


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

function load_layer(name, path, description, cluster, hidden) {
  var text = load_file(path, 'application/json');
  if (! text)
    return;

  var data;
  if (window.JSON)
    data = JSON.parse(text);
  else
    data = eval(text);

  _automap_layers[name] = {
    'name': name,
    'data': data,
    'desc': description,
    'cluster': cluster,
    'hidden': hidden,
  };
}

function create_icons() {
  var pubicon = new L.Icon({
    iconUrl: 'my-icon.png',
    iconRetinaUrl: 'my-icon@2x.png',
    iconSize: [38, 95],
    });
}

function add_main_layer(name, data) {
  _automap_map_data[name] = data;
}

/*
 * create_map: Creates a map inside a DIV.
 *
 * Args:
 *   name: ID of the container DIV.
 *   layers: Array of layer names to include.
 *   base_url: URL to append to every page link.
 *   page: IkiWiki page name where the map is to be embedded.
 *   create_url: URL prefix to create a new wiki page.
 *   tiles: URI template for the map tiles.
 *   attrib: HTML text for data attribution.
 */

function create_map(name, layers, base_url, page, create_url, tiles,
                    attrib) {
  layers = layers || [];
  base_url = base_url ? (base_url + '/') : '';
  page = page || '';
  create_url = create_url || '';
  tiles = tiles || 'http://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
  attrib = attrib || (
    'Map data &copy; <a href="http://openstreetmap.org">' +
    'OpenStreetMap</a> contributors, <a ' +
    'href="http://creativecommons.org/licenses/by-sa/2.0/">' +
    'CC-BY-SA</a>');

  var map = new L.Map(name);
  _automap_maps[name] = map;
  map.fitWorld();  // Initial defined view, so things like openPopup work.

  var tiles = L.tileLayer(tiles, {attribution: attrib, maxZoom: 18});
  map.addLayer(tiles);

  var seen_ids = new Array;
  var layers_to_add = new Array;
  var layer_controls = new Array;

  if (name in _automap_map_data) {
    layers_to_add.push({
                       'name': 'self',
                       'data': _automap_map_data[name],
                       'cluster': false,
                       'hidden': false,
                       });
  }

  for (var i in layers) {
    if (layers[i] in _automap_layers)
      layers_to_add.push(_automap_layers[layers[i]]);
  }

  for (var i in layers_to_add) {
    var layer = layers_to_add[i];
    var featgroup;
    if (layer['cluster']) {
      var options = {
        'spiderfyOnMaxZoom': false,
        'showCoverageOnHover': false,
        'zoomToBoundsOnClick': true,
        'disableClusteringAtZoom': 18
      };
      featgroup = new L.MarkerClusterGroup(options);
    } else {
      featgroup = new L.FeatureGroup();
    }

    for (var j = 0; j < layer['data'].length; j++) {
      item = layer['data'][j];
      if (item['id'] in seen_ids)
        continue;
      seen_ids[item['id']] = 1;

      var latlon = new L.LatLng(item['coord'][0], item['coord'][1]);
      var marker = new L.Marker(latlon);
      featgroup.addLayer(marker);

      var link;
      if (item['create']) {
        link = ('<span class="createlink"><a href="' + create_url +
                '&amp;page=' + item['page'] + '" rel="nofollow">?</a>' +
                item['title'] + '</span>');
      } else if (item['page'] == page) {
        link = '<span class="selflink">' + item['title'] + '</span>';
      } else {
        link = ('<a href="' + base_url + item['page'] + '">' +
                item['title'] + '</a>');
      }
      var text = '<b>' + link + '</b>';
      if ('prop' in item && 'address' in item['prop']) {
        text += '<br/>' + item['prop']['address'];
      }
      marker.bindPopup(text);
    }
    if (! layer['hidden'])
      map.addLayer(featgroup);

    if (layer['name'] == 'self') {
      map.fitBounds(featgroup.getBounds());
      featgroup.eachLayer(function(marker) {
                          var popup = marker.getPopup();
                          popup.setLatLng(marker.getLatLng());
                          map.addLayer(popup);
                          });
    } else {
      layer_controls[layer['desc']] = featgroup;
    }
  }
  L.control.layers(undefined, layer_controls).addTo(map);
}

hook('onload', function() {
     run_hooks('map_layers');
     run_hooks('maps');
     });
