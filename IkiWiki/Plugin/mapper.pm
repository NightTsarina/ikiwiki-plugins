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

our $VERSION = "0.1";

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
use Fcntl qw(:flock);

sub import {
  hook(type => "getopt", id => "mapper", call => \&getopt);
  hook(type => "getsetup", id => "mapper", call => \&getsetup);
  hook(type => "checkconfig", id => "mapper", call => \&checkconfig);
  hook(type => "scan", id => "mapper", call => \&scan);
  hook(type => "preprocess", id => "mapper_layer", scan => 1,
       call => \&preprocess_layer);
  hook(type => "preprocess", id => "mapper_add_waypoint",
       call => \&preprocess_add_waypoint);
  hook(type => "preprocess", id => "mapper_ref_waypoint",
       call => \&preprocess_ref_waypoint);
  hook(type => "preprocess", id => "mapper_defaults",# scan => 1,
       call => \&preprocess_defaults);
  hook(type => "pagetemplate", id => "mapper", call => \&pagetemplate);
}

# ------------------------------------------------------------
use constant DEFAULT_ENDPOINT => "http://overpass-api.de/api/interpreter";
use constant DEFAULT_MAXWP => 1000;
use constant DEFAULT_REFRESH => 3600 * 6;

sub sgettext ($@) {
  my $string = shift;
  return sprintf(gettext($string), @_);
}

sub getdebug ($@) {
  my $string = shift;
  debug(sgettext($string, @_));
}

sub geterror ($@) {
  my $string = shift;
  error(sgettext($string, @_));
}

my $lockfh;
sub lock_mapper () {
  mkdir($config{wikistatedir}) unless (-d $config{wikistatedir});
  open($lockfh, ">", $config{wikistatedir} . "/mapper.lock")
    or die("Cannot create mapper lock file: $!");
  unless (flock($lockfh, LOCK_EX | LOCK_NB)) {
    close($lockfh);
    return 0;
  }
  return 1;
}

sub unlock_mapper () {
  close($lockfh);
}

# ------------------------------------------------------------

sub getopt() {
  eval { use Getopt::Long; };
  geterror("mapper: Failed to load the Getopt::Long library.") if $@;
  Getopt::Long::Configure("pass_through");
  GetOptions(
    "update-maps:s" => \$config{update_maps},
  );
}

sub getsetup() {
  return (
    plugin => {
      safe => 1,
      rebuild => 1,
    },
    mapper_config_pages => {
      type => "string",
      description => "PageSpec for pages that can use privileged commands.",
      example => "_mapper",
      safe => 0,
      rebuild => 1,
    },

  );
}

sub checkconfig () {
  eval { use JSON; };
  geterror("mapper: Failed to load the JSON library.") if $@;
  eval { use IkiWiki::Plugin::stdata; };
  geterror("mapper: Failed to load the stdata plugin.") if $@;
  if (not defined $config{mapper_config_pages}) {
    $config{mapper_config_pages} = "_mapper";
  }

  # Mechanism taken from the aggregate plugin.
  if (defined $config{update_maps} and not (
      $config{post_commit} and IkiWiki::commit_hook_enabled())) {
    update_maps();
  }
}

sub scan (@) {
}

our %layers;

sub preprocess_layer (@) {
  my %params = @_;
  my $page = delete $params{page};
  my $destpage = delete $params{destpage};
  my $preview = delete $params{preview};

  my ($description, $type);

  my $match = pagespec_match($page, $config{mapper_config_pages});
  unless ($match) {
    geterror("mapper_layer: " .
      "Not allowed by mapper_config_pages parameter: %s.", $match);
  }
  $description = delete $params{description} || $page;
  $type = lc(delete $params{type} || "empty");
  my %layer_params = (
    description => $description,
    type => $type,
  );
  if ($type eq "empty") {
    # pass.
  } elsif ($type eq "osm") {
    $layer_params{endpoint} = delete $params{endpoint} || DEFAULT_ENDPOINT;
    $layer_params{max_wp} = delete $params{max_wp} || DEFAULT_MAXWP;
    $layer_params{refresh} = delete $params{refresh} || DEFAULT_REFRESH;
    $layer_params{query} = delete $params{query};
    $layer_params{include_orphans} = delete $params{include_orphans};
    unless ($layer_params{query}) {
      geterror("mapper_layer: Missing query parameter.");
    }
    unless ($layer_params{refresh} =~ /^\d+$/) {
      geterror("mapper_layer: Invalid refresh value: %s.",
        $layer_params{refresh});
    }
  } elsif ($type eq "orphans") {
    $layer_params{from_layer} = delete $params{from_layer};
    unless ($layer_params{from_layer}) {
      geterror("mapper_layer: Missing from_layer parameter.");
    }
    unless (exists $pagestate{$layer_params{from_layer}}{mapper}{layer}) {
      geterror("mapper_layer: Referenced layer does not exist: %s",
        $layer_params{from_layer});
    }
  } else {
    geterror("mapper_layer: Invalid layer type: %s.", $page);
  }
  if (%params) {
    geterror("mapper_layer: Unknown parameters: %s.",
      join(", ", keys(%params)));
  }

  my $jsonfile = "$page.json";
  will_render($page, $jsonfile);

  return "" unless ($page eq $destpage);

  unless (defined wantarray) {
    # Scan phase: create layer and exit.
    if (exists $layers{$page}) {
      return "";
    }
    $layers{$page} = \%layer_params;
    return "";
  }
  if (exists $pagestate{$page}{mapper}{layer}
      and $pagestate{$page}{mapper}{layer}) {
    geterror("mapper_layer: Duplicate layer.");
  }
  $pagestate{$page}{mapper}{layer} = $layers{$page};
  # Don't overwrite if already present.
  $wikistate{mapper}{layers}{$page} ||= {
    parameters => $layers{$page},  # Keep a copy to compare later.
    state => { last_updated => -1, last_error => undef },
    waypoints => {},
  };
  return "";
  # FIXME: crear json a partir de todos los waypoints.
}

sub preprocess_add_waypoint (@) {
}

sub preprocess_ref_waypoint (@) {
}

sub preprocess_defaults (@) {
  my %params = @_;
  my $page = delete $params{page};
  my $destpage = delete $params{destpage};
  my $preview = delete $params{preview};

  my $match = pagespec_match($page, $config{mapper_config_pages});
  unless ($match) {
    geterror("mapper_defaults: " .
      "Not allowed by mapper_config_pages parameter: %s.", $match);
  }
  # FIXME.
}

sub pagetemplate (@) {
}

sub update_maps () {
  eval { use LWP::UserAgent; };
  geterror("mapper: Failed to load the LWP::UserAgent library.") if $@;
  eval { use HTTP::Request; };
  geterror("mapper: Failed to load the HTTP::Request library.") if $@;
  eval { use URI::Escape; };
  geterror("mapper: Failed to load the URI::Escape library.") if $@;

  unless (lock_mapper()) {
    geterror("update_maps: Another process is running, aborting...");
  }
  my $force = ($config{update_maps} and $config{update_maps} eq "force");

  IkiWiki::loadindex();
  my %newlayers;
  foreach my $page (keys $wikistate{mapper}{layers}) {
    if (not exists $pagestate{$page}
        or not exists $pagestate{$page}{mapper}
        or not exists $pagestate{$page}{mapper}{layer}
        or not $pagestate{$page}{mapper}{layer}) {
      next;
    }
    my $params = $pagestate{$page}{mapper}{layer};
    my $state = $wikistate{mapper}{layers}{$page}{state};

    my $now = time();
    next if ($params->{type} ne "osm");

    my $oldparams = $wikistate{mapper}{layers}{$page}{parameters};
    if ($oldparams->{query} ne $params->{query}
        or $oldparams->{endpoint} ne $params->{endpoint}
        or $oldparams->{max_wp} ne $params->{max_wp}) {
      # Critical parameters have changed since last update, force download.
      $state->{last_updated} = -1;
    }
    if ($now < $state->{last_updated} + $params->{refresh} and not $force) {
      next;
    }

    getdebug("mapper: Updating layer %s...", $page);
    my $result = get_osm_layer($page, $params);
    $newlayers{$page} = {
      state => { last_updated => $now, last_error => undef },
      # We save the parameters that were used to retrieve the data.
      parameters => $params,
    };

    if (ref $result) {
      $newlayers{$page}{waypoints} = $result;
      getdebug("mapper: Read %d waypoints.", scalar(@$result));
    } else {
      # Keep the old data anyway.
      $newlayers{$page}{waypoints} = $state->{waypoints};
      $newlayers{$page}{state}{last_error} = $result;
      getdebug("mapper: Error downloading map data for layer %s: %s.",
        $page, $result);
    }
  }
  IkiWiki::lockwiki();
  IkiWiki::loadindex();
  # Now we can also clean up, since we have a lock.
  # We need to be careful in case the wiki was edited during the update.
  my @pages = keys $wikistate{mapper}{layers};
  foreach my $page (@pages) {
    if (not exists $pagestate{$page}
        or not exists $pagestate{$page}{mapper}
        or not exists $pagestate{$page}{mapper}{layer}
        or not $pagestate{$page}{mapper}{layer}) {
      # Remove stale data.
      delete $wikistate{mapper}{layers}{$page};
    }
    if ($newlayers{$page}) {
      $wikistate{mapper}{layers}{$page} = $newlayers{$page};
      $IkiWiki::forcerebuild{$page} = 1;
    }
  }
  IkiWiki::saveindex();
  IkiWiki::unlockwiki();
  unlock_mapper();
  return 1;
}

sub get_osm_layer ($$) {
  my $page = shift;
  my $params = shift;
  my $options = "[out:json];";
  my $output = "out $params->{max_wp};";

  my $request = HTTP::Request->new(POST => $params->{endpoint});
  $request->content_type("application/x-www-form-urlencoded");
  $request->content("data=" .
    uri_escape($options . $params->{query} . $output));

  my $ua = LWP::UserAgent->new;
  my $response = $ua->request($request);

  unless ($response->is_success) {
    return $response->status_line;
  }
  my $jsondata = eval { decode_json($response->content); };
  if ($@) {
    return sgettext("Error parsing JSON data: %s", $@);
  }
  unless (ref $jsondata and ref $jsondata eq 'HASH'
      and $jsondata->{elements} and ref $jsondata->{elements} eq 'ARRAY') {
    return sgettext("Invalid JSON data from endpoint");
  }
  my $waypoints = $jsondata->{elements};
  return $waypoints;
}

1;
