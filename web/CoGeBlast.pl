#! /usr/bin/perl -w
use strict;
use CGI;
use CGI::Ajax;
use CoGe::Accessory::LogUser;
use CoGe::Accessory::Web;
use HTML::Template;
use Text::Wrap qw($columns &wrap);
use Data::Dumper;
use LWP::Simple;
use LWP::Simple::Post qw(post post_xml);
use URI::Escape;
use CoGeX;
use POSIX;
use Digest::MD5 qw(md5_hex);
use DBIxProfiler;
use File::Temp;
use File::Basename;
use CoGe::Accessory::blast_report;
use CoGe::Accessory::blastz_report;
use CoGe::Accessory::Restricted_orgs;
use CoGe::Graphics::GenomeView;
use CoGe::Graphics;
use CoGe::Graphics::Chromosome;
use CoGe::Graphics::Feature::HSP;
use CoGe::Genome;
use Spreadsheet::WriteExcel;
use Benchmark qw(:all);

$ENV{PATH} = "/opt/apache/CoGe/";
$ENV{BLASTDB}="/opt/apache/CoGe/data/blast/db/";
$ENV{BLASTMAT}="/opt/apache/CoGe/data/blast/matrix/";
use vars qw( $TEMPDIR $TEMPURL $DATADIR $FASTADIR $BLASTDBDIR $FORMATDB $BLAST $BLASTZ $FORM $USER $DATE $coge $cogeweb);

$TEMPDIR = "/opt/apache/CoGe/tmp/CoGeBlast";
$DATADIR = "/opt/apache/CoGe/data/";
$FASTADIR = $DATADIR.'/fasta/';
$BLASTDBDIR = $DATADIR.'/blast/db/';
$TEMPURL = "/CoGe/tmp/CoGeBlast";
$FORMATDB = "/usr/bin/formatdb";
$BLAST = "/usr/bin/blast";
$BLASTZ = "/usr/bin/blastz";

$DATE = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
		sub { ($_[5]+1900, $_[4]+1, $_[3]),$_[2],$_[1],$_[0] }->(localtime));
($USER) = CoGe::Accessory::LogUser->get_user();
$FORM = new CGI;

my $connstr = 'dbi:mysql:dbname=genomes;host=biocon;port=3306';
$coge = CoGeX->connect($connstr, 'cnssys', 'CnS' );
#$coge->storage->debugobj(new DBIxProfiler());
#$coge->storage->debug(1);

#my %ajax = CoGe::Accessory::Web::ajax_func();

my $pj = new CGI::Ajax(
		       gen_html=>\&gen_html,
		       cogesearch=>\&cogesearch,
		       source_search=>\&get_data_source_info_for_accn,
		       get_types=>\&get_types,
		       get_sequence=>\&get_sequence,
		       get_url=>\&get_url,
		       check_seq=>\&check_seq,
		       set_seq=>\&set_seq,
		       blast_param=>\&blast_param,
		       database_param=>\&database_param,
		       get_orgs=>\&get_orgs,
		       get_from_id=>\&get_from_id,
		       blast_search=>\&blast_search,
		       generate_feat_info=>\&generate_feat_info,
		       get_hsp_info=>\&get_hsp_info,
		       generate_overview_image=>\&generate_overview_image,
		       overlap_feats_parse=>\&overlap_feats_parse,
		       get_nearby_feats=>\&get_nearby_feats,
		       export_fasta_file=>\&export_fasta_file,
		       generate_excel_feature_file=>\&generate_excel_feature_file,
		       generate_tab_deliminated=>\&generate_tab_deliminated,
		       generate_feat_list=>\&generate_feat_list,
		       dataset_description_for_org=>\&dataset_description_for_org,
		      );
$pj->js_encode_function('escape');
print $pj->build_html($FORM, \&gen_html);
#print $FORM->header;
#$USER=1;print gen_html();


sub gen_html
  {
    my $html;
    unless ($USER)
      {
	$html = login();
      }
    else
     {
    my ($body) = gen_body();
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/generic_page.tmpl');
    $template->param(TITLE=>'CoGe: BLAST');
    $template->param(HELP=>'BLAST');
   # print STDERR "user is: ",$USER,"\n";
    $template->param(USER=>$USER);
    $template->param(DATE=>$DATE);
    $template->param(LOGO_PNG=>"CoGeBlast-logo.png");
    $template->param(BOX_NAME=>'CoGe: Blast');
    $template->param(BODY=>$body);
    $html .= $template->output;
    }
  }

sub gen_body
  {
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
    my $form = $FORM;
    my $featid = join (",",$form->param('featid')) || 0;
    my $chr = $form->param('chr') || 0;
    my $upstream = $form->param('upstream') || 0;
    my $downstream = $form->param('downstream') || 0;
    my $dsid = $form->param('dsid') || 0;
    #my $feat_name = $form->param('featname');
    my $rc = $form->param('rc') || 0;
    $template->param(JAVASCRIPT=>1);
    $template->param(BLAST_FRONT_PAGE=>1);
    $template->param(UPSTREAM=>$upstream);
    $template->param(DOWNSTREAM=>$downstream);
    $template->param(DSID=>$dsid);
    $template->param(ORG_LIST=>get_orgs());
    $template->param(RC=>$rc);
    $template->param(FEATID=>$featid);
    $template->param(CHR=>$chr);
    if ($featid)
    {
    	$template->param(DISPLAY_FEAT=>1);
    	$template->param(SEQVIEW=>1);
#    	my $seq = get_sequence($featid, $dsid, 0, 1, $upstream, $downstream,$rc);
#        $template->param(SEQUENCE=>$seq);
    }
    elsif ($chr)
    {
    	$template->param(SEQVIEW=>2);
#    	my $seq = get_sequence($chr, $dsid, 0, 2, $upstream, $downstream,$rc);
#    	$template->param(SEQUENCE=>$seq);
    }
    else{
        $template->param(SEQVIEW=>0);
        $template->param(SEQUENCE=>'Enter a fasta sequence here');
    }
    $template->param(USER_NAME=>$USER);
    #$template->param(DEFAULT_PARAM=>$param);
    $template->param(REST=>1);
    $template->output;
  }
  
sub get_sequence
  {
    my %opts = @_;
    my $fids = $opts{fid};
    my $dsid = $opts{dsid};
    my $chr = $opts{chr};
    my $start = $opts{start};
    my $stop = $opts{stop};
    my $blast_type = $opts{blast_type};
    my $upstream = $opts{upstream};
    my $downstream = $opts{downstream};
    my $rc = $opts{rc};
    my $fasta;
    my $prot = $blast_type =~ /blast_type_p/ ? 1 : 0;
    if ($fids)
      {
	foreach my $fid (split /,/, $fids)
	  {
	    my $feat = $coge->resultset('Feature')->find($fid);
	    $fasta .= ref($feat) =~ /Feature/i ?
	      $feat->fasta(
			   prot=>$prot,
			   rc=>$rc,
			   upstream=>$upstream,
			   downstream=>$downstream,
			  )
		:
		  ">Unable to retrieve Feature object for id: $fid\n";
	  }
      }
    else
      {
	my $ds = $coge->resultset('Dataset')->find($dsid);
	$fasta = ref ($ds) =~ /dataset/i ? 
	  $ds->fasta
	    (
	     start=>$start,
	     stop=>$stop,
	     chr=>$chr,
	     prot=>$prot,
	     rc=>$rc,
	    )
	      :
		">Unable to retrieve dataset object for id: $dsid";
      }
    return $fasta
  }

sub get_url
  {
    my $url = shift;
    if ($url eq "blastn") {
      $url = "http://www.ncbi.nlm.nih.gov/blast/Blast.cgi?PAGE=Nucleotides&PROGRAM=blastn&MEGABLAST=on&BLAST_PROGRAMS=megaBlast&PAGE_TYPE=BlastSearch&SHOW_DEFAULTS=on";}
    elsif ($url eq "blastp") {
      $url = "http://www.ncbi.nlm.nih.gov/BLAST/Blast.cgi?PAGE=Proteins&PROGRAM=blastp&BLAST_PROGRAMS=blastp&PAGE_TYPE=BlastSearch&SHOW_DEFAULTS=on";}
      elsif ($url eq "blastx") {
        $url = "http://www.ncbi.nlm.nih.gov/BLAST/Blast.cgi?PAGE=Translations&PROGRAM=blastx&BLAST_PROGRAMS=blastx&PAGE_TYPE=BlastSearch&SHOW_DEFAULTS=on";}
    elsif ($url eq "tblastn") {
      $url = "http://www.ncbi.nlm.nih.gov/BLAST/Blast.cgi?PAGE=Translations&PROGRAM=tblastn&BLAST_PROGRAMS=tblastn&PAGE_TYPE=BlastSearch&SHOW_DEFAULTS=on";}
    elsif ($url eq "tblastx") {
      $url = "http://www.ncbi.nlm.nih.gov/BLAST/Blast.cgi?PAGE=Translations&PROGRAM=tblastx&BLAST_PROGRAMS=tblastx&PAGE_TYPE=BlastSearch&SHOW_DEFAULTS=on";}
    else {
      $url = 1;}
    return $url;
  }

sub blast_param
{
    my %opts = @_;
    my $seq_type = $opts{blast_type} || "blast_type_n";
    my $translate = $opts{translate};
    my $version = $opts{version};
    my $pro;
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
    if ($seq_type =~ "blast_type_n") {
      if($version && $version =~ /coge_radio/) {$template->param(BLAST_NU=>1);}
      else {$template->param(NCBI_BLAST_NU=>1);}        
    }
    else {
      $pro = 1;
      if($version && $version =~ /coge_radio/) {$template->param(BLAST_PRO=>1);}
      else {$template->param(NCBI_BLAST_PRO=>1);}
	  
	  unless ($translate)
	  {
	     if($version =~ /coge_radio/) {$template->param(BLAST_PRO_COMP=>1);}
	     else {$template->param(NCBI_BLAST_PRO_COMP=>1);}	  
	  }
    }
    my $html = $template->output;
    return $html,$version,$pro;
}

sub database_param
  {
    my $program = shift || "blastn";
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
    if ($program eq "blastn")
      {$template->param(NU_DB=>1);}
    elsif (($program eq "blastp") || ($program eq "blastx"))
      {$template->param(PRO_DB=>1);}
    else
      {$template->param(T_DB=>1);}
    my $html = $template->output;
    return $html;
  }

sub get_orgs
  {
    my $name = shift;
    my @db = $name ? $coge->resultset('Organism')->search({name=>{like=>"%".$name."%"}})
      : $coge->resultset('Organism')->all();
    ($USER) = CoGe::Accessory::LogUser->get_user();
    my $restricted_orgs = restricted_orgs(user=>$USER);
    my @opts;
    foreach my $item (sort {uc($a->name) cmp uc($b->name)} @db)
      {
	next if $restricted_orgs->{$item->name};
	push @opts, "<OPTION value=\"".$item->id."\" id=\"o".$item->id."\">".$item->name."</OPTION>";
      }
    my $html;
    $html .= qq{<FONT CLASS ="small" id="org_count">Organism count: }.scalar @opts.qq{</FONT>\n<BR>\n};
    unless (@opts) 
      {
	$html .=  qq{<input type = hidden name="org_id" id="org_id"><br>};
	$html .= "No results";
	return $html;
      }

    $html .= qq{<SELECT id="org_id" SIZE="8" MULTIPLE onClick="\$('#remove').hide(0);\$('#add').show(0);" ondblclick="get_from_id(['org_id'],[add_to_list]);">\n};
    $html .= join ("\n", @opts);
    $html .= "\n</SELECT>\n";
    $html =~ s/OPTION/OPTION SELECTED/;
    return $html;
  }
  
sub get_from_id
  {
    my $id = shift;
    #print STDERR "search for $id\n";
    my ($obj) = $coge->resultset('Organism')->find($id);
    my $org = $obj->name;
    return ($id,$org);
  }

sub blast_search
  {
    my %opts = @_;
    my $program = $opts{program};
    my $expect = $opts{expect};
    my $job_title = $opts{job_title};
    my $wordsize = $opts{wordsize};
    my $comp = $opts{comp};
    my $matrix = $opts{matrix};
    my $gapcost = $opts{gapcost};
    my $match_score = $opts{matchscore};
    #blastz params
    my $zwordsize = $opts{zwordsize};
    my $zgap_start = $opts{zgap_start};
    my $zgap_extension = $opts{zgap_extension};
    my $zchaining = $opts{zchaining};
    my $zthreshold = $opts{zthreshold};
    my $zmask = $opts{zmask};


    my $seq = $opts{seq};
    my $blastable = $opts{blastable};
    my $width = $opts{width};
    my $type = $opts{type};

    

#    print STDERR Dumper \%opts;
    my $t1 = new Benchmark;
    $cogeweb = initialize_basefile(prog=>"CoGeBlast");
    my @org_ids = split(/,/,$blastable);
    my $fasta_file = create_fasta_file($seq);
    my $opts;
    my $pre_command;
    if ($program eq "blastz")
      {
	$pre_command = $BLASTZ;
	$pre_command .= " $fasta_file";

	$opts .= " W=" .$zwordsize if defined $zwordsize;
	$opts .= " C=" .$zchaining if defined $zchaining;
	$opts .= " K=" .$zthreshold if defined $zthreshold;
	$opts .= " M=" .$zmask if defined $zmask;
	$opts .= " O=" .$zgap_start if defined $zgap_start;
	$opts .= " E=" .$zgap_extension if defined $zgap_extension;
	my $tmp;
	($tmp, $opts) = check_taint($opts);
      }
    else
      {
	my ($nuc_penalty,$nuc_reward,$exist,$extent);
	#print STDERR $gapcost,"\n";
	if ($gapcost =~/^(\d+)\s+(\d+)/) {($exist,$extent) = ($1,$2);}
	
	if ($match_score=~/^(\d+)\,(-\d+)/) {($nuc_penalty,$nuc_reward) = ($2,$1);}
	$pre_command = "$BLAST -p $program -i $fasta_file";
	if ($program =~ /^blastn$/i)
	  {
	    $pre_command .= " -q $nuc_penalty -r $nuc_reward";
	  }
	else
	  {
	    $pre_command .= " -M $matrix";
	  }
	$pre_command .=" -W $wordsize";
	$pre_command .= " -G $exist -E $extent" if $exist && $extent;
	$pre_command .= " -e $expect";
	$pre_command .= " -C $comp" if $program =~ /tblastn/i;
      }
    my $x;
    ($x, $pre_command) = check_taint($pre_command);
    my @results;
    my $count =1;
    my $t2 = new Benchmark;
    foreach my $orgid (@org_ids)
      {
	my ($org, $db, $fasta_file) = get_blast_db($orgid);
	next unless $db;
	my $command;
	my $outfile;
	my $report;
	if ($program eq "blastz")
	  {
	    $command = $pre_command." $fasta_file $opts";
	    $outfile = $cogeweb->basefile."-$count.blastz";
	    write_log("running $command" ,$cogeweb->logfile);
	    `$command > $outfile`;
	    $report = new CoGe::Accessory::blastz_report({file=>$outfile}) if -r $outfile;
	  
	  }
	else
	  {
	    $command = $pre_command." -d $db";
	    $outfile = $cogeweb->basefile."-$count.blast";
	    write_log("running $command" ,$cogeweb->logfile);
	    `$command > $outfile`;
	    $report = new CoGe::Accessory::blast_report({file=>$outfile}) if -r $outfile;
	  }
	my $file = $report->file();
	$file =~ s/$TEMPDIR//;
	$file = $TEMPURL."/".$file;
	push @results, {
			command=>$command,
			file=>$outfile,
			report=>$report,
			link=>$file,
			organism=>$org,
		       };
	$count++;
      }
    my $t3 = new Benchmark;
    initialize_sqlite();
    my $t4 = new Benchmark;
    my $html = gen_results_page(results=>\@results,width=>$width,type=>$type);
    my $t5 = new Benchmark;
    my $init_time = timestr(timediff($t2,$t1));
    my $blast_time = timestr(timediff($t3,$t2));
    my $dbinit_time = timestr(timediff($t4,$t3));
    my $resultpage_time = timestr(timediff($t5,$t4));
    my $benchmark = qq{
Time to initialize:              $init_time
Time to blast:                   $blast_time
Time to initialize sqlite:       $dbinit_time
Time to generate results page:   $resultpage_time
};
      write_log("$benchmark" ,$cogeweb->logfile);
    return $html,$cogeweb->basefilename;
  }
 
 
sub gen_results_page
   {
     my %opts = @_;
     my $results = $opts{results};
     my $width = $opts{width};
     my $type = $opts{type};
     my $null;
     my $hsp_count = 0;;
     my @table;
     my $length;
     my $flag;
     my @check;
     my @no_feat;
     my $t0 = new Benchmark;
     foreach my $set (@$results)
       {
	 if (@{$set->{report}->hsps()})
	   {
	     foreach my $hsp (@{$set->{report}->hsps()})
	       {
		 $hsp_count++;
		 my ($dsid) = $hsp->subject_name =~ /id: (\d+)/;
		 my ($chr) = $hsp->subject_name =~ /chromosome: (.*?),/;
		 my ($org) = $hsp->subject_name =~ /^\s*(.*?)\s*\(/;
		 next unless $dsid && $chr;
 		 my @feat;
		 foreach my $feat($coge->get_features_in_region(start=>$hsp->subject_start,  
 							  stop=>$hsp->subject_stop,
 							  chr=>$chr, 
 							  dataset_id=>$dsid,
 							 ))
		   {
		     next if $feat->type->name =~ /source/;
		     push @feat, $feat if $feat;
		   }
		if (@feat) 
		  {
		    my %seen;
		    grep { ! $seen{lc($_)} ++ } map {$_->type->name} @feat;
		    foreach my $key (keys %seen)
		      {
			$seen{'rna'}=1 if $key =~ /rna/i;
		      }
		    my $search_type;
		    $search_type = "gene" if $seen{gene};
		    $search_type = "cds" if !$search_type && $seen{cds};
		    $search_type = "rna" if !$search_type && $seen{rna};
		    $search_type = "exon" if !$search_type && $seen{exon};
		    ($search_type) = keys %seen unless $search_type;
		    $search_type = undef if $search_type =~ /source/i;
		    my $no_genes = 0;
		    foreach my $feature (@feat)
		      {
			#print STDERR $search_type,"::",$feature->type->name,"\n" if $feature->dataset->organism->name =~ /Poplar/i;
			next unless $search_type && $feature->type->name =~ /$search_type/i;
			$no_genes++;
			$length = (($feature->stop) - ($feature->start));		     
			my ($name) = sort $feature->names;
			foreach my $data (@check)
			  {
			    $flag = 1 if ($data->{name} && $name && ($data->{name} eq $name) && ($data->{score} == $hsp->score));
			  }
			unless ($flag) {
			  my $fid = $feature->id."_".$hsp->number."_".$dsid;
			  my $pid = $hsp->percent_id =~ /\./ ? $hsp->percent_id : $hsp->percent_id.".0";
			  push @table, {FID=>$fid,FEATURE_NAME=>qq{<a href="#" onclick="update_info_box('table_row$fid')">$name</a>},
					FEATURE_HSP=>qq{<a href="#" onclick="update_hsp_info('table_row$fid')">}.$hsp->number."</a>",
					FEATURE_EVAL=>qq{<a href="#" onclick="update_hsp_info('table_row$fid')">}.$hsp->pval."</a>",
					FEATURE_PID=>qq{<a href="#" onclick="update_hsp_info('table_row$fid')">}.$hsp->percent_id."</a>",
					FEATURE_SCORE=>qq{<a href="#" onclick="update_hsp_info('table_row$fid')">}.$hsp->score."</a>",
					FEATURE_LENGTH=>qq{<a href="#" onclick="update_info_box('table_row$fid')">$length</a>},
					FEATURE_ORG=>qq{<a href="#" onclick="update_info_box('table_row$fid')">$org</a>},};
			  push @check,{name=>$name,score=>$hsp->score};
			}
			$flag=0;
		      }
		    unless($no_genes)
		     {
		       
		       my $id = $hsp->number."_".$dsid;
		       my $no_link = qq{<a href="#" onclick="fill_nearby_feats('$id')">Click for Closest Feature</a>};
		       push @no_feat, {
		       				CHECKBOX=>$id."_".$chr."_".$hsp->subject_start."no",
		       				ID=>$id,
		       			   NO_FEAT_ORG=>$org,
		       			   NO_FEAT=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->number."</a>",
		       			   NO_FEAT_EVAL=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->pval."</a>",
				             NO_FEAT_PID=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->percent_id."</a>",
				             NO_FEAT_SCORE=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->score."</a>",
		       			   NO_FEAT_LINK=>$no_link};
		     }
		 }
		 else {
		   #print STDERR "We have some no feat-hit hsps\n";
		   my $id = $hsp->number."_".$dsid;
		   my $no_link = qq{<a href="#" onclick="fill_nearby_feats('$id')">Click for Closest Feature</a>};
		   push @no_feat, {CHECKBOX=>$id."_".$chr."_".$hsp->subject_start."no",
		   					ID=>$id,
		       			   NO_FEAT_ORG=>$org,
		       			   NO_FEAT=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->number."</a>",
		       			   NO_FEAT_EVAL=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->pval."</a>",
				             NO_FEAT_PID=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->percent_id."</a>",
				             NO_FEAT_SCORE=>qq{<a href="#" onclick="update_hsp_info('table_row$id')">}.$hsp->score."</a>",
		       			   NO_FEAT_LINK=>$no_link};
		 }
		 populate_sqlite($hsp,$dsid);
	       }
	   }
       }
     my $t1 = new Benchmark;
     my ($chromosome_data, $chromosome_data_large) = generate_chromosome_images(results=>$results,large_width=>$width,hsp_type=>$type);
     my $t2 = new Benchmark;
     unless (@table || @no_feat) 
       {
	 $null = "null";
       }
     #table sort!
#     @table = sort {$a->{FEATURE_ORG} cmp $b->{FEATURE_ORG} || $a->{FEATURE_HSP} <=> $b->{FEATURE_HSP} || $a->{FEATURE_EVAL} <=> $b->{FEATURE_EVAL} } @table;
#     @table = sort {$a->{FEATURE_ORG} cmp $b->{FEATURE_ORG} || $a->{FEATURE_HSP} <=> $b->{FEATURE_HSP} } @table;
     
     my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
	 $template->param(OVERLAP_FEATURE_IF=>1);
     # ERIC, i added this so it woulndt fail
     if (@table)
       {
	 $template->param(YES_FEAT_IF=>1);
	 $template->param(FEATURE_TABLE=>\@table);#unless $null;
       }
     $template->param(NULLIFY=>$null) if $null;
     $template->param(HSP_COUNT=>$hsp_count);

     if (@no_feat)
     {
       @no_feat = sort {$a->{NO_FEAT_ORG} cmp $b->{NO_FEAT_ORG} || $a->{NO_FEAT} cmp $b->{NO_FEAT}} @no_feat if @no_feat;
       $template->param(NO_FEAT_IF=>1);
       $template->param(NO_FEATS=>\@no_feat);
     }
     
     my $overlap_feature_element = $template->output;
     $template->param(NO_FEAT_IF=>0);
     $template->param(OVERLAP_FEATURE_IF=>0);
     $template->param(OVERLAP_FEATURE_LIST=>$overlap_feature_element);
     $template->param(CHROMOSOMES_IF=>1);
     $template->param(CHROMOSOME_LOOP=>$chromosome_data);
     my $chromosome_element = $template->output;
     $template->param(CHROMOSOMES_IF=>0);
     if (scalar(@$chromosome_data_large) > 0)
     {
       $template->param(CHROMOSOMES_LARGE_IF=>1);
       $template->param(CHROMOSOME_LOOP_LARGE=>$chromosome_data_large);
       my $chr_large_element = $template->output;
       $template->param(CHROMOSOMES_LARGE_IF=>0);
       $template->param(CHR_LARGE=>$chr_large_element);
     }
     $template->param(CHROMOSOMES=>$chromosome_element);
     $template->param(BLAST_RESULTS=>1);
     $template->param(DATA_FILES=>gen_data_file_summary());
     my $html = $template->output;
     my $t3 = new Benchmark;
    my $table_time = timestr(timediff($t1,$t0));
    my $figure_time = timestr(timediff($t2,$t1));
    my $render_time = timestr(timediff($t3,$t2));
    my $benchmark = qq{
Time to gen tables:              $table_time
Time to gen images:              $figure_time
Time to gen resutls:             $render_time
};
     print STDERR $benchmark;
     write_log($benchmark, $cogeweb->logfile);
     return $html;
   }

sub gen_data_file_summary
  {
    my $html = "<table><tr>";
    $html .= qq{<td class = small>SQLite db};
    my $dbname = $TEMPURL."/".basename($cogeweb->sqlitefile);
    
    $html .= "<div class=xsmall><A HREF=\"$dbname\" target=_new>SQLite DB file</A></DIV>\n";
    $html .= qq{<td class = small>Log File};
    my $logfile = $TEMPURL."/".basename($cogeweb->logfile);
    $html .= "<div class=xsmall><A HREF=\"$logfile\" target=_new>Log</A></DIV>\n";
    $html .= qq{</table>};
  }

sub generate_chromosome_images
  {
    my %opts = @_;
    my $results = $opts{results};
    my $hsp_type = $opts{hsp_type} || "NA";
    my $width = $opts{width} || 400;
    my $large_width = $opts{large_width} || 3*$width;
    my $imagefile_name = $opts{filename} || "null";
    my $height = ($width / 16);
    my $large_height = ($large_width / 16) <= 64 ? ($large_width / 16) : 64;
    my $scale = $opts{scale} || 'linear';
    my %data;
    my $filename;
    my ($hsp_info,$max,$min,$length);
    my (@data, @large_data,@no_data);
    foreach my $set (@$results)
    {
	my $org = $set->{organism};
	$data{$org}{file}=$set->{link};
	$filename = $imagefile_name."_*.png";
	if ($imagefile_name ne "null")
	{
	  if (`ls $filename 2>>/dev/null`)
	  {
	    $data{$org}{image} = $imagefile_name;
	    $data{$org}{skip} = 1;
	    next;
	  }
	}
	$filename = $set->{link};
	($hsp_info,$max,$min,$length) = get_color_scheme($set, $hsp_type);
	if (@{$set->{report}->hsps()})
	  {
	    my @hsps;
	    if ($hsp_type eq "eval")
	      {
		@hsps = sort {$b->eval <=> $a->eval} @{$set->{report}->hsps()}
	      }
	    elsif ($hsp_type eq "length")
	      {
		@hsps = sort {$a->length <=> $b->length} @{$set->{report}->hsps()}
	      }
	    elsif ($hsp_type eq "score")
	      {
		@hsps = sort {$a->score <=> $b->score} @{$set->{report}->hsps()}
	      }
	    else
	      {
		@hsps = sort {$a->percent_id <=> $b->percent_id} @{$set->{report}->hsps()}
	      }


	    
	    foreach my $hsp (@hsps)
	      {
		#first, initialize graphic
		$org =~ s/\s+$//;
		my ($chr) = $hsp->subject_name =~ /chromosome: (.*?),/;
		$data{$org}{image} =new CoGe::Graphics::GenomeView({color_band_flag=>1, image_width=>$width, chromosome_height=>$height}) unless $data{$org}{image};
		$data{$org}{large_image} =new CoGe::Graphics::GenomeView({color_band_flag=>1, image_width=>$large_width, chromosome_height=>$large_height}) unless $data{$org}{large_image};
		my ($dsid) = $hsp->subject_name =~ /id: (\d+)/;
		#add chromosome to graphic
		unless ($data{$org}{chr}{$chr})
		  {
		    next unless $dsid;
		    my $ds = $coge->resultset('Dataset')->find($dsid);
		    my $last_pos = $ds->last_chromosome_position($chr);
		    $data{$org}{image}->add_chromosome(name=>"Chr: $chr",
						       end=>$last_pos,
						      );
		    $data{$org}{chr}{$chr}=1;
		  }
		my $num = $hsp->number."_".$dsid;
		my $up = $hsp->strand eq "++" ? 1 : 0;
# 		my $r = generate_colors(max=>$max,
# 					min=>$min,
# 					length=>$length,
# 					scale=>$scale,
# 					val=>$hsp_info->{$hsp->number},
# 					);
# 		my $b = generate_colors(max=>$max,
# 					min=>$min,
# 					length=>$length,
# 					scale=>$scale,
# 					val=>$hsp_info->{$hsp->number},
# 					reverse_flag=>1,
# 					);
# 		#Reverse color scheme for eval, as less is more
# 		($r, $b) = ($b, $r) if $hsp_type eq "eval";
  		$data{$org}{image}->add_feature(name=>$hsp->number,
  						start=>$hsp->sstart,
  						stop=>$hsp->sstop,
  						chr=>"Chr: $chr",
  						imagemap=>qq/class="imagemaplink" title="HSP No. /.$hsp->number.qq/" onclick="hide_big_picture();show_hsp_div();loading('image_info','Information');loading('query_image','Image');loading('subject_image','Image');get_hsp_info(['args__blastfile','args__/.$cogeweb->basefile.qq/','args__num','args__$num'],['image_info','query_image','subject_image']);"/,
  						up=>$up,
  						color=>[255,0,0],
  					       );
	      }
	  }
      }
    my $count = 1;
    foreach my $org (sort keys %data)
    {
	if ($data{$org}{image})
	  {
	    my $image_file;
	    my $image_map;
	    my $large_image_file;
	    my $image_map_large;
	    unless ($data{$org}{skip})	    
	      {
		my $x;
		$large_image_file = $cogeweb->basefile."_".$hsp_type."_$count"."_large.png";
		($x, $large_image_file) = check_taint($large_image_file);
		$image_file = $cogeweb->basefile."_".$hsp_type."_$count.png";
		($x, $image_file) = check_taint($image_file);
		$data{$org}{image}->generate_png(filename=>$image_file);
		$image_map = $data{$org}{image}->generate_imagemap(mapname=>$cogeweb->basefilename."_".$count);

		my $map_file = $cogeweb->basefile."_$count.$hsp_type.map";
		($x, $map_file) = check_taint($map_file);
		open (MAP, ">$map_file");
		print MAP $image_map;
		close MAP;
		$data{$org}{image}->image_width($large_width);
		$data{$org}{image}->chromosome_height($large_height);
		$data{$org}{image}->generate_png(filename=>$large_image_file);
		$image_map_large = $data{$org}{image}->generate_imagemap(mapname=>$cogeweb->basefilename."_".$count."_large");
		$map_file = $cogeweb->basefile."_$count.$hsp_type.large.map";
		($x, $map_file) = check_taint($map_file);
		open (MAP, ">$map_file");
		print MAP $image_map_large;
		close MAP;

	    }
	    else
	      {
		my $x;
		$image_file = $data{$org}{image}."_$count.png";
		$image_map = get_map($cogeweb->basefile."_$count.$hsp_type.map");
		$large_image_file = $data{$org}{image}."_$count"."_large.png";
		$image_map_large = get_map($cogeweb->basefile."_$count.$hsp_type.large.map");
		#print STDERR $image_map_large,"\n";
		($x, $image_file) = check_taint($image_file);
		($x, $large_image_file) = check_taint($large_image_file);
	      }
	    
	    $image_file =~ s/$TEMPDIR/$TEMPURL/;
	    $large_image_file =~ s/$TEMPDIR/$TEMPURL/;
	    
	    push @large_data,  {DB_NAME_LARGE=>"<a href=".$data{$org}{file}. " target=_new>$org <span class='small link'>Blast Report</span></a><br>", CHR_IMAGE_LARGE=>"<img src=$large_image_file ismap usemap='".$cogeweb->basefilename."_"."$count"."_large' border=0>$image_map_large",IMAGE_ID_LARGE=>$count,};
	    push @data,  {DB_NAME=>"<a href=".$data{$org}{file}. " target=_new>$org <span class='small link'>Blast Report</span></a><br>", CHR_IMAGE=>"<img src=$image_file ismap usemap='".$cogeweb->basefilename."_"."$count' border=0>$image_map",HIT=>1,IMAGE_ID=>$count,};
	    $count++;
	  }
	else
	  {
	    push @no_data,  {DB_NAME=>"No Hits: <a href=".$data{$org}{file}. " target=_new>$org</a>"};
	  }
      }


    return [@data,@no_data], \@large_data;
  }

sub get_map
  {
    my $file = shift;
    my $map;
    open (IN, $file) || die "$!";
    while (<IN>)
      {
	$map .= $_;
      }
    close IN;
    return $map;
  }

sub create_fasta_file
  {
    my $seq = shift;
    write_log("creating user's fasta file",$cogeweb->logfile);
    open(NEW,"> ".$cogeweb->basefile.".fasta");
    print NEW $seq;
    close NEW;
    return $cogeweb->basefile.".fasta";
  }
    

sub get_color_scheme
  {
    my $set = shift;
    my $type = shift || 0;
    my %hsps;
    my %info;
    my @sorted_vals;
    my $max;
    my $min;
    my $code_ref;
    if ($type eq "eval")
      {
	$code_ref = sub {$_->eval;};
      }
    elsif ($type eq "score")
      {
	$code_ref = sub {$_->score;};
      }
    elsif ($type eq "length")
      {
	$code_ref = sub {$_->query_length;};
      }
    else
      {
	$code_ref = sub {$_->percent_id;};
      }
    if (@{$set->{report}->hsps()})
      {
	%hsps = map {$_->number, &$code_ref} @{$set->{report}->hsps()};
	@sorted_vals = sort{$a<=> $b} values %hsps;
	$min = $sorted_vals[0];
	$max = $sorted_vals[-1];
      }
    my $length = keys %hsps;

    return \%hsps,$max,$min,$length;
   }


sub generate_colors
  {
    my %opts = @_;
    my $max = $opts{max};
    my $min = $opts{min};
    my $length = $opts{length};
    my $scale = $opts{scale} || 'linear';
    my $val = $opts{val};
    my $color_max = $opts{color_max} || 255;
    my $color_min = $opts{color_min} || 50;
    my $flag = $opts{reverse_flag} || 0;
    my $color;
    ($color_max,$color_min) = ($color_min,$color_max) if $flag;
    return $color_max if ($val >= $max);
    return $color_min if ($val <= $min);
    if ($scale =~ /log/)
      {
        if ($val == 0) {$color = $color_max;}
        else{
          $color = log($val/$min)/log($max/$min)*($color_max-$color_min)+$color_min;
          }
      }
    else #linear
      {
	$color = ($val-$min)/($max-$min)*($color_max-$color_min)+$color_min;
      }
    return $color;
  }
	
sub get_blast_db
  {
    my $orgid = shift;
    my $org = $coge->resultset('Organism')->find($orgid);
    my @ds = $coge->get_current_datasets_for_org(org=>$orgid);
    @ds = sort {$a->id <=> $b->id }@ds;
    return unless @ds;
    my $org_name = $ds[0]->organism->name;
    my $title = $org_name ." (";
    my %vers = map {$_->version,1} @ds;
    if (keys %vers > 1)
      {
	my @chrs;
	foreach my $ds (@ds)
	  {
	    push @chrs, join (", ", map {"chr:".$_." v:".$ds->version." ds:".$ds->id} $ds->get_chromosomes);
	  }
	$title .= join (", ", @chrs);
      }
    else
      {
	$title .= "v".join ("",keys %vers)." ds:".$ds[0]->id();
      }
    $title .= ")";
    $title =~ s/(`|')//g;
    my $md5 = md5_hex($title);
    my $file = $FASTADIR."/$md5.fasta";
    my $res;
    if (-r $file)
      {
	write_log("fasta file for $org_name ($md5) exists", $cogeweb->logfile);
	$res = 1;
      }
    else
      {
	$res = generate_fasta(dslist=>\@ds, file=>$file) unless -r $file;
      }    my $blastdb = "$BLASTDBDIR/$md5";
    if (-r $blastdb.".nsq")
      {
	write_log("blastdb file for $org_name ($md5) exists", $cogeweb->logfile);
	$res = 1;
      }
    else
      {
	$res = generate_blast_db(fasta=>$file, blastdb=>$blastdb, org=>$org_name);
      }
    return $org_name, $blastdb, $file if $res;
    return 0;
    
  }


sub generate_fasta
  {
    my %opts = @_;
    my $dslist = $opts{dslist};
    my $file = $opts{file};
    $file = $FASTADIR."/$file" unless $file =~ /$FASTADIR/;
    write_log("creating fasta file.", $cogeweb->logfile);
    open (OUT, ">$file") || die "Can't open $file for writing: $!";;
    foreach my $ds (@$dslist)
      {
	foreach my $chr (sort $ds->get_chromosomes)
	  {
	    my $title =  $ds->organism->name." (v". $ds->version.") "."chromosome: $chr".", CoGe database id: ".$ds->id;
	    $title =~ s/^>+/>/;
	    write_log("adding sequence $title", $cogeweb->logfile);
	    print OUT ">".$title."\n";
	    print OUT $ds->get_genomic_sequence(chr=>$chr),"\n";
	  }
      }
    close OUT;
    write_log("Completed fasta creation", $cogeweb->logfile);
    return 1 if -r $file;
    write_log("Error with fasta file creation", $cogeweb->logfile);
    return 0;
  }

sub generate_blast_db
  {
    my %opts = @_;
    my $fasta = $opts{fasta};
    my $blastdb = $opts{blastdb};
#    my $title= $opts{title};
    my $org= $opts{org};
    my $command = $FORMATDB." -p F";
    $command .= " -i '$fasta'";
    $command .= " -t '$org'";
    $command .= " -n '$blastdb'";
    write_log("creating blastdb for $org ($blastdb)",$cogeweb->logfile);
    `$command`;
    return 1 if -r "$blastdb.nsq";
    write_log("error creating blastdb for $org ($blastdb)",$cogeweb->logfile);
    return 0;
  }

sub generate_feat_info 
  {
    my $featid = shift;
    my $checkbox = shift;
    $featid =~ s/^table_row//;
    $featid =~ s/^no_feat//;
    $featid =~ s/_\d+_\d+$//;
    my ($feat) = $coge->resultset("Feature")->find($featid);
    unless (ref($feat) =~ /Feature/i)
    {
      return "Unable to retrieve Feature object for id: $featid";
    }
    my $html = qq{<a href="#" onClick="\$('#overlap_box').slideToggle(pageObj.speed);" style="float: right;"><img src='/CoGe/picts/delete.png' width='16' height='16' border='0'></a>} unless $checkbox;
    $html .= $feat->annotation_pretty_print_html();
    return $html;
  }

sub get_hsp_info
  {
    my %opts = @_;
    my $hsp_id = $opts{num};
    my $filename = $opts{blastfile};
    $filename =~ s/$TEMPDIR//;
    $cogeweb = initialize_basefile(basename=>$filename, prog=>"CoGeBlast");
    my $dbfile = $cogeweb->sqlitefile;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");
    
    $hsp_id =~ s/^table_row// if $hsp_id =~ /table_row/;
    $hsp_id =~ s/^\d+_// if $hsp_id =~ tr/_/_/ > 1;
    
    my ($hsp_num, $pval, $pid,$psim, $score, $qgap, $sgap, $match,$qmismatch, $smismatch, $strand, $length,$qstart, $qstop,$sstart, $sstop,$qalign,$salign,$align,$qname,$sname);
    
    my $sth = $dbh->prepare(qq{SELECT * FROM hsp_data WHERE name = ?});
    
    ($hsp_num) = $hsp_id =~ /^(\d+)_\d+$/;
    $sth->execute($hsp_id) || die "unable to execute";
    while (my $info = $sth->fetchrow_hashref())
	      {
 	        $pval = $info->{eval};
 	        $pid = $info->{pid};
 	        $psim = $info->{psim};
 	        $score = $info->{score};
 	        $qgap = $info->{qgap};
 	        $sgap = $info->{sgap};
 	        $match = $info->{match};
 	        $qmismatch = $info->{qmismatch};
 	        $smismatch = $info->{smismatch};
 	        $strand = $info->{strand};
 	        $length = $info->{length};
			$qstart = $info->{qstart};
			$qstop =  $info->{qstop};
			$sstart = $info->{sstart};
			$sstop =  $info->{sstop};
 	        $qalign = $info->{qalign};
  	        $salign = $info->{salign};
	        $align = $info->{align};
	        $qname = $info->{qname};
	        $sname = $info->{sname};
	      }
    #$sth->execute($name, $pval, $pid,$psim, $score, $qgap, $sgap,$match,$qmismatch, $smismatch, $strand, $length,$qposition,$sposition,$qalign,$salign,$align);
    my $qlength = $qstop - $qstart;
    
    my ($sub_chr) = $sname =~ /chromosome: (.*?),/;
#    print STDERR "$hsp_num, $pval, $pid,$psim, $score, $qgap, $sgap, $match,$qmismatch, $smismatch, $strand, $length,$qposition,$sposition,$qalign,$salign,$align,$qname,$sname\n";
         
    my $query_name = "<pre>".$qname."</pre>";
    $query_name = wrap('','',$query_name);
    $query_name =~ s/\n/<br>/g;
    
    my $subject_name = "<pre>".$sname."</pre>";
    $subject_name = wrap('','',$subject_name);
    $subject_name =~ s/\n/<br>/g;
#     
    my @table1 = ({HSP_PID_QUERY=>$pid,
		   HSP_PSIM_QUERY=>$psim,
		   HSP_GAP_QUERY=>$qgap,
		   HSP_PID_SUB=>$pid,
		   HSP_PSIM_SUB=>$psim,
		   HSP_GAP_SUB=>$sgap,
		   HSP_MATCH_QUERY=>$match,
		   HSP_MISMATCH_QUERY=>$qmismatch,
		   HSP_MATCH_SUB=>$match,
		   HSP_MISMATCH_SUB=>$smismatch,
		   HSP_POSITION_QUERY=>$qstart."-".$qstop,
		   HSP_POSITION_SUB=>$sstart."-".$sstop,
		  });
    my @table2 = ({HSP_STRAND=>$strand,
		   HSP_EVAL=>$pval,
		   HSP_SCORE=>$score,
		   HSP_LENGTH=>$length,
		   HSP_CHR=>$sub_chr,
    		  });
     my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
     $template->param(HSP_IF=>1);
     $template->param(HSP_NUM=>$hsp_num);
     $template->param(HSP_QS=>\@table1);
     $template->param(HSP_HSP=>\@table2);

    #print STDERR join ("\n", $qalign, $align, $salign),"\n";
     my ($sub_dsid) = $sname =~ /id: (\d+)/;
     my $align_str = "";
     my $query_seq = $qalign;
     $query_seq = wrap('','',$query_seq);
     my @query = split(/\n/,$query_seq);
     $query_seq =~ s/[^atgc]//ig;
     $query_seq = wrap('','',$query_seq);
     $query_seq =~ s/\n/<br>/g;
     $query_seq =~ tr/atgc/ATGC/;
     $query_seq = qq{<pre>$query_seq</pre>};
     
     my $sub_seq = $salign;
     $sub_seq = wrap('','',$sub_seq);
     my @sub = split(/\n/, $sub_seq);
     $sub_seq =~ s/[^atgc]//ig;
     $sub_seq = wrap('','',$sub_seq);
     $sub_seq =~ s/\n/<br>/g;
     $sub_seq =~ tr/atgc/ATGC/;
     $sub_seq = qq{<pre>$sub_seq</pre>};
     

    
     my $alignment = $align;
    $alignment =~ s/ /\./g;
     $alignment = wrap('','',$alignment);
     my @align = split(/\n/,$alignment);
     
     for(my $i=0;$i<scalar(@sub);$i++)
     {
       $align_str .= $query[$i]."<br>".$align[$i]."<br>".$sub[$i]."<br>";
     }
    $align_str =~ s/<br>$//;
    $align_str =~ s/\./ /g;
    #print STDERR $align_str,"\n";
     $align_str = "<pre>$align_str</pre>";
     
     $template->param(QUERY_SEQ=>qq{<a href="#" onclick="show_seq('$query_seq','$query_name',1,'seqObj','seqObj','}.$qstart."','".$qstop.qq{')">Click for Query Sequence</a>});
     my $rc = $strand =~ /-/ ? 1 : 0;
     $template->param(SUB_SEQ=>qq{<a href="#" onclick="show_seq('$sub_seq','$subject_name',2,'$sub_dsid','$sub_chr','}.$sstart."','".$sstop.qq{','$rc')">Click for Subject Sequence</a>});
     
     $template->param(ALIGNMENT=>qq{<a href="#" onclick="show_seq('$align_str','HSP No. $hsp_num',0,0,0,0)">Click for Alignment Sequence</a>});
     
     my $html = $template->output;
     $template->param(HSP_IF=>0);
     
    #get query sequence total length
    my $query = $dbh->selectall_arrayref(qq{SELECT * FROM sequence_info WHERE type = "query" AND name = "$qname"});
    my $subject = $dbh->selectall_arrayref(qq{SELECT * FROM sequence_info WHERE type = "subject" AND name = "$sname"});
    my ($query_image, $subject_image) = generate_hit_image(hsp_num=>$hsp_num, hspdb=>$dbh, hsp_name=> $hsp_id);
    my $query_link = qq{
<div class=small>Query: $qname</div>
<img src=$query_image border=0>
};
    $query_link =~ s/$TEMPDIR/$TEMPURL/;

    my ($dsid) = $sname =~ /id: (\d+)/;
    my ($chr) = $sname =~ /chromosome: (.*?),/;
    
    my $subject_link = qq{
<div class=small>Subject: $sname</div>
<a href = 'GeLo.pl?chr=$chr&ds=$dsid&x=$sstart&z=5' target=_new border=0><img src=$subject_image border=0></a>
};
    $subject_link =~ s/$TEMPDIR/$TEMPURL/;
     return $html, $query_link, $subject_link;
   }
  
sub generate_overview_image
  {
     my %opts = @_;
     my $basename = $opts{basename};
     my $type = $opts{type};
     my $image_width = $opts{width};
     my @set = split/\n/, `ls $TEMPDIR/$basename*.blast`;
     my @reports;
     my $count = 1;
     $cogeweb = initialize_basefile(basename=>$basename,prog=>"CoGeBlast");
     foreach my $blast (@set){
       my $report = new CoGe::Accessory::blast_report({file=>$blast});
       my ($org_name) = $report->hsps->[$count-1]->subject_name =~ /^\s*(.*?)\s*\(/;
       push @reports,{report=>$report,organism=>$org_name,link=>$TEMPURL."/".$basename."-".$count.".blast",};
       $count++;
     }
     my $image_filename = $cogeweb->basefile."_".$type;
     my ($chromosome_data, $chromosome_data_large) = generate_chromosome_images(results=>\@reports,hsp_type=>$type,large_width=>$image_width,filename=>$image_filename);
     my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/CoGeBlast.tmpl');
     $template->param(CHROMOSOMES_IF=>1);
     $template->param(CHROMOSOME_LOOP=>$chromosome_data);
     my $chromosome_element = $template->output;
     $template->param(CHROMOSOMES_IF=>0);
     my $chr_large_element;
     if (scalar(@$chromosome_data_large) > 0)
     {
       $template->param(CHROMOSOMES_LARGE_IF=>1);
       $template->param(CHROMOSOME_LOOP_LARGE=>$chromosome_data_large);
       $chr_large_element = $template->output;
       $template->param(CHROMOSOMES_LARGE_IF=>0);
     }
     my $html = $chromosome_element.$chr_large_element;
     return $html;
  }
     

sub generate_hit_image
  {
    my %opts = @_;
    my $hsp_name = $opts{hsp_name};
    my $width = $opts{width} || 400;
    my $dbh = $opts{dbh};
    my $dbfile = $cogeweb->sqlitefile;
    $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") unless $dbh;
    my $sth = $dbh->prepare(qq{SELECT * FROM hsp_data WHERE name = ?});
    $sth->execute($hsp_name) || die "unable to execute";
    my $hsp = $sth->fetchrow_hashref();
    my $query = $dbh->selectall_arrayref(qq{SELECT * FROM sequence_info WHERE type = "query" AND name = "}.$hsp->{qname}.qq{"});
    my $subject = $dbh->selectall_arrayref(qq{SELECT * FROM sequence_info WHERE type = "subject" AND name = "}.$hsp->{sname}.qq{"});
    my ($hsp_num) = $hsp_name =~ /^(\d+)_\d+$/;
    #generate_query_image
    my $cq = new CoGe::Graphics::Chromosome ();
    $cq->chr_length($query->[0][3]);
    $cq->iw($width);
    $cq->draw_chromosome(1);
    $cq->draw_ruler(1);
    $cq->draw_chr_end(0);
    $cq->mag(0);
    $cq->mag_off(1);
    $cq->minor_tick_labels(0);
    $cq->major_tick_labels(1);
    $cq->draw_hi_qual(0);
    $cq->padding(2);
    $cq->set_region(start=>1, stop=>$cq->chr_length, forcefit=>1);
    $cq->feature_height(10);
    $cq->auto_zoom(0);
    $cq->feature_labels(1);
    my $strand = $hsp->{strand} =~ /-/ ? "-1" : 1;
    my $feat = CoGe::Graphics::Feature::HSP->new({start=>$hsp->{qstart}, stop=>$hsp->{qstop}, strand=>$strand, label=>$hsp_num, type=>"HSP"});
    $feat->color([255,200,0]);
    $cq->add_feature($feat);
    my ($dsid) = $hsp->{sname} =~ /id: (\d+)/;
    my ($ds) = $coge->resultset('Dataset')->resolve($dsid);
#    print STDERR $dsid,"::",$ds->name,"!!!\n";;
    my ($chr) = $hsp->{sname} =~ /chromosome: (.*?),/;
    my $len = $hsp->{sstop} - $hsp->{sstart}+1;
    my $start = $hsp->{sstart}-5000;
    $start = 1 if $start < 1;
    my $stop = $hsp->{sstop}+5000;    
    my $cs = new CoGe::Graphics::Chromosome ();
    $cs->chr_length($subject->[0][3]);
    $cs->iw($width);
    $cs->draw_chromosome(1);
    $cs->draw_ruler(1);
    $cs->draw_chr_end(0);
    $cs->mag(0);
    $cs->mag_off(1);
    $cs->minor_tick_labels(0);
    $cs->major_tick_labels(1);
    $cs->draw_hi_qual(0);
    $cs->padding(2);
    $cs->set_region(start=>$start, stop=>$stop, forcefit=>1);
    $cs->auto_zoom(0);
    $cs->feature_height(10);
    $cs->overlap_adjustment(0);
    $cs->feature_labels(1);

    $feat = CoGe::Graphics::Feature::HSP->new({start=>$hsp->{sstart}, stop=>$hsp->{sstop}, strand=>$strand, order=>2, label=>$hsp_num, type=>"HSP"});
    $feat->color([255,200,0]);
    $cs->add_feature($feat);
    
    my $graphics = new CoGe::Graphics;
    $graphics->process_features(c=>$cs, layers=>{features=>{gene=>1, cds=>1, mrna=>1, rna=>1, cns=>1}}, ds=>$ds, chr=>$chr, coge=>$coge);
    $cs->overlap_adjustment(1);
    $cq->overlap_adjustment(1);

    #find neighboring hsps
    my $sname = $hsp->{sname};
    my $qname = $hsp->{qname};
    my $statement = qq{
select * from hsp_data where
((sstart <= $stop AND
sstart >= $start) OR
(sstop <= $stop AND
sstop >= $start)) AND
sname = "$sname" AND
qname = "$qname"
};
    $sth = $dbh->prepare($statement);
    $sth->execute;
    while (my $data = $sth->fetchrow_hashref)
      {
	next if $data->{name} eq $hsp_name;
	my ($label) = $data->{name} =~ /^(\d+)_\d+$/;
	$feat = CoGe::Graphics::Feature::HSP->new({start=>$data->{sstart}, stop=>$data->{sstop}, strand=>$data->{strand}, order=>2, label=>$label, type=>"HSP"});
	$feat->color([255,0,0]);
	$cs->add_feature($feat);
	$feat = CoGe::Graphics::Feature::HSP->new({start=>$data->{qstart}, stop=>$data->{qstop}, strand=>$data->{strand}, order=>1, label=>$label, type=>"HSP"});
	$feat->color([255,0,0]);
	$cq->add_feature($feat);
      }

    my $query_file = $cogeweb->basefile.".q.".$hsp_name.".png";
    $cq->generate_png(file=>$query_file);
    my $sub_file = $cogeweb->basefile.".s.".$hsp_name.".png";
    $cs->generate_png(file=>$sub_file);
    return $query_file, $sub_file;
  }

sub overlap_feats_parse #Send to GEvo
  {
    my $accn_list = shift;
    $accn_list =~ s/^,//;
    $accn_list =~ s/,$//;
    my @list;
     my @no_feats;
    my $url = "/CoGe/GEvo.pl?";
    my ($chr,$dsid,$loc);
    my $count = 1;
    #print STDERR $url,"\n";
    foreach my $featid (split /,/,$accn_list)
    {
		if($featid=~/no/)
		{
			($dsid,$chr,$loc) = $featid =~/^\d+_(\d+)_(\w+)_(\d+)no$/;
			push @no_feats,{dsid=>$dsid,chr=>$chr,loc=>$loc};
		}
		else{
			$featid =~ s/_.*$//;
			push @list, $featid;			
		}
    }
    my %seen = ();
    @list = grep {!$seen{$_}++} @list;
    foreach my $featid( @list)
      {
      	#my ($feat) = $coge->resultset("Feature")->find($featid);
		#my ($feat_name) = sort $feat->names;#something
		$url .= "fid$count=$featid&";
		$count ++;
      }
	foreach my $no_feat (@no_feats)
	{
		$url .= "dsid$count=$no_feat->{dsid}&chr$count=$no_feat->{chr}&x$count=$no_feat->{loc}&";
		$count++
	}
    $count--;
    return ("alert",$count) if $count > 10;
    $url .= "num_seqs=$count";
    return $url;
  }
	
sub initialize_sqlite
  {
    my $dbfile = $cogeweb->sqlitefile;
#    $dbfile = $TEMPDIR."/".$dbfile unless $dbfile =~ /$TEMPDIR/;
    return if -r $dbfile;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","")  || die "cant connect to db";
    my $create = qq{
CREATE TABLE hsp_data
(
id INTEGER PRIMARY KEY AUTOINCREMENT,
name varchar(50),
eval varchar(10),
pid varchar(10),
psim varchar(10),
score varchar(10),
qgap integer(10),
sgap integer(10),
match integer(10),
qmismatch integer(10),
smismatch integer(10),
strand varchar(2),
length integer(10),
qstart integer(50),
qstop integer(50),
sstart integer(50),
sstop integer(50),
qalign text,
salign text,
align text,
qname text,
sname text
)
};
    $dbh->do($create);
     my $index = qq{
  ALTER TABLE 'hsp_data' ADD AUTO_INCREMENT 'id';
 };
#     $dbh->do($index);
     $index = qq{
 CREATE INDEX name ON hsp_data (name)
 };
     $dbh->do($index);
     $index = qq{
 CREATE INDEX qname ON hsp_data (qname)
 };
     $dbh->do($index);
     $index = qq{
 CREATE INDEX sname ON hsp_data (sname)
 };
     $dbh->do($index);
    $create = qq{
 CREATE TABLE sequence_info
 (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 name varchar(255),
 type varchar(10),
 length integer(1024)
 )
 };
     $dbh->do($create);
      $index = qq{
  CREATE INDEX seqname ON sequence_info (name)
  };
      $dbh->do($index);
      $index = qq{
  CREATE INDEX type ON sequence_info (type)
  };
      $dbh->do($index);
    system "chmod +rw $dbfile";
  }
  
sub populate_sqlite
  {
     my ($hsp,$dsid) = @_;
     my $pval = $hsp->pval;
     my $pid = $hsp->percent_id;
     my $qgap = $hsp->query_gaps;
     my $sgap = $hsp->subject_gaps;
     my $score = $hsp->score;
     my $psim = $hsp->percent_sim;
     my $length = $hsp->length;
     my $strand = $hsp->strand;
     my $match = $hsp->match;
     my $qalign = $hsp->query_alignment;
     my $salign = $hsp->subject_alignment;
     my $align = $hsp->alignment;
     my $qname = $hsp->query_name;
     my $sname = $hsp->subject_name;
     my $name = $hsp->number."_".$dsid;
    
     my $dbh = DBI->connect("dbi:SQLite:dbname=".$cogeweb->sqlitefile,"","");
     
     my $query_length = $hsp->query_stop > $hsp->query_start ? (($hsp->query_stop) - ($hsp->query_start) + 1) : (($hsp->query_start) - ($hsp->query_stop) + 1);
     my ($qstart, $qstop) = $hsp->query_stop > $hsp->query_start ? ($hsp->query_start, $hsp->query_stop) : ($hsp->query_stop, $hsp->query_start);
     my $qmismatch = $query_length - $hsp->match;
     
     my $subject_length = $hsp->subject_stop > $hsp->subject_start ? (($hsp->subject_stop) - ($hsp->subject_start) + 1) : (($hsp->subject_start) - ($hsp->subject_stop) + 1);
     my ($sstart, $sstop) = $hsp->subject_stop > $hsp->subject_start ? ($hsp->subject_start,$hsp->subject_stop) : ($hsp->subject_stop,$hsp->subject_start);
     my $smismatch = $subject_length - $hsp->match;
     
     my $statement = qq{
       INSERT INTO hsp_data (name, eval, pid, psim, score, qgap, sgap,match,qmismatch,smismatch, strand, length, qstart,qstop, sstart, sstop,qalign,salign,align,qname,sname) values ("$name", "$pval", "$pid","$psim", "$score", $qgap, $sgap, $match,$qmismatch, $smismatch, "$strand",$length,$qstart, $qstop, $sstart, $sstop,"$qalign","$salign","$align","$qname","$sname") 
     };
     print STDERR $statement unless $dbh->do($statement);

     #populate sequence_info table

     $statement = "SELECT name FROM sequence_info where name = '$qname'";
     my $val = $dbh->selectall_arrayref($statement);
     unless ($val->[0][0])
       {
	 my $qlength = $hsp->query_length;
	 $statement = qq{
INSERT INTO sequence_info (name, type, length) values ("$qname","query","$qlength")
};
	 print STDERR $statement unless $dbh->do($statement);
       }
     $statement = "SELECT name FROM sequence_info where name = '$sname'";
     $val = $dbh->selectall_arrayref($statement);
     unless ($val->[0][0])
       {
	 my $slength = $hsp->subject_length;
	 $statement = qq{
INSERT INTO sequence_info (name, type, length) values ("$sname","subject","$slength")
};
	 print STDERR $statement unless $dbh->do($statement);
       }
#     $statement = "SELECT * from sequence_info";
#     my $sth = $dbh->prepare($statement);
#     $sth->execute;
#     while (my $row = $sth->fetchrow_arrayref)
#       {
#	 print STDERR join ("\t", @$row),"\n";
#       }
   }
  
sub get_nearby_feats
  {
    my %opts = @_;
#    print STDERR Dumper \%opts;
    my $hsp_id = $opts{num};
    my $filename = $opts{basefile};
    $cogeweb = initialize_basefile(basename=>$filename, prog=>"CoGeBlast");
    my $dbh = DBI->connect("dbi:SQLite:dbname=".$cogeweb->sqlitefile,"","");
    $hsp_id =~ s/^table_row// if $hsp_id =~ /table_row/;
    $hsp_id =~ s/^\d+_// if $hsp_id =~ tr/_/_/ > 1;
    
    my $name;
    #my $checkbox = " ";
    my $distance = ">250";
    my $sth = $dbh->prepare(qq{SELECT * FROM hsp_data WHERE name = ?});
    my ($sstart, $sstop,$sname);
    my ($hsp_num,$dsid) = $hsp_id =~ /^(\d+)_(\d+)$/;
    $sth->execute($hsp_id) || die "unable to execute";
    while (my $info = $sth->fetchrow_hashref())
    {
		$sstart=$info->{sstart};
		$sstop = $info->{sstop};
		$sname = $info->{sname};
    }
	my ($start,$stop) = ($sstart,$sstop);
	my ($chr) = $sname =~ /chromosome: (.*?),/;
	my @feat;
	my $count = 1;
	until(@feat)
	{
	  $sstart = ($sstart - 1000*$count) >= 0 ? ($sstart - 1000*$count) : 0;
	  $sstop +=1000*$count;
	  @feat = $coge->get_features_in_region(start=>$sstart, 
						stop=>$sstop,
						chr=>$chr, 
						dataset_id=>$dsid,
					       );
	  last if ($sstop - $sstart) > 256000;
	  $count *= 4;
	}
	my $html = qq{<a href="#" onClick="\$('#overlap_box').slideToggle(pageObj.speed);" style="float: right;"><img src='/CoGe/picts/delete.png' width='16' height='16' border='0'></a>};
	my @feat_low;
	my @feat_high;
	my $closest_feat;
	if (@feat) 
	{
	  my %seen;
	  grep { ! $seen{lc($_)} ++ } map {$_->type->name} @feat;
	  my $search_type = "gene" if $seen{gene};
	  $search_type = "cds" if !$search_type && $seen{cds};
	  $search_type = "rna" unless $search_type;
	  foreach my $feature (@feat)
	  {
	      next unless $feature->type->name =~ /$search_type/i;
	      next unless ref($feature) =~ /Feature/i;
	      if ($feature->stop < $start) {
			push @feat_low,$feature;
	      }
	      else {
			push @feat_high,$feature;
	      }
	  }
	  unless(@feat_low or @feat_high)
	  {
	 	$html .= "No Features within 250 kb of HSP No. $hsp_num";
	  	return $html;
	  }
	  my ($feat_low) = sort {$b->stop <=> $a->stop} @feat_low if @feat_low;
	  my ($feat_high) = sort {$a->start <=> $b->start}@feat_high if @feat_high;
	
	  my $closest_feat;
	  #print STDERR $distance,"\n";
	  if($feat_low and $feat_high) 
	  {
	 	 $closest_feat = ($start - $feat_low->stop) < ($feat_high->start - $stop) ? $feat_low : $feat_high;
	 	 $distance = ($start - $feat_low->stop) < ($feat_high->start - $stop) ? ($start - $feat_low->stop)."!" : ($feat_high->start - $stop);
	  }
	  elsif($feat_high)
	  {
	  	$closest_feat = $feat_high;
		$distance = ($feat_high->start - $stop);
	  }
	  else
	  {
	 	 $closest_feat = $feat_low;
	 	 $distance = ($start - $feat_low->stop)."!";
	  }
	  #print STDERR $distance,"\n";
	  my $upstream = $distance =~ s/!$//;
	
	  my $tmp_dist = $distance;
	  my $val = $closest_feat->id."_".$hsp_id;
	  if ($distance >= 1000) 
	  {
		$distance = $distance / 1000;
	  	$distance .= " kb";
	  }
	  else {
		$distance .= " bp";
	  }
	  #print STDERR $distance,"\n";
	  $distance .= $upstream ? " upstream" : " downstream";
	  $html .= "Feature Closest to HSP No. $hsp_num: <br><br>";
	  $html .= $closest_feat->annotation_pretty_print_html();
	  ($name) = sort $closest_feat->names;
	  $name = qq{<a href="#" onclick=update_info_box('no_feat}.$closest_feat->id."_".$hsp_num."_".$dsid."')>$name</a>";
	  #$checkbox = "<input type=checkbox name='nofeat_checkbox' value='".$closest_feat->id."_".$hsp_num."_".$dsid."'  id='nofeat_checkbox".$closest_feat->id."_".$hsp_num."_".$dsid."'>";
	  $html .= "<font class=\"title4\">Distance from HSP:</font> <font class=\"data\">$distance</font>";
	  $distance = $tmp_dist;
	  #print STDERR $distance,"\n";
	}	
	else {
	 $html .= "No Features within 250 kb of HSP No. $hsp_num";
	 $name = "None";
	}
	$distance /= 1000;
	$distance = sprintf("%.3f", $distance);
	return $html,$name,$distance;
}


sub export_fasta_file
  {
    my $accn_list = shift;
    $accn_list =~ s/^,//;
    $accn_list =~ s/,$//;
    my $url = "FastaView.pl?";
    my @list;
    foreach my $accn (split /,/,$accn_list)
    {
		next if $accn =~ /no$/;
		my ($featid) = $accn =~ m/^(\d+)_\d+_\d+$/;
		push @list,$featid;
	}
	my %seen = ();
    @list = grep {!$seen{$_}++} @list;
    foreach my $featid( @list)
    {
    	$url .= "featid=$featid&";
    }
	$url =~s/&$//;
	return $url;
  }
  
sub generate_excel_feature_file
  {
    my $accn_list = shift;
    my $filename = shift;
    $cogeweb = initialize_basefile(basename=>$filename, prog=>"CoGeBlast");
    my $dbh = DBI->connect("dbi:SQLite:dbname=".$cogeweb->sqlitefile,"","");
    my $sth = $dbh->prepare(qq{SELECT * FROM hsp_data WHERE name = ?});

    my $workbook = Spreadsheet::WriteExcel->new("$TEMPDIR/Excel_$filename.xls");
    $workbook->set_tempdir("$TEMPDIR");
    my $worksheet = $workbook->add_worksheet();
    $accn_list =~ s/^,//;
    $accn_list =~ s/,$//;
    my $i = 1;
       	 
   	 $worksheet->write(0,0,"Feature Name");
   	 $worksheet->write(0,1,"HSP No.");
   	 $worksheet->write(0,2,"E-value");
   	 $worksheet->write(0,3,"Percent ID");
   	 $worksheet->write(0,4,"Score");
   	 $worksheet->write(0,5,"Organism");
    
    foreach my $accn (split /,/,$accn_list)
    {
      next if $accn =~ /no$/;
      my ($featid,$hsp_num,$dsid) = $accn =~ m/^(\d+)_(\d+)_(\d+)$/;
   	  my ($feat) = $coge->resultset("Feature")->find($featid);
   	 
   	 my ($name) = sort $feat->names;
   	 my $org = $feat->organism->name;
   	 
   	 $sth->execute($hsp_num."_".$dsid) || die "unable to execute";
      my ($pval,$pid,$score);
      while (my $info = $sth->fetchrow_hashref())
	      {
 	        $pval = $info->{eval};
 	        $pid = $info->{pid};
 	        $score = $info->{score};
	      }
   	 
   	 $worksheet->write($i,0,"http://toxic.berkeley.edu/CoGe/FeatView.pl?accn=$name",$name);
   	 $worksheet->write($i,1,$hsp_num);
   	 $worksheet->write($i,2,$pval);
   	 $worksheet->write($i,3,$pid);
   	 $worksheet->write($i,4,$score);
   	 $worksheet->write($i,5,$org);
   	 
   	 $i++;
   	}
   	
   	$workbook->close() or die "Error closing file: $!";
   	 
   	return "tmp/Excel_$filename.xls";
  }
   	 
sub generate_tab_deliminated
  {
    my $accn_list = shift;
    my $filename = shift;
    my $cogeweb = initialize_basefile(basename=>$filename, prog=>"CoGeBlast");
    my $dbh = DBI->connect("dbi:SQLite:dbname=".$cogeweb->sqlitefile,"","");
    
    my $sth = $dbh->prepare(qq{SELECT * FROM hsp_data WHERE name = ?});

    $accn_list =~ s/^,//;
    $accn_list =~ s/,$//;
    
    my $str = "Name\tHSP No.\tE-value\tPerc ID\tScore\tOrganism\n";
    
    foreach my $accn (split /,/,$accn_list)
    {
      next if $accn =~ /no$/;
      my ($featid,$hsp_num,$dsid) = $accn =~ m/^(\d+)_(\d+)_(\d+)$/;
	 my $ds = $coge->resultset("Dataset")->find($dsid);
   	 my ($feat) = $coge->resultset("Feature")->find($featid);
   	 
   	 my ($name) = sort $feat->names;
   	 my $org = $ds->organism->name;
   	 
   	 $sth->execute($hsp_num."_".$dsid) || die "unable to execute";
      my ($pval,$pid,$score);
      while (my $info = $sth->fetchrow_hashref())
	      {
 	        $pval = $info->{eval};
 	        $pid = $info->{pid};
 	        $score = $info->{score};
	      }
   	 $str .= "$name\t$hsp_num\t$pval\t$pid\t$score\t$org\n";
   	}
	$str =~ s/\n$//;
	
	open(NEW,"> $TEMPDIR/tab_delim$filename.tabbed");
	print  NEW $str;
	close NEW;
	return "tmp/tab_delim$filename.tabbed";
  }
   	 
sub generate_feat_list
  {
    my $accn_list = shift;
    my $filename = shift;
    
    $accn_list =~ s/^,//;
    $accn_list =~ s/,$//;
    
    my $url = "FeatList.pl?";
    my @list;
    foreach my $accn (split /,/,$accn_list)
    {
		next if $accn =~ /no$/;
		my ($featid) = $accn =~ m/^(\d+)_\d+_\d+$/;
		push @list,$featid;
	}
	my %seen = ();
    @list = grep {!$seen{$_}++} @list;
    foreach my $featid( @list)
    {
    	$url .= "fid=$featid&";
    }
	$url =~s/&$//;
	return $url;
  }

sub dataset_description_for_org
  {
    my $org_id = shift;
    my ($org) = $coge->resultset('Organism')->find($org_id);
    my $html = "Current datasets for ".$org->name;
    $html .= ": ".$org->description if $org->description;
    $html .= "<table>";
    my $i = 0;
    foreach my $ds ($org->current_datasets)
      {
	my $name = $ds->name;
	$name .= ": ".$ds->description if $ds->description;
	$name = "<a href=".$ds->link." target=_new>".$name."</a>"if $ds->link;
	$name =~ s/href=/href=http:\/\// unless $name =~ /http/ || $name =~/ftp/;
	my $source = $ds->datasource->name;
	$source .= ": ".$ds->datasource->description if $ds->datasource->description;
	$source = "<a href=".$ds->datasource->link." target=_new>".$source."</a>" if $ds->datasource->link;
	$source =~ s/href=/href=http:\/\// unless $source =~ /http/;
	$html .= "<tr";
	$html .= " class='even'" if $i % 2 == 0;
	$html .= "><td>".join ("<td>", $name, $source)."\n";
	$i++;
      }
    $html.="</table>";
    return $html;
  }
      
