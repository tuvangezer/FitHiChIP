#!/bin/bash

#===============
# A stand alone executable which takes input the 
# base directory containing HiC-pro generated reads
# obtained by processing HiChiP alignment files
# different sets of reads generated from HiC-pro pipeline
# are then used to infer HiChIP peaks

# author: Sourya Bhattacharyya
# Vijay-AY lab
# La Jolla Institute for Allergy and Immunology
#===============

#===============
# sample execution command for this script:
# ./PeakInferHiChIP.sh -H /home/HiCPROREADSDIR -D /home/OutPeakDir -R 'hs' -M '--nomodel --extsize 147 -q 0.01'
#===============

usage(){
cat << EOF

Options:
   	-H 	HiCProDir 			Directory containing the reads generated by HiC-pro pipeline
   	-D  OutDir				Directory containing the output set of peaks. Default: current directory
   	-R 	refGenome			Reference genome string used for MACS2. Default is 'hs' for human chromosome. For mouse, specify 'mm'
   	-M 	MACS2ParamStr		String depicting the parameters for MACS2. Default: "--nomodel --extsize 147 -q 0.01"
   	-L 	ReadLength			Length of reads for the HiC-pro generated reads. Default 75
   	
EOF
}

#==============
# default parameters
OutDir=`pwd`'/'
HiCProBasedir=""
refGenome='hs'
MACS2ParamStr='--nomodel --extsize 147 -q 0.01'
ReadLength=75
#==============

while getopts "H:D:R:M:L:" opt;
do
	case "$opt" in
		H) HiCProBasedir=$OPTARG;;
		D) OutDir=$OPTARG;;
		R) refGenome=$OPTARG;;
		M) MACS2ParamStr=$OPTARG;;
		L) ReadLength=$OPTARG;;
		\?) usage
			echo "error: unrecognized option -$OPTARG";
			exit 1
			;;
	esac
done

#===================
# verify the input parameters
#===================
if [[ -z $HiCProBasedir ]]; then
	echo 'User should provide the directory containing HiC-pro output reads - exit !!'
	exit 1
fi

if [[ $(( $ReadLength % 2 )) -eq 0 ]]; then
	halfreadlen=`expr $ReadLength / 2`
else
	t=`expr $ReadLength - 1`
	halfreadlen=`expr $t / 2`
fi

echo "ReadLength : "$ReadLength
echo "halfreadlen: "$halfreadlen

#===================
# create the output directory
#===================
mkdir -p $OutDir

macs2dir=$OutDir'/MACS2_ExtSize'
mkdir -p $macs2dir
PREFIX='out_macs2'

# file containing input reads 
# to be applied for MACS2
mergedfile=$OutDir'/MACS2_input.bed'

#=========================
# check the specified HiC-pro directory
# and read different categories of files
#=========================

# DE read
cnt=0
for f in `find $HiCProBasedir -type f -name *.DEPairs`; do
	DEReadFile=$f
	cnt=`expr $cnt + 1`
done
if [[ $cnt == 0 ]]; then
	echo 'There is no file containing DE reads - exit !!'
	exit 1
fi

# SC read
cnt=0
for f in `find $HiCProBasedir -type f -name *.SCPairs`; do
	SCReadFile=$f
	cnt=`expr $cnt + 1`
done
if [[ $cnt == 0 ]]; then
	echo 'There is no file containing SC reads - exit !!'
	exit 1
fi

# RE read
cnt=0
for f in `find $HiCProBasedir -type f -name *.REPairs`; do
	REReadFile=$f
	cnt=`expr $cnt + 1`
done
if [[ $cnt == 0 ]]; then
	echo 'There is no file containing RE reads - exit !!'
	exit 1
fi

# validpairs file
cnt=0
if [ -f $HiCProBasedir'/rawdata_allValidPairs' ]; then
	ValidReadFile=$HiCProBasedir'/rawdata_allValidPairs'
	cnt=`expr $cnt + 1`
else
	for f in `find $HiCProBasedir -type f -name *.validPairs`; do
		ValidReadFile=$f
		cnt=`expr $cnt + 1`
	done
fi
if [[ $cnt == 0 ]]; then
	echo 'There is no file containing valid pairs - exit !!'
	exit 1
fi

echo 'File containing DE reads: '$DEReadFile
echo 'File containing SC reads: '$SCReadFile
echo 'File containing RE reads: '$REReadFile
echo 'File containing valid pairs: '$ValidReadFile

# process the valid pairs file
# and write individual reads by spanning through the read length values
# first process the DE, SC, and RE pairs
awk -v l="$halfreadlen" '{print $2"\t"($3-l)"\t"($3+l)"\n"$5"\t"($6-l)"\t"($6+l)}' $DEReadFile > $mergedfile
awk -v l="$halfreadlen" '{print $2"\t"($3-l)"\t"($3+l)"\n"$5"\t"($6-l)"\t"($6+l)}' $SCReadFile >> $mergedfile
awk -v l="$halfreadlen" '{print $2"\t"($3-l)"\t"($3+l)"\n"$5"\t"($6-l)"\t"($6+l)}' $REReadFile >> $mergedfile

# then process the valid pairs file
# only CIS pairs and reads with length < 1 Kb
awk -v l="$halfreadlen" 'function abs(v) {return v < 0 ? -v : v} {if (($2==$5) && (abs($6-$3)<1000)) {print $2"\t"($3-l)"\t"($3+l)"\n"$5"\t"($6-l)"\t"($6+l)}}' $ValidReadFile >> $mergedfile

# call MACS2 for peaks (FDR threshold = 0.01)
macs2 callpeak -t ${mergedfile} -f BED -n ${PREFIX} --outdir ${macs2dir} -g $refGenome $MACS2ParamStr
