package CoGe::Builder::Load::Experiment;

use Moose;
extends 'CoGe::Builder::Buildable';

use Data::Dumper qw(Dumper);
use Switch;
use File::Spec::Functions qw(catfile catdir);
use File::Path qw(make_path);
use String::ShellQuote qw(shell_quote);

use CoGe::Accessory::Utils qw(get_unique_id to_filename_base);
use CoGe::Accessory::Web qw(url_for);
use CoGe::Core::Storage qw(get_workflow_paths get_workflow_results_file get_upload_path);
use CoGe::Core::Experiment qw(detect_data_type);
use CoGe::Core::Metadata qw(to_annotations tags_to_string);
use CoGe::Builder::CommonTasks;
use CoGe::Builder::Alignment::Aligner qw(build);
use CoGe::Builder::Expression::qTeller qw(build);
use CoGe::Builder::PopGen::SummaryStats qw(build);
use CoGe::Builder::SNP::CoGeSNPs qw(build);
use CoGe::Builder::SNP::Samtools qw(build);
use CoGe::Builder::SNP::Platypus qw(build);
use CoGe::Builder::SNP::GATK qw(build);
use CoGe::Builder::Methylation::Bismark qw(build);
use CoGe::Builder::Methylation::BWAmeth qw(build);
use CoGe::Builder::Methylation::Metaplot qw(build);
use CoGe::Builder::Protein::ChIPseq qw(build);
use CoGe::Exception::MissingField;
use CoGe::Exception::Generic;

sub get_name {
    my $self = shift;
    my $metadata = $self->params->{metadata};
    my $info = '"' . $metadata->{name};
    $info .= ": " . $metadata->{description} if $metadata->{description};
    $info .= " (v" . $metadata->{version} . ")";
    $info .= '"';
    return "Load Experiment " . $info;
}

sub get_site_url {
    my $self = shift;
    return url_for('LoadExperiment.pl', wid => $self->workflow->id);
}

sub build {
    my $self = shift;
    
    # Validate inputs not already checked in Request
    my $data = $self->params->{source_data};
    unless (defined $data && ref($data) eq 'ARRAY' && @$data) {
        CoGe::Exception::MissingField->throw(message => "Missing source_data");
    }
    my $metadata = $self->params->{metadata};
    unless ($metadata) {
        CoGe::Exception::MissingField->throw(message => "Missing metadata");
    }

    # mdb added 2/25/15 - convert from Mojolicious boolean: bless( do{\\(my $o = 1)}, 'Mojo::JSON::_Bool' )
    $metadata->{restricted} = $metadata->{restricted} ? 1 : 0;
    
    # Determine file type if not set
    my $file_type = $data->[0]->{file_type}; # type of first data file
    ($file_type) = detect_data_type($file_type, $data->[0]->{path}) unless $file_type;
    
    #
    # Build workflow
    #

    # Create tasks to retrieve files #TODO move to Buildable::pre_build()
    my $dr = CoGe::Builder::Common::DataRetrieval->new($self);
    $dr->build();
    my @input_files = @{$dr->data_files};

    # Add analytical tasks based on file type
    if ( $file_type eq 'fastq' || $file_type eq 'bam' || $file_type eq 'sra' ) {
        my @bam_files;
        my @raw_bam_files; # mdb added 2/29/16 for Bismark, COGE-706

        # Align fastq file or take existing bam
        if ( $file_type && ( $file_type eq 'fastq' || $file_type eq 'sra' ) ) {
            # Add alignment workflow
            my $aligner = CoGe::Builder::Alignment::Aligner->new($self);
            $aligner->build(\@input_files);
            @bam_files = @{$aligner->bam};
            @raw_bam_files = @{$aligner->raw_bam};
        }
        elsif ( $file_type && $file_type eq 'bam' ) {
            $self->add_task(
                $self->load_bam(
                    bam_file => $input_files[0]
                )
            );
            @bam_files = @raw_bam_files = @input_files;
        }
        else { # error -- should never happen
            CoGe::Exception::Generic->throw(message => 'Invalid file type');
        }
        
        # Add expression workflow (if specified)
        if ( $self->params->{expression_params} ) {
            my $expr = CoGe::Builder::Expression::qTeller->new($self);
            $expr->build($bam_files[0]);
        }
        
        # Add SNP workflow (if specified)
        if ( $self->params->{snp_params} ) {
            my $isBamSorted = ($file_type ne 'bam');
            my $snp_finder = CoGe::Builder::SNP::SNPFinder->new($self);
            $snp_finder->build($bam_files[0], $isBamSorted);
        }
        
        # Add methylation workflow (if specified)
        if ( $self->params->{methylation_params} ) {
            my $aligner = CoGe::Builder::Alignment::Aligner->new($self);
            $aligner->build($bam_files[0], $raw_bam_files[0]);
        }
        
        # Add ChIP-seq workflow (if specified)
#        if ( $self->params->{chipseq_params} ) {
#            my $chipseq_params = {
#                user => $self->user,
#                wid => $self->workflow->id,
#                genome => $genome,
#                input_files => $bam_files,
#                metadata => $metadata,
#                additional_metadata => $additional_metadata,
#                read_params => $self->params->{read_params},
#                chipseq_params => $self->params->{chipseq_params},
#            };
#
#            my $chipseq_workflow = CoGe::Builder::Protein::ChIPseq::build($chipseq_params);
#            push @tasks, @{$chipseq_workflow->{tasks}};
#            push @done_files, @{$chipseq_workflow->{done_files}};
#        }
    }
    # Else, all other file types
#    else {
#        # Add conversion step for BigWig files
#        my $input_file = $input_files[0];
#        if ( $file_type eq 'bw' ) {
#            my $wig_task = create_bigwig_to_wig_job(
#                staging_dir => $self->staging_dir,
#                input_file => $input_file
#            );
#            push @tasks, $wig_task;
#            push @done_files, $wig_task->{outputs}->[1];
#            $input_file = $wig_task->{outputs}->[0];
#        }
#
#        # Submit workflow to generate experiment
#        my $load_task = create_load_experiment_job(
#            user => $self->user,
#            staging_dir => $self->staging_dir,
#            wid => $self->workflow->id,
#            gid => $genome->id,
#            input_file => $input_file,
#            metadata => $metadata,
#            additional_metadata => $additional_metadata,
#            normalize => $self->params->{normalize} ? $self->params->{normalize_method} : 0
#        );
#        push @tasks, $load_task;
#        push @done_files, $load_task->{outputs}->[1];
#    }
    
    # Add pipeline input dependencies to tasks -- temporary kludge for SRA.pm, mdb 12/7/16
#    if ($self->inputs && @{$self->inputs}) {
#        foreach my $task (@tasks) {
#            push @{$task->{inputs}}, @{$self->inputs};
#        }
#    }

#    $self->workflow->add_jobs(\@tasks);
}

__PACKAGE__->meta->make_immutable;

1;
