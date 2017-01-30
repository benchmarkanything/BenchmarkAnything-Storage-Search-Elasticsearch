package BenchmarkAnything::Storage::Search::Elasticsearch;
# ABSTRACT: Utility functions to use Elasticsearch with BenchmarkAnything storage

use 5.008;
use strict;
use warnings;
use Encode 'encode_utf8';

=head2 $object = get_elasticsearch_client (\%opt)

Create end return an L<Elasticsearch client|Search::Elasticsearch>
instance, together with its index and type name from benchmarkanything
config.

Options

=over 4

=item searchengine

The content of the C<searchengine> entry from BenchmarkAnything::Config;

=item ownjson

If set to a true value then the client uses a JSON serializer that
does not try to upgrade/downgrade/encode/decode your already fine
utf-8 data.

=back

=cut

sub get_elasticsearch_client {

    my ( $opt ) = @_;

    require Search::Elasticsearch;

    my $cfg     = $opt->{searchengine};
    my $s_index = $cfg->{elasticsearch}{index};
    my $s_type  = $cfg->{elasticsearch}{type};
    die "benchmarkanything-storage-search-elasticsearch: missing config 'elasticsearch.index'" unless $s_index;
    die "benchmarkanything-storage-search-elasticsearch: missing config 'elasticsearch.type'"  unless $s_type;

    # Elasticsearch
    my $or_es = Search::Elasticsearch->new
     (client => ($cfg->{client} || "5_0::Direct"),
      $opt->{ownjson} ? (serializer => "+BenchmarkAnything::Storage::Search::Elasticsearch::Serializer::JSON::DontTouchMyUTF8") : (),
     );

    return wantarray ? ($or_es, $s_index, $s_type) : $or_es;
}

=head2 \%es_query = get_elasticsearch_query (\%ba_query)

Converts a
L<BenchmarkAnything|BenchmarkAnything::Storage::Backend::SQL> query
into a respective Elasticsearch query.

=cut

sub get_elasticsearch_query
{

    my ( $hr_ba_query ) = @_;

    my $hr_es_query;
    my $default_max_size = 10_000;

    my $ar_ba_select   = $hr_ba_query->{select};   # !, aggregators!
    my $ar_ba_where    = $hr_ba_query->{where};    # done; wildcards to entries with 'foo:', maybe fixed with analyzer settings
    my $i_ba_limit     = $hr_ba_query->{limit};    # done
    my $i_ba_offset    = $hr_ba_query->{offset};   # done
    my $ar_ba_order_by = $hr_ba_query->{order_by}; # done

    my @must_ranges;
    my @must_matches;
    my @must_not_matches;
    my @should_matches;

    # The 'sort' entry should get an always-the-same canonical
    # structure because get_mapping/properties below relies on that.
    my %sort =
     !$ar_ba_order_by
      ? ( sort => [ { VALUE_ID => { order => "asc" }} ] ) # default
      : ( sort => [ map { my @e = ();
                          # No error handling for bogus input here, hm...
                          if (ref and ref eq 'ARRAY')
                          {
                              my $k         =    $_->[0];
                              my $direction = lc($_->[1]) || 'asc';
                              my $options   =    $_->[2]; # (eg. numeric=>1) - IGNORED! We let Elasticsearch figure out.
                              @e = ({ $k => { order => $direction } });
                          }
                          elsif (defined($_)) # STRING
                          {
                              @e = ({ $_ => { order => "asc" } });
                          }
                          else
                          {
                              require Data::Dumper;
                              print STDERR "_get_elasticsearch_query: unknown order_by clause: ".Data::Dumper::Dumper($_)."\n";
                              return;
                          }
                          @e
                      } @{ $ar_ba_order_by || [] }
                  ]);
    my %from = !$i_ba_offset ? () : ( from => $i_ba_offset+1 );
    my %size = ( size => ($i_ba_limit || $default_max_size) );

    my %range_operator =
     (
      '<'  => 'lt',
      '>'  => 'gt',
      '<=' => 'lte',
      '>=' => 'gte',
     );
    my %match_operator =
     (
      '='  => 1,
     );
    my %not_match_operator =
     (
      '!=' => 1,
     );
    my %wildcard_match_operator =
     (
      'like' => 1,
     );
    my %wildcard_not_match_operator =
     (
      'not like' => 1,
     );
    foreach my $w (@{ $ar_ba_where || [] })
    {
        my $op = $w->[0];       # operator
        my $k  = $w->[1];       # key
        my @v  = map { encode_utf8($_) } @$w[2..@$w-1]; # value(s)

        my $es_op;
        if ($es_op = $range_operator{$op})
        {
            push @must_ranges,        { range => { $k => { $es_op => $v[0] } } };
        }
        elsif ($es_op = $match_operator{$op})
        {
            if (@v > 1) {
                push @should_matches, { match => { $k => $_ } } foreach @v;
            } else {
                push @must_matches,   { match => { $k => $v[0] } };
            }
        }
        elsif ($es_op = $not_match_operator{$op})
        {
            push @must_not_matches,   { match => { $k => $_ } } foreach @v;
        }
        elsif ($es_op = $wildcard_match_operator{$op})
        {
            my $es_v = $v[0];
            $es_v =~ s/%/*/g;
            push @must_matches,       { wildcard => { $k => $es_v } };
        }
        elsif ($es_op = $wildcard_not_match_operator{$op})
        {
            my $es_v = $v[0];
            $es_v =~ s/%/*/g;
            push @must_not_matches,   { wildcard => { $k => $es_v } };
        }
        else
        {
            print STDERR "_get_elasticsearch_query: Unsupported operator: $op\n";
            return;
        }
    }

    $hr_es_query = { query => { bool => {
                                         (@must_matches||@must_ranges ? (must     => [ @must_ranges, @must_matches ]) : ()),
                                         (@must_not_matches           ? (must_not => [ @must_not_matches ]) : ()),
                                         (@should_matches             ? (should   => [ @should_matches ],minimum_should_match => 1) : ()),
                                        },
                              },
                     %from,
                     %size,
                     %sort,
                   };

    return $hr_es_query;
}

1;
