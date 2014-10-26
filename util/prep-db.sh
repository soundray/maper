#!/bin/bash
set -vx
# Takes a list of images, masks, and corresponding segmentations
# and a base directory name
# Prepares an atlas database 
# or a target set for use with MAPER

# Generates onepad images from images and brain masks
# Generates subsampled tc3s
# Generates posnorm

maperutil=$(dirname "$0")
. "$maperutil"/maperutil.rc
. "$maperutil"/common
maperutil=$(normalpath "$maperutil")

# parameters
export pn=$0
arg_images=
arg_masks=
arg_segs=none
arg_dir=

while [ $# -gt 0 ]
do
    case "$1" in
        -images)  arg_images="$2"; shift;;
	-masks)   arg_masks="$2"; shift;;
	-segs)    arg_segs="$2"; shift;;
	-dir)     arg_dir="$2"; shift;;
	--) shift; break;;
	-*)
	    echo >&2 \
		    "Usage: $0 -images filelist.txt -masks filelist.txt -segs filelist.txt -dir output-directory"
    exit 1;;
*)  break;;# terminate while loop
    esac
    shift
done

test -e "$arg_images" || fatal "Image list $arg_images not found"
test -e "$arg_masks" || fatal "Mask list $arg_masks not found"
test -e "$arg_segs" || fatal "Segmentation list $arg_segs not found"

cpsegs() {
local dir=$1 ; shift
local num=$1 ; shift ; shift ; shift
local seg=$1 ; shift
segdir=$dir/seg/
test -e $segdir || mkdir -p $segdir || fatal "Could not create $segdir"
convert $seg $segdir/$num.nii.gz
}

images=$(normalpath "$arg_images")
masks=$(normalpath "$arg_masks")
if [[ $arg_segs == "none" ]] ; then 
    skipsegs=1
else
    segs=$(normalpath "$arg_segs")
fi

test -e "$arg_dir" || mkdir -p "$arg_dir"
dir=$(normalpath "$arg_dir")

# paths irtk, nifty, temporary
: ${IRTK:=$irtk}
: ${NIFTYREG:=$niftyreg}
export PATH=$IRTK:$NIFTYREG:$PATH

td=$(tempdir)
trap 'rm -rf $td >/dev/null 2>&1' 0
trap 'cp -r $td $outdir/' 1 2 3 13 15

# TODO: there should be a sanity check here to ensure that the files
# on corresponding lines belong together

test -e $HOME/.maperutil/exec && rm -r $HOME/.maperutil/exec

paste $images $masks $segs >$td/combined.txt
cat $td/combined.txt | while read i ; do 
    (( c += 1 ))
    $maperutil/qu.sh $maperutil/gen-onepad.sh "$dir" $c $i
    $maperutil/qu.sh $maperutil/gen-tc3.sh "$dir" $c $i
    $maperutil/qu.sh $maperutil/gen-posnorm.sh "$dir" $c $i
    if [[ -z $skipsegs ]] ; then 
	cpsegs "$dir" $c $i ; 
    fi
done

$maperutil/runq.sh ~/.maperutil/exec

# TODO: consider -- not sure if we need to copy the mask as-is, too
# TODO: consider -- crop/resize images to a common grid

exit 0
