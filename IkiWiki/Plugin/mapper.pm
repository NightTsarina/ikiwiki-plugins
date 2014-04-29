#!/usr/bin/perl
# vim:ts=2:sw=2:et:ai:sts=2:cinoptions=(0
package IkiWiki::Plugin::mapper;

use warnings;
use strict;
use utf8;

=head1 NAME

IkiWiki::Plugin::mapper - 

=head1 VERSION

This describes version B<0.1> of IkiWiki::Plugin::mapper

=cut

our $VERSION = '0.1';

=head1 DESCRIPTION

See doc/plugins/contrib/mapper and ikiwiki/directive/mapper for docs.

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
  hook(type => "getsetup", id => "mapper", call => \&getsetup);
  hook(type => "checkconfig", id => "mapper", call => \&checkconfig);
  hook(type => "scan", id => "mapper", call => \&scan);
  hook(type => "preprocess", id => "mapper_new_layer", scan => 1,
       call => \&preprocess_new_layer);
  hook(type => "preprocess", id => "mapper_add_waypoint",# scan => 1,
       call => \&preprocess_add_waypoint);
  hook(type => "preprocess", id => "mapper_ref_waypoint",# scan => 1,
       call => \&preprocess_ref_waypoint);
  hook(type => "preprocess", id => "mapper_defaults",# scan => 1,
       call => \&preprocess_defaults);
  hook(type => "pagetemplate", id => "mapper", call => \&pagetemplate);
}

# ------------------------------------------------------------
use constant DEFAULT_ENDPOINT => 'http://overpass-api.de/api/interpreter';
use constant DEFAULT_MAXWP => 1000;

sub _geterror($@) {
  my $string = shift;
  return error(sprintf(gettext($string), @_));
}

# ------------------------------------------------------------

sub getsetup () {
  return (
    plugin => {
      safe => 1,
      rebuild => 1,
    },
  );
}

sub checkconfig () {
  eval { use JSON; };
  error ('automap: Failed to load the JSON library.') if $@;
  eval { use IkiWiki::Plugin::stdata; };
  error ('automap: Failed to load the stdata plugin.') if $@;
}

sub scan (@) {
}

our %layers;

sub preprocess_new_layer (@) {
  my %params = @_;
  my $page = delete $params{page};
  my $destpage = delete $params{destpage};
  my $preview = delete $params{preview};

  my ($name, $description, $type);

  unless ((delete $params{name}) =~ /^(\w+)$/) {
    _geterror('mapper_new_layer: Missing or invalid layer name.');
  }
  $name = $1;  # Untaint.
  $description = delete $params{description} || $name;
  $type = lc(delete $params{type} || 'empty');
  my %layer_params = (
    name => $name,
    description => $description,
    type => $type,
  );
  if ($type eq 'empty') {
    # pass.
  } elsif ($type eq 'osm') {
    $layer_params{endpoint} = delete $params{endpoint} || DEFAULT_ENDPOINT;
    $layer_params{max_wp} = delete $params{max_wp} || DEFAULT_MAXWP;
    $layer_params{query} = delete $params{query};
    unless ($layer_params{query}) {
      _geterror('mapper_new_layer: Missing query parameter.');
    }
  } elsif ($type eq 'orphans') {
    $layer_params{from_layer} = delete $params{from_layer};
    unless ($layer_params{from_layer}) {
      _geterror('mapper_new_layer: Missing from_layer parameter.');
    }
    unless (exists $pagestate{$page}{mapper}{layer}{$layer_params{from_layer}})
    {
      _geterror('mapper_new_layer: Referenced layer does not exist: %s',
        $layer_params{from_layer});
    }
  } else {
    _geterror('mapper_new_layer: Invalid layer type: %s.', $page);
  }
  if (%params) {
    _geterror('mapper_new_layer: Unknown parameters: %s.',
      join(', ', keys(%params)));
  }

  my $layerpage = "$page/$name";
  my $jsonfile = "$layerpage.json";
  will_render($page, $jsonfile);

  return '' unless ($page eq $destpage);

  unless (defined wantarray) {
    # Scan phase: create layer and exit.
    if (exists $layers{$layerpage}) {
      return '';
    }
    $layers{$layerpage} = {
      waypoints => {},
      parameters => \%layer_params,
    };
    return '';
  }
  if (exists $pagestate{$page}{mapper}{layer}{$name}) {
    _geterror('mapper_new_layer: Duplicate layer name.');
  }
  $pagestate{$page}{mapper}{layer}{$name} = $layers{$layerpage};
  return '';
}

sub preprocess_add_waypoint (@) {
}

sub preprocess_ref_waypoint (@) {
}

sub preprocess_defaults (@) {
}

sub pagetemplate (@) {
}

1;
