#!/usr/bin/env python
# -*- coding: UTF-8 -*-

"""
I/O related functions to perform on the .qa, .dag, .maf file

A .maf file is typically generated by BLASTZ or LASTZ
see spec on http://genome.ucsc.edu/FAQ/FAQformat.html#format5

A .dag file may look like:
## alignment a3068_scaffold_1 vs. b8_1 Alignment #1  score = 102635.0 (num aligned pairs: 2053): 
a3068_scaffold_1        scaffold_1||548785||550552||scaffold_100153.1||-1||CDS||30767256||87.37 140     140     b8_1    1||427548||427811||AT1G02210||-1||CDS||20183105||87.37     172     172     1.000000e-250   50

A .qa file may look like:
####
2       2840    3       3880    1.647
2       2859    3       3867    2.560
###

A .raw file just looks like .qa file, except all cluster info (starts with '#') are ignored, and each anchor point is treated as its own cluster
"""

import math
import sys
from itertools import groupby


# copied from brentp's dag_chainer.py
CONSTANT_MATCH_SCORE=None
MAX_MATCH_SCORE=50.0

def scoringF(evalue, constant_match=CONSTANT_MATCH_SCORE, max_match=MAX_MATCH_SCORE):
    """
    This scoring function converts the BLAST E-value to a score between [0, 50]
    """
    if not constant_match is None:
        return constant_match
    if evalue == 0.0: return max_match
    matchScore = -math.log10(evalue);
    return max_match if matchScore > max_match else matchScore


def parse_line(row, log_evalue=False, precision=1, fmt="qa", self_match=False):
    """
    Return anchor point info from an input line (.qa, .raw format)
    """
    atoms = row.rstrip().split("\t")

    if fmt=="dag":
        ca, a, cb, b, evalue = atoms[0], atoms[2], atoms[4], \
                               atoms[6], atoms[8]
    else: # handle .qa or .raw fmt
        ca, a, cb, b, score = atoms
    
    if log_evalue:
        score = int(scoringF(float(evalue)))
    score = int(float(score) * precision) 
    
    a, b = int(a), int(b)
    gene1, gene2 = (ca, a), (cb, b)

    if self_match and gene1 > gene2: 
        gene1, gene2 = gene2, gene1

    return (gene1, gene2, score)


def read_maf(maf_file):
    """
    Read cluster info from .maf file
    """
    from maf_utils import get_clusters

    return get_clusters(maf_file)


def read_raw(filename, log_evalue=False, precision=1):
    """
    Read cluster info from raw anchor point lists
    """
    fp = file(filename)
    clusters = []

    for row in fp:
        if row[0]=="#": continue
        anchor = parse_line(row, log_evalue=log_evalue, precision=precision)
        clusters.append([anchor])

    return clusters


def read_clusters(filename, log_evalue=False, precision=1, fmt="qa", self_match=False):
    """
    Read cluster info from .qa and .dag file
    """
    fp = file(filename)
    clusters = [] 
    
    row = fp.readline()
    j = 1
    while row:
        if row.strip() == "": break
        row = fp.readline()
        cluster = []
        while row and row[0] != "#":
            if row.strip()== "": break
            anchor = parse_line(row, log_evalue=log_evalue, precision=precision, 
                    fmt=fmt, self_match=self_match)
            cluster.append(anchor)
            row = fp.readline()

        if len(cluster) == 0: continue
        clusters.append(cluster)

    print >>sys.stderr, "read (%d) clusters in '%s'" % \
            (len(clusters), filename)

    clusters.sort()

    return clusters


def write_clusters(filehandle, clusters):
    for cluster in clusters:
        cluster_score = sum(x[-1] for x in cluster)
        filehandle.write("###\n") 
        for gene1, gene2, score in cluster:
            # gene is (name, posn)
            filehandle.write("%s\t%d\t" % gene1 )
            filehandle.write("%s\t%d\t" % gene2 )
            filehandle.write("%d\n" % score )

    print >>sys.stderr, "write (%s) clusters to '%s'" % \
            (len(clusters), filehandle.name)


def make_range(clusters, extend=0):
    """
    Convert to interval ends from a list of anchors
    extend modifies the xmax, ymax boundary of the box, 
    which can be positive or negative
    very useful when we want to make the range as fuzzy as we specify
    """
    eclusters = [] 
    for cluster in clusters:
        xlist, ylist, scores = zip(*cluster)
        score = sum(scores)

        xchr, xmin = min(xlist) 
        xchr, xmax = max(xlist)
        ychr, ymin = min(ylist) 
        ychr, ymax = max(ylist)

        # allow fuzziness to the boundary
        xmax += extend
        ymax += extend
        # because extend can be negative values, we don't want it to be less than min
        if xmax < xmin: xmin, xmax = xmax, xmin
        if ymax < ymin: ymin, ymax = ymax, ymin
        #if xmax < xmin: xmax = xmin
        #if ymax < ymin: ymax = ymin

        eclusters.append(((xchr, xmin, xmax),\
                          (ychr, ymin, ymax), score))

    return eclusters


def make_projection(clusters):
    """
    Let the x-projection of the blocks 1..n,
    output the y-projection sequence for downstream permutation analysis,
    both lists are nested one level as we have integer sequences for many chromosomes
    """
    clusters.sort()
    x_projection, y_projection = [], []

    for i, cluster in enumerate(clusters):
        block_id = i+1
        cluster.sort()
        xlist, ylist, scores = zip(*cluster)

        xchr, xfirst = xlist[0]
        x_projection.append((xchr, xfirst, block_id))

        ychr, yfirst = ylist[0]
        ychr, ylast = ylist[-1]
        if yfirst < ylast: 
            sign = 1
        else:
            yfirst, ylast = ylast, yfirst
            sign = -1
        y_projection.append((ychr, yfirst, sign * block_id))

    y_projection.sort()

    return x_projection, y_projection 


def print_intseq(projection, filehandle):
    """
    Convert from a list of (chr, pos, signed_id) => a nested list of multichromosome
    contains signed integers
    """
    g = groupby(projection, lambda x: x[0])
    chr_list, intseq = zip(*[(chr, list(x[2] for x in blocks)) for chr, blocks in g])
    for s in intseq:
        print >>filehandle, " ".join(str(x) for x in s) + "$"

    return chr_list


def print_grimm(clusters, filehandle=sys.stdout):
    """
    GRIMM-style output, for more info, see http://nbcr.sdsc.edu/GRIMM/grimm.cgi
    """
    x_projection, y_projection = make_projection(clusters)

    print >>filehandle, ">genome X"
    chr_list = print_intseq(x_projection, filehandle)
    print >>sys.stderr, ",".join(chr_list)
    print >>filehandle, ">genome Y"
    chr_list = print_intseq(y_projection, filehandle)
    print >>sys.stderr, ",".join(chr_list)


def interval_union(intervals):
    """
    Returns total size of intervals, expect interval as (chr, left, right)
    """
    intervals.sort()

    total_len = 0
    cur_chr, cur_left, cur_right = intervals[0] # left-most interval
    for interval in intervals:
        # open a new interval if left > cur_right or chr != cur_chr
        if interval[1] > cur_right or interval[0] != cur_chr:
            total_len += cur_right - cur_left + 1
            cur_chr, cur_left, cur_right = interval
        else:
            # update cur_right
            cur_right = max(interval[2], cur_right)

    # the last one
    total_len += cur_right - cur_left + 1

    return total_len


def calc_coverage(clusters, self_match=False):
    """
    Calculates the length that's covered, for coverage statistics
    """
    eclusters = make_range(clusters)

    intervals_x = [x[0] for x in eclusters]
    intervals_y = [x[1] for x in eclusters]
    
    if self_match:
        total_len_x = interval_union(intervals_x+intervals_y)
        total_len_y = total_len_x
    else:
        total_len_x = interval_union(intervals_x)
        total_len_y = interval_union(intervals_y)

    return total_len_x, total_len_y



if __name__ == '__main__':

    from optparse import OptionParser, OptionGroup

    supported_fmts = ("qa", "dag", "maf", "raw")

    usage = "Conversion from %s to .qa format\n" % (supported_fmts,) +\
            "as required to run before quota_align.py " \
            "if input is not in .qa format\n\n" \
            "%prog [options] input output \n" \
            ".. if output not given, will write to stdout"
    parser = OptionParser(usage)

    input_group = OptionGroup(parser, "Input options")
    input_group.add_option("--format", dest="fmt",
            action="store", default="qa", choices=supported_fmts, 
            help="specify the input format, must be one of %s " % (supported_fmts,) + \
                 "[default: %default]")
    parser.add_option_group(input_group)

    output_group = OptionGroup(parser, "Output options")
    output_group.add_option("--precision", dest="precision",
            action="store", type="float", default=1,
            help="convert float scores into int(score*precision) " \
                "since quota_align only deals with integer scores "\
                "[default: no multiplier]")
    output_group.add_option("--log_evalue", dest="log_evalue",
            action="store_true", default=False,
            help="convert BLAST E-value to min(int(-log10(evalue)),%d) " % MAX_MATCH_SCORE +\
                "since quota_align only deals with integer scores "\
                "[default: no multiplier]")
    output_group.add_option("--calc_coverage", dest="calc_coverage",
            action="store_true", default=False,
            help="print the total length the clusters occupy "\
                "[default: %default]")
    output_group.add_option("--print_grimm", dest="print_grimm",
            action="store_true", default=False,
            help="print two integer sequences for GRIMM permutation analysis "\
                 "[default: %default]")
    parser.add_option_group(output_group)

    (options, args) = parser.parse_args()
    
    try:
        input_file = args[0]
        if len(args) == 2:
            cluster_file = args[1]
            fw = file(cluster_file, "w")
        else:
            fw = sys.stdout
    except:
        sys.exit(parser.print_help())

    # file format conversion
    if options.fmt=="maf":
        clusters = read_maf(input_file)
    elif options.fmt=="raw":
        clusters = read_raw(input_file, log_evalue=options.log_evalue, 
                precision=options.precision)
    else:
        clusters = read_clusters(input_file, log_evalue=options.log_evalue,
                precision=options.precision, fmt=options.fmt)

    if options.print_grimm:
        print_grimm(clusters)
        sys.exit(0)

    if options.calc_coverage:
        total_len_x, total_len_y = calc_coverage(clusters)
        print >>sys.stderr, "total length on x-axis:", total_len_x 
        print >>sys.stderr, "total length on y-axis:", total_len_y
        sys.exit(0)

    write_clusters(fw, clusters)


