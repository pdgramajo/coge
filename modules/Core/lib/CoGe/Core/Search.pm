package CoGe::Core::Search;

use strict;
use warnings;

use List::Compare;
use CoGeX;
use CoGeX::Result::User;
use CoGeDBI;
use Data::Dumper;
use JSON qw(encode_json);

BEGIN {
    our ( @EXPORT, @ISA, $VERSION );
    require Exporter;

    $VERSION = 0.1;
    @ISA = qw( Exporter );
    @EXPORT = qw( search );
}

sub search {
	shift @_;
	my %opts = @_;
    my $search_term = $opts{search_term};	# Takes in the entire string, to be processed later
    #my $timestamp   = $opts{timestamp};
	my $db 			= $opts{db};
	my $USER		= $opts{USER};
	say STDERR "$db";

    my @searchArray = split( ' ', $search_term );
    my @specialTerms;
    my @idList;
    my @results;

    #return unless $search_term;

    #Set up the necessary arrays of serch terms and special conditions
    for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
        if ( index( $searchArray[$i], "::" ) == -1 ) {
            if ( index( $searchArray[$i], '!' ) == -1 ) {
                $searchArray[$i] = { 'like', '%' . $searchArray[$i] . '%' };
            } else {
            	my $bang_index = index($searchArray[$i], '!');
            	my $new_term = substr($searchArray[$i], 0, $bang_index) . substr($searchArray[$i], $bang_index + 1);
            	$searchArray[$i] = { 'not_like', '%' . $new_term . '%' };
            	#print STDERR Dumper($searchArray[$i]);
            }
        }
        else {
            my @splitTerm = split( '::', $searchArray[$i] );
            splice( @searchArray, $i, 1 );
            $i--;
            push @specialTerms, { 'tag' => $splitTerm[0], 'term' => $splitTerm[1] };
        }
    }

	#print STDERR Dumper(\@searchArray);

	#Set the special conditions
	my $type = "none";    #Specifies a particular field to show
	my @restricted =
	  [ -or => [ restricted => 0, restricted => 1 ] ]; 
	  #Specifies either restricted(1) OR unrestriced(0) results. Default is all.
	my @deleted =
	  [ -or => [ deleted => 0, deleted => 1 ] ]; 
	  #Specifies either deleted(1) OR non-deleted(0) results. Default is all.
	for ( my $i = 0 ; $i < @specialTerms ; $i++ ) {
		if ( $specialTerms[$i]{tag} eq 'type' ) {
			$type = $specialTerms[$i]{term};
		}
		if ( $specialTerms[$i]{tag} eq 'restricted' ) {
			@restricted = [ restricted => $specialTerms[$i]{term} ];
			if ( $type eq "none" ) {
				$type = 'restricted'; 
				#Sets the "type" so that only fields relevant to restriction are shown. (i.e. there are no restricted users.)
			}
		}
		if (
			$specialTerms[$i]{tag} eq 'deleted'
			&& (   $specialTerms[$i]{term} eq '0'
				|| $specialTerms[$i]{term} eq '1' )
		  )
		{
			@deleted = [ deleted => $specialTerms[$i]{term} ];
			if ( $type eq "none" ) {
				$type = 'deleted'; 
				#Sets the "type" so that only fields relevant to deletion are shown. (i.e. there are no deleted users).
			}
		}
	}

    # Perform organism search
    if (   $type eq 'none'
        || $type eq 'organism'
        || $type eq 'genome'
        || $type eq 'restricted'
        || $type eq 'deleted' )
    {
        my @orgArray;
        for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
            my $and_or;
            if ($searchArray[$i]{"not_like"}) {
                $and_or = "-and";
			} else {
				$and_or = "-or";
			}
			push @orgArray,
			  [
				$and_or => [
					name        => $searchArray[$i],
					description => $searchArray[$i],
					organism_id => $searchArray[$i]
				]
			  ];
		}
		my @organisms =
		  $db->resultset("Organism")->search( { -and => [ @orgArray, ], } );

		if ( $type eq 'none' || $type eq 'organism' ) {
			foreach ( sort { $a->name cmp $b->name } @organisms ) {
				push @results,
				  { 'type' => "organism", 'label' => $_->name, 'id' => $_->id, 'description' => $_->description };
			}
		}
		@idList = map { $_->id } @organisms;
	}
	
	#print STDERR "organism done\n";

	# Perform user search
	if ( $type eq 'none' || $type eq 'user' ) {
		my @usrArray;
		for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
			my $and_or;
            if ($searchArray[$i]{"not_like"}) {
                $and_or = "-and";
            } else {
                $and_or = "-or";
            }
			push @usrArray,
			  [
				$and_or => [
					user_name  => $searchArray[$i],
					first_name => $searchArray[$i],
					user_id    => $searchArray[$i],
					last_name => $searchArray[$i]
				]
			  ];
		}
		my @users =
		  $db->resultset("User")->search( { -and => [ @usrArray, ], } );

		foreach ( sort { $a->user_name cmp $b->user_name } @users ) {
			push @results,
			  { 'type' => "user", 'first' => $_->first_name, 'last' => $_->last_name, 'username' => $_->user_name, 'id' => $_->id, 'email' => $_->email };
		}
	}
	
	#print STDERR "user done\n";

	# Perform genome search (corresponding to Organism results)
	if (   $type eq 'none'
		|| $type eq 'genome'
		|| $type eq 'restricted'
		|| $type eq 'deleted' )
	{
		my @genomes = $db->resultset("Genome")->search(
			{
				-and => [
					organism_id => { -in => \@idList },
					@restricted,
					@deleted,
				],
			}
		);

		foreach ( sort { $a->id cmp $b->id } @genomes ) {
			if ($USER->has_access_to_genome($_)) {
				push @results,
				  {
					'type'          => "genome",
					'label'         => $_->info,
					'id'            => $_->id,
					'deleted'       => $_->deleted,
					'restricted'    => $_->restricted
				  };
			}
		}

		# Perform direct genome search (by genome ID)
		my @genIDArray;
		for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
			push @genIDArray, [ -or => [ genome_id => $searchArray[$i] ] ];
		}
		my @genomeIDs =
		  $db->resultset("Genome")
		  ->search( { -and => [ @genIDArray, @restricted, @deleted, ], } );

		foreach ( sort { $a->id cmp $b->id } @genomeIDs ) {
			if ($USER->has_access_to_genome($_)) {
				push @results,
				  {
					'type'          => "genome",
					'label'         => $_->info,
					'id'            => $_->id,
					'deleted'       => $_->deleted,
					'restricted'    => $_->restricted
				  };
			}
		}
	}
	
	#print STDERR "genome done\n";

	# Perform experiment search
	if (   $type eq 'none'
		|| $type eq 'experiment'
		|| $type eq 'restricted'
		|| $type eq 'deleted' )
	{
		my @expArray;
		for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
			my $and_or;
            if ($searchArray[$i]{"not_like"}) {
                $and_or = "-and";
            } else {
                $and_or = "-or";
            }
			push @expArray,
			  [
				$and_or => [
					name          => $searchArray[$i],
					description   => $searchArray[$i],
					experiment_id => $searchArray[$i]
				]
			  ];
		}
		my @experiments =
		  $db->resultset("Experiment")
		  ->search( { -and => [ @expArray, @restricted, @deleted, ], } );

		foreach ( sort { $a->name cmp $b->name } @experiments ) {
			if ($USER->has_access_to_experiment($_)) {
				push @results,
				  {
					'type'          => "experiment",
					'label'         => $_->name,
					'id'            => $_->id,
					'deleted'       => $_->deleted,
					'restricted'    => $_->restricted
				  };
			}
		}
	}

    #print STDERR "experiment done\n";

	# Perform notebook search
	if (   $type eq 'none'
		|| $type eq 'notebook'
		|| $type eq 'restricted'
		|| $type eq 'deleted' )
	{
		my @noteArray;
		for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
			my $and_or;
            if ($searchArray[$i]{"not_like"}) {
                $and_or = "-and";
            } else {
                $and_or = "-or";
            }
			push @noteArray,
			  [
				$and_or => [
					name        => $searchArray[$i],
					description => $searchArray[$i],
					list_id     => $searchArray[$i]
				]
			  ];
		}
		my @notebooks =
		  $db->resultset("List")
		  ->search( { -and => [ @noteArray, @restricted, @deleted, ], } );

		foreach ( sort { $a->name cmp $b->name } @notebooks ) {
			if ($USER->has_access_to_list($_)) {
				push @results,
				  {
					'type'          => "notebook",
					'label'         => $_->info,
					'id'            => $_->id,
					'deleted'       => $_->deleted,
					'restricted'    => $_->restricted
				  };
			}
		}
	}
	
	#print STDERR "notebook done\n";

	# Perform user group search
	if ( $type eq 'none' || $type eq 'usergroup' || $type eq 'deleted' ) {
		my @usrGArray;
		for ( my $i = 0 ; $i < @searchArray ; $i++ ) {
			my $and_or;
            if ($searchArray[$i]{"not_like"}) {
                $and_or = "-and";
            } else {
                $and_or = "-or";
            }
			push @usrGArray,
			  [
				$and_or => [
					name          => $searchArray[$i],
					description   => $searchArray[$i],
					user_group_id => $searchArray[$i]
				]
			  ];
		}
		my @userGroup =
		  $db->resultset("UserGroup")
		  ->search( { -and => [ @usrGArray, @deleted, ], } );

		foreach ( sort { $a->name cmp $b->name } @userGroup ) {
			push @results,
			  {
				'type'    => "user_group",
				'label'   => $_->name,
				'id'      => $_->id,
				'deleted' => $_->deleted
			  };
		}
	}

	#print STDERR "Successful search\n";
	#return encode_json( { timestamp => $timestamp, items => \@results } );
	return @results;
}

1;