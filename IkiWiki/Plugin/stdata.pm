#!/usr/bin/perl
# vim:ts=2:sw=2:et:ai:sts=2:cinoptions=(0
package IkiWiki::Plugin::stdata;

use warnings;
use strict;

=head1 NAME

IkiWiki::Plugin::stdata - Add structured data to a page.

=head1 VERSION

This describes version B<0.1> of IkiWiki::Plugin::stdata

=cut

our $VERSION = '0.1';

=head1 DESCRIPTION

This allows structured data to be defined in YAML format on a separate source
file.

See doc/plugins/contrib/stdata and ikiwiki/directive/stdata for docs.

=head1 PREREQUISITES

    IkiWiki
    YAML::Any

=head1 AUTHOR

    Martín Ferrari (TINCHO)

=head1 COPYRIGHT

Copyright (c) 2013 Martín Ferrari

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

sub import {
  hook(type => 'getsetup', id => 'stdata', call => \&getsetup);
  hook(type => 'checkconfig', id => 'stdata', call => \&checkconfig);
  hook(type => 'preprocess', id => 'stdata', call => \&preprocess,
       scan => 1);
  hook(type => 'preprocess', id => 'getstdata', call => \&getstdata);
  hook(type => 'pagetemplate', id => 'stdata', call => \&pagetemplate);
}

# ------------------------------------------------------------
# Hooks
# --------------------------------
sub getsetup () {
  return (
    plugin => {
      safe => 1,
      rebuild => 1,
    },
    stdata_inject_meta => {
      type => 'boolean',
      description => 'Feed some of the structured data into the meta plugin.',
      safe => 0,
      rebuild => 1,
    },
  );
}

sub checkconfig () {
  eval {
    use YAML::Any;
  };
  error ('stdata: Failed to load the YAML library.') if $@;
  $YAML::UseBlock = 1;
}

sub preprocess (@) {
  my %params = @_;
  my $datapage = exists($params{datapage}) ? $params{datapage} : $_[0];
  my $page = $params{page};
  my $prefix = $params{prefix} || '';

  if (not defined wantarray) {
    $pagestate{$page}{stdata} = {};
    if (not $datapage) {
      $pagestate{$page}{stdata}{__error} = gettext(
        'stdata: Missing data page name.');
      return;
    }
    debug('stdata: including ' . $datapage);
    my @sources = pagespec_match_list($page, $datapage, num => 1);
    my $source = @sources ? srcfile($sources[0], 1) : undef;
    if (not $source) {
      if (not exists $params{ignore_missing}) {
        $pagestate{$page}{stdata}{__error} = gettext(
          'stdata: Can\'t find data page name: ') . $datapage;
      }
      return;
    }
    my $stdata;
    eval {
      my ($file, $datatext);
      open $file, '<:encoding(UTF-8)', $source or die $!;
      $stdata = Load(join('', <$file>));
      close $file;
    };
    if ($@) {
      $pagestate{$page}{stdata}{__error} = sprintf(
        gettext('stdata: Error reading YAML data: %s'), "$@");
      return;
    }
    if (not defined $stdata or not ref $stdata or not ref $stdata eq 'HASH') {
      $pagestate{$page}{stdata}{__error} = gettext(
        'stdata: Invalid YAML data.');
      return;
    }
    foreach my $key (keys %{$stdata}) {
      $pagestate{$page}{stdata}{$prefix . $key} = $stdata->{$key};
    }
  } else {
    if ($pagestate{$page}{stdata}{__error}) {
      my $error = delete($pagestate{$page}{stdata}{__error});
      error($error);
    }
  }
  if ($config{stdata_inject_meta} and $pagestate{$page}{stdata}) {
    process_meta($page, $params{destpage}, defined wantarray);
  }
  return '';
}

sub getstdata (@) {
  return if (not defined wantarray);
  my %params = @_;
  my $name = exists($params{name}) ? $params{name} : $_[0];
  my $page = $params{page};

  if (exists($pagestate{$page}{stdata}{$name})) {
    return $pagestate{$page}{stdata}{$name};
  }
  return '';
}
 
sub pagetemplate (@) {
  my %params = @_;
  my $page = $params{page};
  my $template = $params{template};

  if (exists $pagestate{$page}{stdata} and
      ref $pagestate{$page}{stdata} and %{$pagestate{$page}{stdata}}) {
    while (my ($key, $value) = each %{$pagestate{$page}{stdata}}) {
      $template->param('stdata_' . $key, $value);
    }
  }
}

# --------------------------------

our @META_FIELDS = qw(title description guid license copyright enclosure
                      author authorurl permalink date updated foaf name
                      keywords robots);

sub process_meta ($$$) {
  my $page = shift;
  my $destpage = shift;
  my $wantarray = shift;
  my $stdata = $pagestate{$page}{stdata};

  foreach my $key (@META_FIELDS) {
    if (exists $stdata->{$key}) {
      my @params = ($key => $stdata->{$key});
      if ($key eq 'title' or $key eq 'author' and
        exists $stdata->{$key . 'sort'}) {
        push @params, sortas => $stdata->{${key} . 'sort'};
      }
      push @params, page => $page;
      push @params, destpage => $destpage if($destpage);
      if ($wantarray) {
        my @a = IkiWiki::Plugin::meta::preprocess(@params);
      } else {
        IkiWiki::Plugin::meta::preprocess(@params);
      }
    }
  }
}
1;
