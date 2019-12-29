#!/bin/bash

ppath=$(realpath "$BASH_SOURCE")
pdir=$(dirname "$ppath")
pname=$(basename "$ppath")

set -e 

. "$pdir"/generic-functions

usage() {
cat <<EOF

hammers_mith-ancillaries.sh - Prepare atlas database downloaded from 
https://brain-development.org/brain-atlases/adult-brain-atlases/individual-adult-brain-atlases-new/
for MAPER.

Usage: $pname \$DOWNLOAD \$ANCILLARIES

\$DOWNLOAD is the directory path where the download from brain-development.org is stored. It should 
contain a subdirectory Hammers_mith-n30r95

\$ANCILLARIES is a directory path where the script saves the ancillaries (preprocessed versions of 
the T1-weighted images, brain masks, pre-transformation matrices, and a source description 
(src-description.csv)).

EOF
}

[[ $# -eq 2 ]] || fatal "Parameter error. "

atlasdb=$1 ; shift
[[ -d $atlasdb/Hammers_mith-n30r95 ]] || fatal "Atlas database not found in $atlasdb"

ancilldb=$1 ; shift
cd $ancilldb || fatal "Could not change directory to $ancilldb. "

mkdir -p seg/seg95 || fatal "Could not create output directories in $ancilldb. "

### Download atlas ancillaries
atlas=hammers_mith-ancillaries-n30r95
if [[ ! -e $atlas.tar ]] ; then
    dlcommand="wget -O -"
    # url=https://github.com/soundray/maper/releases/download/0.9.1-rc/$atlas.tar
    url=https://soundray.org/maper/$atlas.tar
    type wget >/dev/null 2>&1 || dlcommand="curl -fL"
    echo $dlcommand $url 
    $dlcommand $url >$atlas.tar || fatal "Download failed. wget or curl must be installed"
fi
[[ ! -e $atlas.tar ]] && fatal "No tarfile found -- something went wrong"

tar xf $atlas.tar || fatal "Atlas unpacking failed"
rm $atlas.tar

for a in {1..30} ; do 
    aa=$(printf '%02g' $a)
    cp $atlasdb/Hammers_mith-n30r95/a$aa-seg.nii.gz seg/seg95/a$a.nii.gz
done

cat >src-description.csv <<EOF
id, onepad, pretransformation, seg95
a1, onepad/a1.nii.gz, posnorm/a1.dof.gz, seg/seg95/a1.nii.gz
a2, onepad/a2.nii.gz, posnorm/a2.dof.gz, seg/seg95/a2.nii.gz
a3, onepad/a3.nii.gz, posnorm/a3.dof.gz, seg/seg95/a3.nii.gz
a4, onepad/a4.nii.gz, posnorm/a4.dof.gz, seg/seg95/a4.nii.gz
a5, onepad/a5.nii.gz, posnorm/a5.dof.gz, seg/seg95/a5.nii.gz
a6, onepad/a6.nii.gz, posnorm/a6.dof.gz, seg/seg95/a6.nii.gz
a7, onepad/a7.nii.gz, posnorm/a7.dof.gz, seg/seg95/a7.nii.gz
a8, onepad/a8.nii.gz, posnorm/a8.dof.gz, seg/seg95/a8.nii.gz
a9, onepad/a9.nii.gz, posnorm/a9.dof.gz, seg/seg95/a9.nii.gz
a10, onepad/a10.nii.gz, posnorm/a10.dof.gz, seg/seg95/a10.nii.gz
a11, onepad/a11.nii.gz, posnorm/a11.dof.gz, seg/seg95/a11.nii.gz
a12, onepad/a12.nii.gz, posnorm/a12.dof.gz, seg/seg95/a12.nii.gz
a13, onepad/a13.nii.gz, posnorm/a13.dof.gz, seg/seg95/a13.nii.gz
a14, onepad/a14.nii.gz, posnorm/a14.dof.gz, seg/seg95/a14.nii.gz
a15, onepad/a15.nii.gz, posnorm/a15.dof.gz, seg/seg95/a15.nii.gz
a16, onepad/a16.nii.gz, posnorm/a16.dof.gz, seg/seg95/a16.nii.gz
a17, onepad/a17.nii.gz, posnorm/a17.dof.gz, seg/seg95/a17.nii.gz
a18, onepad/a18.nii.gz, posnorm/a18.dof.gz, seg/seg95/a18.nii.gz
a19, onepad/a19.nii.gz, posnorm/a19.dof.gz, seg/seg95/a19.nii.gz
a20, onepad/a20.nii.gz, posnorm/a20.dof.gz, seg/seg95/a20.nii.gz
a21, onepad/a21.nii.gz, posnorm/a21.dof.gz, seg/seg95/a21.nii.gz
a22, onepad/a22.nii.gz, posnorm/a22.dof.gz, seg/seg95/a22.nii.gz
a23, onepad/a23.nii.gz, posnorm/a23.dof.gz, seg/seg95/a23.nii.gz
a24, onepad/a24.nii.gz, posnorm/a24.dof.gz, seg/seg95/a24.nii.gz
a25, onepad/a25.nii.gz, posnorm/a25.dof.gz, seg/seg95/a25.nii.gz
a26, onepad/a26.nii.gz, posnorm/a26.dof.gz, seg/seg95/a26.nii.gz
a27, onepad/a27.nii.gz, posnorm/a27.dof.gz, seg/seg95/a27.nii.gz
a28, onepad/a28.nii.gz, posnorm/a28.dof.gz, seg/seg95/a28.nii.gz
a29, onepad/a29.nii.gz, posnorm/a29.dof.gz, seg/seg95/a29.nii.gz
a30, onepad/a30.nii.gz, posnorm/a30.dof.gz, seg/seg95/a30.nii.gz
EOF

echo "Done."

