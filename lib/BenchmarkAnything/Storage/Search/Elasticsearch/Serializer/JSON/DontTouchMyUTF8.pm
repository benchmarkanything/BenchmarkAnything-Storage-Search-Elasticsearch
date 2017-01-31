package BenchmarkAnything::Storage::Search::Elasticsearch::Serializer::JSON::DontTouchMyUTF8;
# ABSTRACT: Pass through known-utf8 data untouched to Elasticsearch.

# As seen in
#   https://github.com/elastic/elasticsearch-perl/issues/57
# (Kudos to Celogeek - you are not alone!)

=head2 JSON

The JSON instance which does not contain special utf-8 fiddling.

=cut

use Moo;
use JSON::MaybeXS 1.002002 ();

has 'JSON' => ( is => 'ro', default => sub { JSON::MaybeXS->new } );

with 'Search::Elasticsearch::Role::Serializer::JSON';
use namespace::clean;

1;
