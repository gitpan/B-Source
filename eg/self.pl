use Data::Dumper;
use B::Source;
$_ = B::Source->new->index->read_source;
$Data::Dumper::Sortkeys = 1;
print Dumper($_->{'source'}{$0} );
