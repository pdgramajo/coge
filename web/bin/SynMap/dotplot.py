#!/usr/bin/python
def def_parse(astr,strip_text='LOC_'):
    astr = astr.replace('\n','')
    astr = astr.replace('\r','')
    astr = astr.replace(strip_text,'')
    y = astr.split(';')
    results = {}
    for x in y:
        z = x.split('=')
        results[z[0]] = z[1]
    return results

def gff_parse(fname,name_val,gene_order=True,exclude=['M','C','Sy','Un','Pt','Mt','UNKNOWN']):
    #needs to read through a gff file and return:
    #dictionary of gene names with order values and chromosomes
    #dirctionary of lengths of chromosomes
    fh = open(fname)
    gene_dict = {}
    chr_dict = {}
    for x in fh:
        if x[0] == '#': continue
        y = x.strip().split()
        if y[2] != 'gene': continue
        myloc = (int(y[3]) + int(y[4]))/2
        def_vals = def_parse(y[-1])
        if not name_val in def_vals: continue
        myname = def_vals[name_val]
        mychr = y[0]
        mychr = mychr.replace('c','C')
        mychr = mychr.replace('Chromosome_','')
        mychr = mychr.replace('Chr','')
        mychr = mychr.replace('Bd','')
        if 'affold' in mychr: continue
        if 'uper_' in mychr: continue
        if mychr in exclude: continue
        if not mychr in chr_dict: chr_dict[mychr] = myloc
        if chr_dict[mychr] < myloc: chr_dict[mychr] = myloc
        if not mychr in gene_dict: gene_dict[mychr] = {}
        gene_dict[mychr][myloc] = myname
    clist = list(gene_dict)
    clist.sort()
    gene_add = {}
    for c in clist:
        llist = list(gene_dict[c])
        llist.sort()
        count = 0
        for l in llist:
            if gene_order:
                myadd = count
            else:
                myadd = l
            gene_add[gene_dict[c][l]] = myadd
            count += 1
        if gene_order:
            chr_dict[c] = count
    return gene_add,chr_dict

def chr_info(chr_dict,linewidth):
	start = 50
	chr_list_a = list(chr_dict)
	chr_list_b = []
	int_use = True
	for x in chr_list_a:
		try:
			int(x)
			chr_list_b.append(x)
		except:
			int_use = False
    		continue
	if len(chr_list_b) > 0:
	    chr_list_b.sort(key=int)
	else:
		chr_list_a.sort()
		chr_list_b = chr_list_a
	chr_starts = {}
	for x in chr_list_b:
		start += linewidth
		chr_starts[x] = start
		start += chr_dict[x]
	start += linewidth
	return chr_starts,start

def chr_middle(chrs,end):
	chr_list_a = list(chrs)
	chr_list_b = []
	for x in chr_list_a:
		try: 
			int(x)
			chr_list_b.append(x)
		except:
			continue
	if len(chr_list_b) > 0:
	    chr_list_b.sort(key=int)
	    chr_list = chr_list_b
	else:
		chr_list_a.sort()
		chr_list = chr_list_a
	vals = []
	for x in chr_list:
		vals.append(chrs[x])
	vals.append(end)
	results = {}
	for x in range(len(chr_list)):
		results[chr_list[x]] = (vals[x]+vals[x+1])/2
	return results

def draw_boxes(xchrs,ychrs,xend,yend,linewidth,xheader='Chr',yheader='Chr'):
    origin = [0,0]
    xstart = origin[0]
    ystart = origin[1]
    lines = s.SVG('g')
    names = s.SVG('g')
    xmiddle = chr_middle(xchrs,xend)
    ymiddle = chr_middle(ychrs,yend)
    stroke_def = "stroke-width:%ipx;stroke:#000000" % (linewidth)
    for achr in xchrs:
        xcoord = xchrs[achr]-(linewidth/float(2))
        aline = s.SVG('line',x1=xcoord,x2=xcoord,y1=ystart,y2=yend+linewidth,style=stroke_def)
        lines.append(aline)
        aname = s.SVG('text',xheader+achr,x=xmiddle[achr],y=(ystart+12),style='text-anchor:middle;text-align:center')
        names.append(aname)
    aline = s.SVG('line',x1=(xend + (linewidth/float(2))),x2=(xend+(linewidth/float(2))),y1=ystart,y2=yend+linewidth,style=stroke_def) 
    lines.append(aline)
    for achr in ychrs:
        ycoord = ychrs[achr]-(linewidth/float(2))
        aline = s.SVG('line',x1=xstart,x2=xend+linewidth,y1=ycoord,y2=ycoord,style=stroke_def)
        lines.append(aline)
        aname = s.SVG('text',yheader+achr,x=(xstart+12),y=ymiddle[achr],style='text-anchor:middle;text-align:center',transform="rotate(270,%i,%i)" % (xstart+12,ymiddle[achr]))
        names.append(aname)
    aline = s.SVG('line',x1=xstart,x2=xend+linewidth,y1=(yend+(linewidth/float(2))),y2=(yend+(linewidth/float(2))),style=stroke_def)
    lines.append(aline)
    results = s.SVG('svg')
    results.append(lines)
    results.append(names)
    return results
def define_colors(ksvalue,max_ks=1.5,iterations=1):
    color_base = [[255,0,0],[255,255,0],[0,255,0],[0,255,255],[220,0,220],[0,0,255]]
    color_points = []
    for x in range(iterations):
        color_points.extend(color_base)
    color_points.reverse()
    if ksvalue == 'undef': return 'gray'
    if ksvalue == 'NA': return 'gray'
    if float(ksvalue) >= max_ks: return 'gray'
    scale = float(ksvalue)/max_ks
    step = 1/(len(color_points)-1)
    list_ind = scale * (len(color_points)-1)
    base_val = int(list_ind)
    dist = (list_ind-base_val)
    top = color_points[int(list_ind)+1]
    bottom = color_points[int(list_ind)]
    colors = []
    for x in range(len(top)):
        colors.append(bottom[x] + ((top[x]-bottom[x])*dist))     
    return "rgb(%i,%i,%i)" % (colors[0],colors[1],colors[2])

def parse_dag_line(aline):
    myvals = aline.split('||')
    results = {}
    myvals[0] = myvals[0].replace('Bd','')
    results['chr'] = myvals[0]
    results['name'] = myvals[3]
    return results

def draw_dots(fname,xgenes,ygenes,xchrs,ychrs):
    dots = s.SVG('g')
    fh = open(fname)
    file_dict = {}
    for line in fh:
        if '#' in line: continue
        columns = line.split()
        myks = columns[0]
        if myks == 'undef': myks = '200'
        if myks == 'NA': myks = '200'
        file_dict[line] = float(myks)
    def sort_key(a_val):
        return file_dict[a_val]
    file_list = list(file_dict)
    file_list.sort(key=sort_key)
    file_list.reverse()
    for line in file_list:
        columns = line.split()
        xgene = parse_dag_line(columns[3])
        ygene = parse_dag_line(columns[7])
        if not xgene['name'] in xgenes:
            if xgene['name'] in ygenes:
                xgene,ygene=ygene,xgene
        if not xgene['name'] in xgenes: continue
        if not xgene['chr'] in xchrs: continue
        if not ygene['name'] in ygenes: continue
        if not ygene['chr'] in ychrs: continue
        ks = columns[0]
        mycolor = define_colors(ks)
        xcoord = xchrs[xgene['chr']] + xgenes[xgene['name']]
        ycoord = ychrs[ygene['chr']] + ygenes[ygene['name']]
        adot = s.SVG('circle',cx=xcoord,cy=ycoord,r=1,fill=mycolor)
        dots.append(adot)
    return dots

def rescale(adict,ascale):
    results = {}
    for x in adict:
        results[x] = adict[x]*float(ascale)
    return results

def replace_gff_parse(fname,first=True):
	fh = open(fname)
	gene_pos = {}
	chr_vals = {}
	chr_sets = {}
	for x in fh:
		if x[0] == '#': continue
		y = x.strip().split('\t')
		if first:
			this_data = y[3]
		else:
			this_data = y[7]
		z = this_data.split('||')
		myname = z[3]
		mychr = z[0]
		myorder = z[7]
		if not mychr in chr_vals: chr_vals[mychr] = []
		if not mychr in chr_sets: chr_sets[mychr] = set([])
		chr_vals[mychr].append(int(myorder))
		gene_pos[myname] = int(myorder)
		chr_sets[mychr].add(myname)
	chr_dict = {}
	for x in chr_vals:
		chr_vals[x].sort()
		chr_dict[x] = chr_vals[x][-1] - chr_vals[x][0]
		for g in chr_sets[x]:
			gene_pos[g] -= chr_vals[x][0]
	return gene_pos,chr_dict
	
import svgfig as s
import optparse
p = optparse.OptionParser(__doc__)
p.add_option('--xmax',dest="xmax", type=int,default=800,help="How wide to make the x-axis of the plot. Default 800px")
p.add_option('--ymax',dest="ymax", type=int,default=800,help="Same as xmax but for y-axis. Default 800px")
p.add_option('--dag_file',dest="dag_file", type=str,default='',help="The output file generated by SynMap which includes Ks values")
p.add_option('--xhead',dest="xhead", type=str,default='',help="Header for labels of chromosomes from the genome on x-axis")
p.add_option('--yhead',dest="yhead", type=str,default='',help="Same as x, but for the genome on y axis")
p.add_option('--flip',action="store_true",dest="flip",default=False,help="Flip which genomes is on x and y axis. (By default the genome on the left in the SynMap file is listed on the x-axis)")
p.add_option('--xonly',dest="xonly",help="Generate a dotplot using only this chromosome from the genome on the x axis. Name must be an exact match.")
p.add_option('--yonly',dest='yonly',help="Same thing but for the genome on the y axis. Name must be an exact match.")
p.add_option('--output',dest='out',type=str,default='temp',help="Where the final file is saved. '.svg' automatically postpended to file name.")
#parameters
(opts,args) = p.parse_args()

#Ks file from SynMap

#x-size y-size


#gff1 = 'Sbicolor_79_gene.gff3'
#gff2 = gff1
#gff2 = 'ZmB73_5b_FGS.gff'
dag_file = opts.dag_file
import sys
if not dag_file:
	print "No file provided"
	sys.exit(p.print_help())
import os
if not os.path.exists(dag_file):
	print "No such file %s" % dag_file
	sys.exit(p.print_help())
#dag_file = '/home/jschnable/Desktop/maize-maize.ks'
linewidth = 3
xmax = opts.xmax
ymax = opts.ymax

xgenes,xchrs = replace_gff_parse(dag_file,first=True)
ygenes,ychrs = replace_gff_parse(dag_file,first=False)
if opts.flip:
	xgenes,ygenes = ygenes,xgenes
	xchrs,ychrs = ychrs,xchrs
xchrs,xend = chr_info(xchrs,linewidth)
ychrs,yend = chr_info(ychrs,linewidth)
if xmax:
    xscale = xmax/float(xend)
else:
    xscale = 1
if ymax:
    yscale = ymax/float(yend)
elif xmax:
    yscale = xscale
else:
    yscale = 1
xend = xend*xscale
yend = yend*yscale
if opts.xonly:
	temp = {}
	for achr in xchrs:
		if achr == opts.xonly:
			temp[achr] = xchrs[achr]
	if len(temp) == 1:
		xchrs = temp
	else:
		print "%s not in the list of chromosomes" % (opts.xonly)
		sys.exit()
if opts.yonly:
	temp = {}
	for achr in ychrs:
		if achr == opts.yonly:
			temp[achr] = ychrs[achr]
	if len(temp) == 1:
		ychrs = temp
	else:
		print "%s not in the list of chromosomes" % (opts.yonly)
		sys.exit()		
		
xchrs = rescale(xchrs,xscale)
ychrs = rescale(ychrs,yscale)
xgenes = rescale(xgenes,xscale)
ygenes = rescale(ygenes,yscale)
boxes = draw_boxes(xchrs,ychrs,xend,yend,linewidth,xheader=opts.xhead,yheader=opts.yhead)
dots = draw_dots(dag_file,xgenes,ygenes,xchrs,ychrs)
myimage = s.SVG('svg')
myimage.append(dots)
myimage.append(boxes)
myimage.save(opts.out+".tmp")
fh = open(opts.out+".tmp")
fh2 = open(opts.out + '.svg','w')
for x in fh:
	if x[:4] == '<svg':
		x = """<svg
   xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmlns:cc="http://creativecommons.org/ns#"
   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   version="1.1"
   width="400"
   height="400"
   id="svg2">
  <metadata
     id="metadata56540">
    <rdf:RDF>
      <cc:Work
         rdf:about="">
        <dc:format>image/svg+xml</dc:format>
        <dc:type
           rdf:resource="http://purl.org/dc/dcmitype/StillImage" />
        <dc:title></dc:title>
      </cc:Work>
    </rdf:RDF>
  </metadata>

"""
		x2 = x.replace('height="400"','height="%i"' % (int(ymax)+20))
		x3 = x2.replace('width="400"','width="%i"' % (int(xmax)+20))
		fh2.write(x3)
	else:
		fh2.write(x)
os.remove(opts.out+".tmp")
