package B::Source;
use strict;
use base 'Exporter';
use List::Util qw(max min);
use B qw(svref_2object main_root class);
use vars qw($VERSION @EXPORT);

$VERSION = 0.01;
@EXPORT = 'index_source';

sub index_source {
    return __PACKAGE__->new->index->read_source;
}

sub B::OP::line_numbers {
    my $op   = shift;
    my $self = shift;
    
    my $line = $op->can('line') ? $op->line : undef;
    my $file = $op->can('file') ? $op->file : undef;
    
    if ( defined $line and defined $file ) {
	$self->{'source'}{$file}{$line} = undef;
    }
    
    my $kid;
    if ( $op->can('first') ) {
	$kid = $op->first;
    } else {
	return;
    }
    
    do {
	$kid->line_numbers( $self )
	    if $kid->can('line_numbers');
    } while ( $kid->can('sibling') and
	      $kid = $kid->sibling and
	      $$kid );
}

BEGIN {
    for ( qw(LIST
	     SV
	     PAD
	     PV
	     LOOP
	     COP
	     LOGOP) ) {
	no strict 'refs';
	*{"B::" . $_ . "OP::line_numbers"} = \&B::OP::line_numbers;
    }
}

sub new {
    my $class = shift;
    my $self  = bless { @_ }, $class;

    $self->{'root'} ||=
	( eval { $self->{'sub'}->ROOT }
	  || main_root );
    if ( $self->{'sub'} ) {
	$self->{'subname'} = subname( $self->{'sub'} );
    }
    
    $self->read_source;
    
    return $self;
}

sub source {
    my $self = shift;
    return $self->{'source'};
}

sub index {
    my $self = shift;

    return if $self->{'indexed'};
    
    # main_root
    $self->index_sub;

    $self->index_sub( $_ ) for
	( grep $_,
	  eval { B::begin_av->ARRAY },
	  eval { B::check_av->ARRAY },
	  eval { B::init_av->ARRAY },
	  eval { B::end_av->ARRAY },
	  $self->find_stash_subs );
    
    $self->{'indexed'} = 1;

    return $self;
}

sub index_sub {
    my $self = shift;
    my $sub = shift;

    my $op =
	eval { $sub->ROOT } || main_root;
    $self->{'subname'} =
	eval { subname( $sub ) } || '<main>';
    
    eval { $op->line_numbers( $self ) };
    
    return $self;
}

sub read_source {
    my $self = shift;
    
    for my $file ( keys %{$self->{'source'}} ) {
	next unless -e $file;
	my @source = do { local @ARGV = $file;
			  local $/ = "\n";
			  <> };
	my @index =
	    sort( { $a <=> $b }
		  keys( %{$self->{'source'}{$file}} ) );
	my $prev_ix = 1;
	
	for my $ix ( @index ) {
 	    $self->{'source'}{$file}{$prev_ix} =
		join '',
		delete
		@source[ ($prev_ix - 1) .. ($ix - 2) ];
	    $prev_ix = $ix;
	}
	
 	my $minline = min( keys %{$self->{'source'}{$file}} );
 	$self->{'source'}{$file}{$minline} =
 	    join( '',
		  grep defined(),
		  delete @source[ 0 .. $minline - 1] )
	    . $self->{'source'}{$file}{$minline};
 	my $maxline = max( keys %{$self->{'source'}{$file}} );
 	$self->{'source'}{$file}{$maxline} .=
 	    join '',
 	    grep defined(),
 	    delete
 	    @source[ $maxline - 1.. $#source ];
	
 	if ( @source ) {
 	    warn "Source for $file wasn't assigned to any optrees: " . join('',grep defined(),@source) . ".";
 	}
    }
    return $self->{'source'};
}

sub subname {
    my $op = shift;
    my $stash = eval { $op->STASH->NAME . '::' } || '';
    my $gv = eval { $op->GV->NAME };
    
    return if not defined $gv;
    return $stash . $gv;
}

sub find_stash_subs {
    # Stolen from B::Deparse from perl 5.8.2 and hacked up
    my ($self,$pack) = @_;
    my (@ret, $stash);

    my @subs;
    
    if (!defined $pack) {
	$pack = '';
	$stash = \%::;
    } else {
	$pack =~ s/(::)?$/::/;
	no strict 'refs';
	$stash = \%$pack;
    }
    my %stash = svref_2object($stash)->ARRAY;
    while (my ($key, $val) = each %stash) {
	next if $key eq 'main::';	# avoid infinite recursion
	next unless 'GV' eq class( $val );

	if (class(my $cv = $val->CV) ne "SPECIAL") {
	    next if $self->{'subs_done'}{$$val}++;
	    next if $$val != ${$cv->GV};   # Ignore imposters
	    push @subs, $cv;
	}
	if (class(my $cv = $val->FORM) ne "SPECIAL") {
	    next if $self->{'forms_done'}{$$val}++;
	    next if $$val != ${$cv->GV};   # Ignore imposters
	    push @subs, $cv;
	}
	if (class($val->HV) ne "SPECIAL" && $key =~ /::$/) {
	    push @subs, $self->find_stash_subs($pack . $key);
	}
    }

    return @subs;
}

sub null {
    # Stolen from B::Deparse from perl 5.8.2
    my $op = shift;
    return class($op) eq "NULL";
}

sub is_state {
    # Stolen from B::Deparse from perl 5.8.2
    my $name = $_[0]->name;
    return $name eq "nextstate" || $name eq "dbstate" || $name eq "setstate";
}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

B::Source - Indexes your perl source code by filename and COP

=head1 SYNOPSIS

  use B::Source;
  use Data::Dumper;
  $Data::Dumper::Sortkey = 1;
  print Dumper( index_source->{$0} );

=head1 DESCRIPTION

This module attempts to find all of the subroutines currently in memory and
then index their source code by their COP nodes from their optrees. The idea
is that when given a B::COP object you can now look up its related source
code through its ->line and ->file properties.

This module was written to support B::Deobfuscate and B::ToXML and isn't
something I'd normally consider using directly.

=head1 FUNCTIONS

=over 4

=item index_source

This takes no parameters and returns a hash reference. The keys are your
source file names from the B::COP objects. The values are hashes of line
numbers and source code. A B::COP object's ->file and ->line properties
are keys to the source code.

 { 'foo.pl' => { '1' => 'use strict',
                 '5' => 'print 1' },
   'bar.pm' => { ... }
 }

=back

=head1 AUTHOR

Joshua b. Jore E<lt>jjore@cpan.orgE<gt>

=head1 SEE ALSO

L<perl>, L<B>, L<perlguts>.

=cut
