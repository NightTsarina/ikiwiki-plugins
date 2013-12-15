#!/usr/bin/perl
# vim:ts=2:sw=2:et:ai:sts=2:cinoptions=(0
package IkiWiki::Plugin::automap;

use warnings;
use strict;
use utf8;

=head1 NAME

IkiWiki::Plugin::automap - 

=head1 VERSION

This describes version B<0.1> of IkiWiki::Plugin::automap

=cut

our $VERSION = '0.1';

=head1 DESCRIPTION

See doc/plugins/contrib/automap and ikiwiki/directive/automap for docs.

=head1 PREREQUISITES

    IkiWiki
    YAML::Any
    JSON

=head1 AUTHOR

    Martín Ferrari (TINCHO)

=head1 COPYRIGHT

Copyright (c) 2013 Martín Ferrari

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

sub import {
  hook(type => "getsetup", id => "automap", call => \&getsetup);
  hook(type => "checkconfig", id => "automap", call => \&checkconfig);
  hook(type => "scan", id => "automap", call => \&scan);
  hook(type => "preprocess", id => "mapitem", call => \&preprocess_mapitem);
  hook(type => "preprocess", id => "automap", call => \&preprocess_automap);
  hook(type => "pagetemplate", id => "automap", call => \&pagetemplate);
}

# ------------------------------------------------------------
sub getsetup () {
  return (
    plugin => {
      safe => 1,
      rebuild => 1,
    },
    automap_base => {
      type => 'string',
      description => 'Parent page for data read and created by automap.',
      example => 'mapitems',
      safe => 1,
      rebuild => 1,
    },
    automap_create => {
      type => 'boolean',
      description => 'Create stub pages for unlinked map items.',
      safe => 1,
      rebuild => 1,
    },
  );
  use IkiWiki::Plugin::transient;
}

our $data_regex;
our $yaml_impl;

sub checkconfig () {
  eval { use JSON; };
  error ('automap: Failed to load the JSON library.') if $@;
  eval { use YAML::Any; };
  error ('automap: Failed to load the YAML library.') if $@;

  $YAML::UseBlock = 1;
  $yaml_impl = YAML::Any->implementation();
  if ($yaml_impl eq 'YAML::Syck') {
    $YAML::Syck::ImplicitUnicode = 1;
  }

  if (not defined $config{automap_base}) {
    $config{automap_base} = 'mapitems';
  }
  my $base = $config{automap_base};
  $data_regex = qr(^\Q$base\E/([\w-]+)/(node|way)_(\d+)._yaml$)o;
}

sub scan (@) {
  my %params = @_;
  my $page = $params{page};
  my $content = $params{content};

  # Clean data for a page that's being rebuilt.
  if (exists $pagestate{$page}{automap} and
      exists $pagestate{$page}{automap}{mapitems} and
      ref $pagestate{$page}{automap}{mapitems}) {
    foreach my $item (keys %{$pagestate{$page}{automap}{mapitems}}) {
      if ($pagestate{$item}{automap}{backlink} and
          $pagestate{$item}{automap}{backlink} eq $page) {
        delete $pagestate{$item}{automap}{backlink};
      }
    }
    delete $pagestate{$page}{automap};
  }
  return if ($page !~ /$data_regex/ or not $content);
  my ($map, $type, $id) = ($1, $2, $3);

  debug ("automap::scan $page $1 $2 $3");
  if ($yaml_impl eq 'YAML::XS') {
    # Stupid broken unicode support.
    utf8::encode($content);
  }
  my $data;
  eval {
    $data = Load($content);
  };
  if ($@) {
    warn "content: $content " . utf8::is_utf8($content) ;
    warn(sprintf(gettext("automap: Error reading YAML data from %s: %s\n"),
                 $page, "$@"));
    return;
  }
  if (not defined $data or not ref $data or not ref $data eq 'HASH') {
    warn(sprintf(gettext("automap: Invalid YAML data in %s.\n"), $page));
    return;
  }
  if (not $data->{id} or $data->{id} != $id or
      not $data->{type} or $data->{type} ne $type) {
    warn(sprintf(gettext("automap: Data mismatch in %s.\n"), $page));
    return;
  }
  $pagestate{$page}{automap} = $data;
  $pagestate{$page}{automap}{map} = $map;
}

#FIXME: check modifications.
sub preprocess_mapitem (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $preview = $params{preview};

  my $map = $params{map} || 'map';
  my $type = $params{type} || 'node';
  my $id = $params{id};
  if (not $id) {
    error(gettext('mapitem: missing "id" parameter.'));
  }
  if ($type !~ /^(way|node)$/) {
    error(gettext('mapitem: Invalid map item type: ') . $type);
  }
  if ($id !~ /^\d+$/) {
    error(gettext('mapitem: Invalid map item id: ') . $id);
  }
  if ($map !~ /^[\w-]+$/) {
    error(gettext('mapitem: Invalid map name: ' . $map));
  }
  my $datapage = "$config{automap_base}/${map}/${type}_${id}._yaml";
  if (not exists $pagestate{$datapage} or
      not exists $pagestate{$datapage}{automap} or
      not $pagestate{$datapage}{automap}) {
    error(sprintf(gettext('mapitem: Map item not found: %s.'), $datapage));
  }
  if (exists $pagestate{$datapage}{automap}{backlink} and
      $pagestate{$datapage}{automap}{backlink} ne $page) {
    error(gettext('mapitem: Duplicate linking to the same map item.'));
  }

  $pagestate{$datapage}{automap}{backlink} = $page;
  $pagestate{$page}{automap}{mapitems}{$datapage} = '';
  add_depends($page, "internal($datapage)");
  return '';
}

# FIXME: orden de backlinks.
sub preprocess_automap (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $preview = $params{preview};
  my $map = $params{map} || 'map';
  my $layer = $params{layer} || 'mapitems';

  my @result;
  foreach my $mappage (keys %pagestate) {
    next if (not exists $pagestate{$mappage}{automap} or
             not exists $pagestate{$mappage}{automap}{map} or
             $pagestate{$mappage}{automap}{map} ne $map);
    my $mapdata = $pagestate{$mappage}{automap};
    push @result, $mapdata;
    add_depends($page, "internal($mappage)");
    if (exists $mapdata->{backlink}) {
      add_depends($page, $mapdata->{backlink});
    }
  }
  my @output = ();
  foreach (@result) {
    my %item = %$_;
    if (exists $item{backlink}) {
      $item{link} = htmllink($page, $destpage, $item{backlink});
      delete $item{backlink};
    }
    push @output, item2geojson(%item);
  }
  my $output = to_json({
      type => "FeatureCollection",
      features => \@output,
    }, {pretty => 1});
  return $output;
}

sub item2geojson (@) {
  my %item = @_;
  my $data = {
    type => "Feature",
    id => "$item{type}/$item{id}",
    geometry => {
      type => "Point",
      coordinates => [$item{lon} + 0.0, $item{lat} + 0.0],
    },
  };
  delete $item{type};
  delete $item{id};
  delete $item{lon};
  delete $item{lat};
  $data->{properties} = \%item;
  return $data;
}

sub pagetemplate (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $template = $params{template};

  if (exists $pagestate{$page}{automap} and
      exists $pagestate{$page}{automap}{mapitems} and
      ref $pagestate{$page}{automap}{mapitems}) {

    my @output = ();
    foreach my $mapitem (keys %{$pagestate{$page}{automap}{mapitems}}) {
      my %item = %{$pagestate{$mapitem}{automap}};
      if (exists $item{backlink}) {
        $item{link} = htmllink($page, $destpage, $item{backlink});
        delete $item{backlink};
      }
      push @output, item2geojson(%item);
    }
    my $output = to_json({
        type => "FeatureCollection",
        features => \@output,
      }, {pretty => 1});
    $template->param('has_map', 1);
    $template->param('automap_items_json', $output);
  }
}

1;
