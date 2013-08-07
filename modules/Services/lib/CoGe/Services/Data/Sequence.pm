package CoGe::Services::Data::Sequence;
use base 'CGI::Application';

use CoGeX;
use CoGe::Accessory::Web qw( init );
use CoGe::Accessory::Storage qw( get_genome_seq );
use JSON qq{encode_json};
use Data::Dumper;

sub setup {
    my $self = shift;
    $self->run_modes( 'get' => 'get' );
    $self->mode_param('rm');
}

sub get {
    my $self = shift;
    my $gid  = $self->param('gid');
    return unless $gid;
    my $chr   = $self->param('chr');
    my $start = $self->query->param('start');
    my $stop  = $self->query->param('stop');
    $stop = $self->query->param('end') if ( not defined $stop );
    my $strand = $self->query->param('strand');
    print STDERR "Sequence::get gid=$gid chr=$chr start=$start stop=$stop\n";

    # Connect to the database
    my ( $db, $user, $conf ) = CoGe::Accessory::Web->init();
    print STDERR "matt: " . $user->name . "\n";

    # Retrieve genome
    my $genome = $db->resultset('Genome')->find($gid);
    return unless $genome;

    # Check permissions
    if ( $genome->restricted
        and ( not defined $user or not $user->has_access_to_genome($genome) ) )
    {
        print STDERR "Sequence::get access denied to genome $gid\n";
        return;
    }

    # Force browser to download as attachment
    if ( not defined $chr or $chr eq '' ) {
        $self->header_add( -attachment => "genome_$gid.faa" );
    }

    # Get sequence from file
    return get_genome_seq(
        gid   => $gid,
        chr   => $chr,
        start => $start,
        stop  => $stop
    );
}

1;
