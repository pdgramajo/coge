package CoGe::Builder::Methylation::Bismark;

use v5.14;
use strict;
use warnings;

use Clone qw(clone);
use Data::Dumper qw(Dumper);
use File::Basename qw(basename);
use File::Spec::Functions qw(catdir catfile);
use CoGe::Accessory::Utils qw(to_filename to_filename_without_extension);
use CoGe::Accessory::Web qw(get_defaults);
use CoGe::Core::Storage qw(get_genome_file get_workflow_paths);
use CoGe::Core::Metadata qw(to_annotations);
use CoGe::Builder::CommonTasks;

our $CONF = CoGe::Accessory::Web::get_defaults();

BEGIN {
    use vars qw ($VERSION @ISA @EXPORT @EXPORT_OK);
    require Exporter;

    $VERSION = 0.1;
    @ISA     = qw(Exporter);
    @EXPORT  = qw(build);
}

sub build {
    my $opts = shift;
    my $genome = $opts->{genome};
    my $user = $opts->{user};
    my $input_file = $opts->{raw_bam_file}; # path to bam file -- important: this should be the unsorted version
                                            # see COGE-706 and http://seqanswers.com/forums/showthread.php?t=45192
    my $metadata = $opts->{metadata};
    my $additional_metadata = $opts->{additional_metadata};
    my $wid = $opts->{wid};
    my $read_params = $opts->{read_params};
    my $methylation_params = $opts->{methylation_params};

    # Setup paths
    my ($staging_dir, $result_dir) = get_workflow_paths($user->name, $wid);

    # Set metadata for the pipeline being used
    my $annotations = generate_additional_metadata($read_params, $methylation_params);
    my @annotations2 = CoGe::Core::Metadata::to_annotations($additional_metadata);
    push @$annotations, @annotations2;

    #
    # Build the workflow
    #
    my (@tasks, @done_files);

    if ($methylation_params->{'bismark-deduplicate'}) {
        my $deduplicate_task = create_bismark_deduplicate_job( 
            bam_file => $input_file,
            read_type => $read_params->{read_type},
            staging_dir => $staging_dir
        );
        push @tasks, $deduplicate_task;
        $input_file = $deduplicate_task->{outputs}[0];
    }
    
     my $extract_methylation_task = create_extract_methylation_job( 
        bam_file => $input_file,
        read_type => $read_params->{read_type},
        staging_dir => $staging_dir,
        '--ignore' => $methylation_params->{'--ignore'},
        '--ignore_r2' => $methylation_params->{'--ignore_r2'},
        '--ignore_3prime' => $methylation_params->{'--ignore_3prime'},
        '--ignore_3prime_r2' => $methylation_params->{'--ignore_3prime_r2'}
    );
    push @tasks, $extract_methylation_task;
    
    my @outputs = @{$extract_methylation_task->{outputs}};
    while (@outputs) {
        my $file1 = shift @outputs;
        my $file2 = shift @outputs;
        
        my ($name) = $file1 =~ /(CHG|CHH|CpG)/;
        
        my $import_task = create_bismark_import_job(
            ob_input_file => $file1,
            ot_input_file => $file2,
            min_coverage => $methylation_params->{'bismark-min_converage'},
            staging_dir => $staging_dir,
            name => $name
        );
        push @tasks, $import_task;
        
        my $md = clone($metadata);
        $md->{name} .= " ($name methylation)";
        
        my $load_task = create_load_experiment_job(
            user => $user,
            metadata => $md,
            staging_dir => $staging_dir,
            wid => $wid,
            gid => $genome->id,
            input_file => $import_task->{outputs}[0],
            name => $name,
            annotations => $annotations
        );
        push @tasks, $load_task;
        push @done_files, $load_task->{outputs}[1];
    }

    return {
        tasks => \@tasks,
        done_files => \@done_files
    };
}

sub generate_additional_metadata {
    my $read_params = shift;
    my $methylation_params = shift;
    
    my @annotations;
    push @annotations, qq{https://genomevolution.org/wiki/index.php/Methylation_Analysis_Pipeline||note|Generated by CoGe's Methylation Analysis Pipeline};
    
    if ($read_params->{'read_type'} eq 'paired') {
        if ($methylation_params->{'bismark-deduplicate'}) {
            push @annotations, 'note|deduplicate_bismark -p';
        }
        push @annotations, 'note|bismark_methylation_extractor ' . join(' ', map { $_.' '.$methylation_params->{$_} } ('--ignore', '--ignore_r2', '--ignore_3prime', '--ignore_3prime_r2'));
    }
    else {
        if ($methylation_params->{'bismark-deduplicate'}) {
            push @annotations, 'note|deduplicate_bismark -s';
        }
        push @annotations, 'note|bismark_methylation_extractor ' . join(' ', map { $_.' '.$methylation_params->{$_} } ('--ignore', '--ignore_3prime'));
    }
    
    return \@annotations;
}

sub create_bismark_deduplicate_job {
    my %opts = @_;
    my $bam_file = $opts{bam_file};
    my $read_type = $opts{read_type} // 'single';
    my $staging_dir = $opts{staging_dir};
    my $name = basename($bam_file);
    
    my $cmd = ($CONF->{BISMARK_DIR} ? catfile($CONF->{BISMARK_DIR}, 'deduplicate_bismark') : 'deduplicate_bismark');
    $cmd = 'nice ' . $cmd;
    
    my $args;
    if ($read_type eq 'paired') {
        push @$args, ['-p', '', 0];
    }
    else { # single-ended
        push @$args, ['-s', '', 0];
    }
    
    push @$args, ['--bam', $bam_file, 1];
    
    my $output_file = to_filename_without_extension($bam_file) . '.deduplicated.bam';
    
    return {
        cmd => $cmd,
        script => undef,
        args => $args,
        inputs => [
            $bam_file
        ],
        outputs => [
            catfile($staging_dir, $output_file),
        ],
        description => "Deduplicating PCR artifacts using Bismark"
    };
}

sub create_extract_methylation_job {
    my %opts = @_;
    my $bam_file = $opts{bam_file};
    my $read_type = $opts{read_type} // 'single';
    my $ignore = $opts{'--ignore'} // 0;
    my $ignore_r2 = $opts{'--ignore_r2'} // 0;
    my $ignore_3prime = $opts{'--ignore_3prime'} // 0;
    my $ignore_3prime_r2 = $opts{'--ignore_3prime_r2'} // 0;
    my $staging_dir = $opts{staging_dir};
    
    my $cmd = $CONF->{BISMARK_DIR} ? catfile($CONF->{BISMARK_DIR}, 'bismark_methylation_extractor') : 'bismark_methylation_extractor';
    $cmd = 'nice ' . $cmd;
    
    my $name = to_filename_without_extension($bam_file);
    
    my $args = [
        ['--multicore', 4, 0],
        ['--output', $staging_dir, 0],
        ['--ignore', $ignore, 0],
        ['--ignore_3prime', $ignore_3prime, 0]
    ];
    
    if ($read_type eq 'paired') {
        push @$args, ['-p', '', 0];
        push @$args, ['--ignore_r2', $ignore_r2, 0];
        push @$args, ['--ignore_3prime_r2', $ignore_3prime_r2, 0];
    }
    
    push @$args, ['', $bam_file, 0];
    
    my $done_file = catfile($staging_dir, 'extract_methylation.done');
    push @$args, ['', '&& touch ' . $done_file, 0]; # kludge to ensure proper sequence since --output dir must be absolute
    
    return {
        cmd => $cmd,
        script => undef,
        args => $args,
        inputs => [
            $bam_file
        ],
        outputs => [
            catfile($staging_dir, 'CHG_OB_' . $name . '.txt'),
            catfile($staging_dir, 'CHG_OT_' . $name . '.txt'),
            catfile($staging_dir, 'CHH_OB_' . $name . '.txt'),
            catfile($staging_dir, 'CHH_OT_' . $name . '.txt'),
            catfile($staging_dir, 'CpG_OB_' . $name . '.txt'),
            catfile($staging_dir, 'CpG_OT_' . $name . '.txt')
        ],
        description => "Extracting methylation status"
    };
}

sub create_bismark_import_job {
    my %opts = @_;
    my $ot_input_file = $opts{ot_input_file};
    my $ob_input_file = $opts{ob_input_file};
    my $min_coverage = $opts{min_coverage} // 5;
    my $staging_dir = $opts{staging_dir};
    my $name = $opts{name};
    
    my $cmd = catfile($CONF->{SCRIPTDIR}, 'methylation', 'coge-import_bismark.py');
    die "ERROR: SCRIPTDIR is not in the config." unless $cmd;
    
    my $output_file = $name . '.filtered.coge.csv';
    
    return {
        cmd => $cmd,
        script => undef,
        args => [
            ['-u', 'f', 0],
            ['-c', $min_coverage, 0],
            ['--OT', $ot_input_file, 1],
            ['--OB', $ob_input_file, 1],
            ['-o', $name, 0]
        ],
        inputs => [
            $ot_input_file,
            $ob_input_file,
            catfile($staging_dir, 'extract_methylation.done')
        ],
        outputs => [
            catfile($staging_dir, $output_file),
        ],
        description => "Converting $name"
    };
}

1;