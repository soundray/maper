#!/bin/bash

# This takes a directory name, an image, and a mask, and determines a
# posnorm (positional normalization) transformation.  This moves the
# centre of gravity (mass) to the grid centre and rotates the image so
# the midsagittal plane aligns approximately with the x-central grid
# slice.  The transformation is saved in .dof format in a subdirectory
# (posnorm/) of the directory.

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

outdir=$dir/posnorm
test -e $outdir || mkdir $outdir || fatal "Could not create directory $outdir"
output=$outdir/$num.dof.gz

#basedir=$1 ; shift
#subdir=$1 ; shift
#imgname=$1 ; shift

input=$img

# Functions
center() {
    # Transform (translation only) image so that the CoG ends up
    # in the grid centre
    local f=$1 ; shift
    local dofout=$1 ; shift
    
    info $f >info.txt
    
    read xdim ydim zdim <<< $(cat info.txt | grep Image.size.is | cut -d ' ' -f 4-6 | sed -e 's/.*e.*/0/')
    
    gridi=$[$xdim/2]
    gridj=$[$ydim/2]
    gridk=$[$zdim/2]
    gridl=1
    
    read x0 x1 x2 x3 y0 y1 y2 y3 z0 z1 z2 z3 t0 t1 t2 t3 <<< $(cat info.txt | grep -A 5 Image.to.world.matrix  | tail -n 4 | sed -e 's/.*e.*/0/' )
    
    gridx=$(echo $x0 '*' $gridi + $x1 '*' $gridj + $x2 '*' $gridk + $x3 '*' $gridl | $maperutil/funcs.bc )
    gridy=$(echo $y0 '*' $gridi + $y1 '*' $gridj + $y2 '*' $gridk + $y3 '*' $gridl | $maperutil/funcs.bc )
    gridz=$(echo $z0 '*' $gridi + $z1 '*' $gridj + $z2 '*' $gridk + $z3 '*' $gridl | $maperutil/funcs.bc )
    gridt=$(echo $t0 '*' $gridi + $t1 '*' $gridj + $t2 '*' $gridk + $t3 '*' $gridl | $maperutil/funcs.bc )
    
    read cogx cogy cogz <<< $(seg_stats $f -c | cut -d ' ' -f 4-6 | sed -e 's/.*e.*/0/' )
    
    trx=$(echo $gridx - $cogx | $maperutil/funcs.bc )
    try=$(echo $gridy - $cogy | $maperutil/funcs.bc )
    trz=$(echo $gridz - $cogz | $maperutil/funcs.bc )
    
    cat >oldformat.dof <<EOF
DOF: 6
0.0     0.0     $trx
0.0     0.0     $try
0.0     0.0     $trz
0.0     0.0     0
0.0     0.0     0
0.0     0.0     0
EOF

    dofimport oldformat.dof $dofout 2>dofimport.err || cat dofimport.err
}

flipreg() {
local input=$1 ; shift
local output=$1 ; shift

reflect $input reflected.nii -x
rreg2 reflected.nii $input -dofout rreg-input-reflected.dof
bisect_dof rreg-input-reflected.dof $output
}


# Get DOF that moves CoG of brain to the centre of the grid
seg_maths $msk -bin maskbin
seg_maths maskbin -mul $img masked.nii
center masked.nii center1.dof

# Subsample
resample masked.nii resampled.nii -size 2 2 2
blur resampled.nii blurred.nii 2

# Estimate the linear transformation that aligns the MSP with the grid central sagittal plane
flipreg blurred.nii mspalign.dof >flipreg.log 2>&1

dofcombine center1.dof mspalign.dof $output

exit 0
