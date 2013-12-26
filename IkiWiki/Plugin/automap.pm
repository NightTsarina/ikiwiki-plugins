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
  hook(type => "preprocess", id => "automapitem", #scan => 1,
       call => \&preprocess_item);
  hook(type => "preprocess", id => "automap",
       call => \&preprocess_map);
  hook(type => "preprocess", id => "automapjson",
       call => \&preprocess_json);
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
  $data_regex = qr(^\Q$base\E/(node|way)_(\d+)._yaml$)o;
}

sub scan (@) {
  my %params = @_;
  my $page = $params{page};
  my $content = $params{content};

  # Continue only for data files.
  return if ($page !~ /$data_regex/ or not $content);
  my ($type, $id) = ($1, $2);

  debug ("automap::scan $page $type/$id");
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
  $pagestate{$page}{automap}{data} = $data;
}

my %preprocessed;

sub preprocess_item (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $preview = $params{preview};

  if (! $preprocessed{$page}) {
    clean_page($page);
    $preprocessed{$page} = 1;
  }
  my $embed = (defined $params{embed} and $params{embed} ne '0');
  my $type = $params{type} || 'node';
  my $id = $params{id};

  if (not $id) {
    error(gettext('automapitem: missing "id" parameter.'));
  }
  if ($type !~ /^(way|node)$/o) {
    error(gettext('automapitem: Invalid map item type: ') . $type);
  }
  if ($id !~ /^\d+$/o) {
    error(gettext('automapitem: Invalid map item id: ') . $id);
  }
  my $datapage = "$config{automap_base}/${type}_${id}._yaml";
  if (not exists $pagestate{$datapage} or
      not exists $pagestate{$datapage}{automap} or
      not exists $pagestate{$datapage}{automap}{data} or
      not $pagestate{$datapage}{automap}{data}) {
    error(sprintf(gettext('automapitem: Map item not found: %s.'),
                  $datapage));
  }
#  debug('automap backlinks ' . join(' ', IkiWiki::backlink_pages($datapage)));
  if (exists $pagestate{$datapage}{automap}{backlink} and
      $pagestate{$datapage}{automap}{backlink} ne $page) {
    error(gettext('automapitem: Duplicate linking to the same map item.'));
  }

  if (not $preview) {
    $pagestate{$datapage}{automap}{backlink} = $page;
    $pagestate{$page}{automap}{mapitems}{$datapage} = undef;
    add_depends($page, "internal($datapage)");
  }

  if ($embed) {
    $pagestate{$page}{automap}{maps} ||= [];
    my $nr = scalar(@{$pagestate{$page}{automap}{maps}});
    push @{$pagestate{$page}{automap}{maps}}, "automap-$nr";
    return "<div id=\"automap-$nr\" class=\"automap\"></div>\n";
  }

  return '';
}

sub preprocess_map (@) {
  my %params = @_;
  my $page = $params{page};

  if (! $preprocessed{$page}) {
    clean_page($page);
    $preprocessed{$page} = 1;
  }
}

sub preprocess_json (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $preview = $params{preview};

  if (! $preprocessed{$page}) {
    clean_page($page);
    $preprocessed{$page} = 1;
  }

  my $layer = $params{layer} || '';
  my $pages = exists $params{pages} ? $params{pages} : 'mapped(*)';
  my $include_orphans = (defined $params{include_orphans} ?
                         ($params{include_orphans} || $config{automap_base}) :
                         undef);
  my $add_to = $params{add_to} || $pages;
  my $default_hidden = $params{default_hidden};

  unless ($layer =~ /^(\w+)$/) {
    error(gettext('automapjson: Missing or invalid layer name.'));
  }
  $layer = $1;  # Untaint.
  if (exists $wikistate{automap}{layers}{$layer} and
      $wikistate{automap}{layers}{$layer} ne $page) {
    error(gettext('automapjson: Duplicate layer name.'));
  }

  return '' unless ($page eq $destpage);

  my $jsonfile = "$page/$layer.json";
  will_render($page, $jsonfile);

  my @mapitems;
  foreach my $target (pagespec_match_list($page, $pages,
                                          sort => 'meta(title)')) {
    next unless(IkiWiki::PageSpec::match_mapped($target, ''));
    my $title;
    if (exists $pagestate{$target} and
      exists $pagestate{$target}{meta}{title}) {
      $title = $pagestate{$target}{meta}{title};
    } else {
      $title = pagetitle(IkiWiki::basename($target));
    }
    foreach my $mapitem (keys %{$pagestate{$target}{automap}{mapitems}}){
      my $mapdata = $pagestate{$mapitem}{automap}{data};
      push @mapitems, item2json({page => $target, mapdata => $mapdata});
    }
  }

  if ($include_orphans) {
    # Any link change.
    #add_depends($page, "*", deptype("links"));
    add_depends($page, "mapped(*)");
    my @orphans = pagespec_match_list(
      $page, "internal($config{automap_base}/*)",
      # update when orphans are added/removed
      deptype => deptype("presence"),
      sort => 'title',
      filter => sub {
        my $target = shift;
        return 1 unless (exists $pagestate{$target}{automap}{data});
        return 0 unless (exists $pagestate{$target}{automap}{backlink});
        my $backlink = $pagestate{$target}{automap}{backlink};
        return 1 unless ($backlink);
        return (exists $pagestate{$backlink} and
                exists $pagestate{$backlink}{automap}{mapitems} and 
                exists $pagestate{$backlink}{automap}{mapitems}{$target});
      },
    );
    foreach my $target (@orphans) {
      my $mapdata = $pagestate{$target}{automap}{data};
      my $title = (exists $mapdata->{name} ?  $mapdata->{name} :
                   $mapdata->{type} . ' ' . $mapdata->{id});
      my $pagename = "$include_orphans/" . titlepage($title);
      $pagename =~ s#/+#/#g;
      push @mapitems, item2json({
          title => $title,
          page => $pagename,
          mapdata => $mapdata,
          create => 1,
        });
    }
  }
  my $json = to_json(\@mapitems);
  writefile($jsonfile, $config{destdir}, $json);

  # Easy way to get all layers.
  $wikistate{automap}{layers}{$layer} = $page;
  $pagestate{$page}{automap}{layer}{$layer} = {
    json => $jsonfile,
    pagespec => $add_to,
    default_hidden => $default_hidden,
  };
  return '';
}

sub clean_page ($) {
  my $page = shift;
  # Clean data for a page that's being rebuilt.
  if (exists $pagestate{$page}{automap}{mapitems} and
      ref $pagestate{$page}{automap}{mapitems}) {
    # Remove links to this page.
    foreach my $item (keys %{$pagestate{$page}{automap}{mapitems}}) {
      if (exists $pagestate{$item}{automap}{backlink} and
          defined $pagestate{$item}{automap}{backlink} and
          $pagestate{$item}{automap}{backlink} eq $page) {
        delete $pagestate{$item}{automap}{backlink};
      }
    }
    debug ("automap::clean_page $page");
    delete $pagestate{$page}{automap};
  }
}

sub item2json ($) {
  my $item = shift;
  my %mapdata = %{$item->{mapdata}};  # Copy.
  my %res;
  $res{page} = $item->{page};
  if (exists $item->{title}) {
    $res{title} = $item->{title};
  } else {
    if (exists $pagestate{$res{page}}{meta}{title}) {
      $res{title} = $pagestate{$res{page}}{meta}{title};
    } else {
      $res{title} = pagetitle(IkiWiki::basename($res{page}));
    }
  }
  # FIXME: description.
  $res{create} = 1 if ($item->{create});

  $res{id} = (delete $mapdata{type}) . '/' . (delete $mapdata{id});
  $res{coord} = [(delete $mapdata{lat}) + 0.0, (delete $mapdata{lon}) + 0.0];
  $res{prop} = \%mapdata;
  return \%res;
}

sub pagetemplate (@) {
  my %params = @_;
  my $page = $params{page};
  my $destpage = $params{destpage};
  my $template = $params{template};

  unless (exists $pagestate{$page}{automap} and
          exists $pagestate{$page}{automap}{maps} and
          ref $pagestate{$page}{automap}{maps}) {
    return;
  }
  my @output = ();
  foreach my $mapitem (keys %{$pagestate{$page}{automap}{mapitems}}) {
    my $mapdata = $pagestate{$mapitem}{automap}{data};
    push (@output, item2json({page => $page, mapdata => $mapdata}));
  }
  my $json = to_json(\@output, {pretty => 1});

  my @layers = ();
  my @layer_names = ();
  foreach my $layer (keys %{$wikistate{automap}{layers}}) {
    my $layerpage = $wikistate{automap}{layers}{$layer};
    if (not exists $pagestate{$layerpage}{automap}{layer} or
        not exists $pagestate{$layerpage}{automap}{layer}{$layer}) {
      next;
    }
    my $layerdata = $pagestate{$layerpage}{automap}{layer}{$layer};
    if (not pagespec_match($page, $layerdata->{pagespec},
                           location => $layerpage)) {
      next;
    }
    push @layers, {
      layer_name => $layer,
      layer_hidden => $layerdata->{default_hidden} ? 'true' : 'false',
      layer_url => urlto($layerdata->{json}, $destpage)};
    push @layer_names, $layer;
  }
  unshift @layer_names, 'this_page';

  my @maps = ();
  foreach my $map (@{$pagestate{$page}{automap}{maps}}) {
    push @maps, {map_div => $map, map_layers_json => to_json(\@layer_names)};
  }

  $template->param('has_map', 1);
  $template->param('automap_items_json', $json);
  $template->param('automap_base', urlto('index', $destpage));
  $template->param('automap_layers', \@layers);
  $template->param('automap_maps', \@maps);
}

package IkiWiki::PageSpec;

sub match_mapped ($$;@) {
  my $page = shift;
  my $glob = shift || '*';
  my $ret = match_glob($page, $glob);
  if (not $ret) {
    return $ret;
  }
  if (exists $IkiWiki::pagestate{$page}{automap} and
      exists $IkiWiki::pagestate{$page}{automap}{mapitems} and
      ref $IkiWiki::pagestate{$page}{automap}{mapitems}) {
    return IkiWiki::SuccessReason->new(
      # Assuming "" means non static, or somesuch, yay for proper docs.
      "$page has map items", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
  }
  return IkiWiki::FailReason->new(
    "$page has no map items", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
#  return match_link($page, $glob, linktype => 'tag', @_);
}

1;
