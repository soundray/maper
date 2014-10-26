#!/bin/bash

# This takes a directory, an image, and a mask, and creates a 3-class
# multispectral tissue probability map in a subdirectory (tc3) of the
# directory

maperutil=$(dirname "$0")
. "$maperutil"/maperutil.rc
. "$maperutil"/common
maperutil=$(normalpath "$maperutil")

dir=$1 ; shift
num=$1 ; shift
img=$1 ; shift
msk=$1 ; shift

td=$(tempdir)
trap 'rm -rf $td >/dev/null 2>&1' 0
trap 'cp -r $td $outdir/' 1 2 3 13 15
cd $td

outdir=$dir/tc3
test -e $outdir || mkdir $outdir || fatal "Could not create directory $outdir"
output=$outdir/$num.nii.gz

seg_maths $msk -bin maskbin.nii

# Tissue classification
seg_EM -in $img -out tc3raw.nii.gz -bc_out discard.nii.gz -nopriors 3 -mask maskbin.nii

# Generate crisp labels
# seg_maths tc3raw.nii.gz -tpmax -add maskbin.nii $crispoutput

# Get individual tc probability maps, subsample
seg_maths tc3raw.nii.gz -tp 0 -mul 254 csffull.nii.gz
resample csffull.nii.gz csf.nii.gz -size 2 2 2

seg_maths tc3raw.nii.gz -tp 1 -mul 255 gmfull.nii.gz
resample gmfull.nii.gz gm.nii.gz -size 2 2 2

seg_maths tc3raw.nii.gz -tp 2 -mul 255 wm.nii.gz
resample wm.nii.gz wm.nii.gz -size 2 2 2

# Pad CSF map
resample maskbin.nii maskres.nii.gz -size 2 2 2
dilation maskres.nii.gz maskdil.nii.gz -iterations 3
seg_maths csf.nii.gz -add maskdil.nii.gz csfpadded.nii.gz

# Combine into multispectral volume
seg_maths csfpadded.nii.gz -merge 2 4 gm.nii.gz wm.nii.gz $output

exit 0

##########################
# Alternative: FSL FAST

# fast -g -o fast brain
# fslmaths fast_pve_0 -mul 254 csf
# fslmaths fast_pve_1 -mul 255 gm
# fslmaths fast_pve_2 -mul 255 wm
# fslmaths fast_pveseg -bin maskbin
# dilation maskbin.nii.gz maskdil.nii.gz -iterations 3
# fslmaths csf -add maskdil csfpadded
# fslmerge -t $output csfpadded gm wm
