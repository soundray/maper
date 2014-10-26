#!/bin/bash

# This takes a directory, an image, and a mask, and creates a
# one-padded version of the image (brain extracted, background 0, a
# layer of voxels valued 1 adjacent to the extracted surface) in a
# subdirectory (onepad) of the directory

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

test -e $dir/onepad || mkdir $dir/onepad || fatal "Could not create directory $dir/onepad"

seg_maths $msk -bin mskbin.nii
seg_maths $img -mul mskbin.nii brain.nii
dilation mskbin.nii dilmask.nii -iterations 3
seg_maths brain.nii -add dilmask.nii onepad.nii
convert onepad.nii $dir/onepad/$num.nii.gz -float
