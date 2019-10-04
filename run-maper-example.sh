#!/bin/bash

ppath=$(realpath "$BASH_SOURCE")
pdir=$(dirname "$ppath")
pname=$(basename "$ppath")

set -e 

. "$pdir"/generic-functions
. "$pdir"/common

echo ""
echo "   This is a test to see if MAPER has been set up correctly."
echo ""
echo "   It downloads a minimal atlas database (19 MByte) to the present working directory"
echo "   and runs MAPER single-threaded in quicktest mode, writing to $PWD/test/.  It should finish in"
echo "   30 minutes or less."
echo ""
echo "   For more extensive testing, consider removing \"-quicktest\" from the launchlist-gen line and"
echo "   change the xargs \"-P 1\" argument to reflect the number of available cores. The runtime will"
echo "   then be approximately 120 minutes divided by the number of cores."
echo ""
echo -n "Continue? Please enter \'yes\' "

read reply
[[ $reply != "yes" ]] && fatal "Not continuing"
echo

### Check for MAPER and dependencies
which maper >/dev/null 2>&1 || fatal "MAPER not found. Please ensure maper is on executable path"
which transform-image >/dev/null 2>&1 || fatal "MIRTK not found. Please ensure transform-image is on executable path"
which seg_maths >/dev/null 2>&1 || fatal "NiftySeg not found. Please ensure seg_maths is on executable path"

### Download mini atlas
atlas=mini-atlas-n7r95
if [[ ! -e $atlas.tar ]] ; then
    dlcommand="wget -O -"
    which wget >/dev/null 2>&1 || dlcommand="curl --output -"
    $dlcommand https://soundray.org/maper/$atlas.tar >$atlas.tar || fatal "Download failed. wget or curl must be installed"
fi
[[ ! -e $atlas.tar ]] && fatal "No tarfile found -- something went wrong"

tar xf $atlas.tar || fatal "Atlas unpacking failed"

set -v

launchlist-gen \
    -quicktest -output-dir $PWD/test \
    -src-base $atlas -src-description $atlas/source-description.csv \
    -tgt-base $atlas -tgt-description $atlas/test-target.csv \
    -launchlist launchlist.sh || fatal "Launchlist not generated"

time cat launchlist.sh | cut -d ' ' -f 2- | xargs -L 1 -P 1 maper | tee maper.log
