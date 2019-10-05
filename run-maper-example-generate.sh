#!/bin/bash

ppath=$(realpath "$BASH_SOURCE")
pdir=$(dirname "$ppath")
pname=$(basename "$ppath")

set -e 

echo ""
echo "   This program generates run-maper-example.sh, a test script for to process provided data, in"
echo "   the present working directory. Please edit the file and modify the settings according to"
echo "   your local requirements.  Then run it with 'bash run-maper-example.sh' or (more verbose)"
echo "   'bash -vx run-maper-example.sh'"
echo ""
echo "   It downloads a minimal atlas database (19 MByte) to the present working directory"
echo "   and runs MAPER single-threaded in quicktest mode, writing to '$PWD/test/'.  It should finish in"
echo "   30 minutes or less."
echo ""
echo "   For more extensive testing, consider removing '-quicktest' from the launchlist-gen line. "
echo "   The runtime will then be approximately 120 minutes divided by the number of cores."
echo ""
echo -n "Continue? Please enter 'y' "

read reply
if [[ $reply != "y" ]] ; then echo "Not continuing" ; exit ; fi
echo

cat >run-maper-example.sh <<EOF

ppath=\$(realpath "\$BASH_SOURCE")
pdir=\$(dirname "\$ppath")
pname=\$(basename "\$ppath")

set -e 
### Set paths here

export PATH=/opt/mirtk/lib/tools:\$PATH
export PATH=/opt/niftyseg/seg-apps:\$PATH

### Set number of parallel threads (or set MAPERTEST_XARGS environment variable instead)

threads=1

[[ -z \$MAPERTEST_XARGS ]] && MAPERTEST_XARGS="xargs -L 1 -P \$threads"

### 

quicktest=TRUE

[[ -z \$quicktest ]] || quicktestarg="-quicktest"

########
### For basic testing, nothing needs modifying below this line
########

msg () {
    for msgline
    do echo -e "\$pname: \$msgline" >&2
    done
}

fatal () { msg "\$@" ; exit 1 ; }

usage() { echo \$usage ; fatal "\$@" ; }

tempdir () {
    : \${TMPDIR:="/tmp"}
    tdbase=\$TMPDIR/\$USER
    test -e \$tdbase || mkdir -p \$tdbase
    td=\$(mktemp -d \$tdbase/\$(basename \$0).XXXXXX) || fatal "Could not create temp dir in \$tdbase"
    echo \$td
}

finish () {
    [[ \$savewd -eq 1 ]] || rm -rf "\$td"
    exit
}



### Check for MAPER and dependencies
type maper >/dev/null 2>&1 || fatal "MAPER not found. Please ensure maper is on executable path"
type transform-image >/dev/null 2>&1 || fatal "MIRTK not found. Please ensure transform-image is on executable path"
type seg_maths >/dev/null 2>&1 || fatal "NiftySeg not found. Please ensure seg_maths is on executable path"

### Download mini atlas
atlas=mini-atlas-n7r95
if [[ ! -e \$atlas.tar ]] ; then
    dlcommand="wget -O -"
    url=https://github.com/soundray/maper/releases/download/0.9.0-rc/\$atlas.tar
    # url=https://soundray.org/maper/\$atlas.tar
    type wget >/dev/null 2>&1 || dlcommand="curl --output -"
    \$dlcommand \$url >\$atlas.tar || fatal "Download failed. wget or curl must be installed"
fi
[[ ! -e \$atlas.tar ]] && fatal "No tarfile found -- something went wrong"

tar xf \$atlas.tar || fatal "Atlas unpacking failed"

set -v

launchlist-gen \\
    $quicktestarg -output-dir \$PWD/test -threads \$threads \\
    -src-base \$atlas -src-description \$atlas/source-description.csv \\
    -tgt-base \$atlas -tgt-description \$atlas/test-target.csv \\
    -launchlist launchlist.sh || fatal "Launchlist not generated"

time cat launchlist.sh | cut -d ' ' -f 2- | ${MAPERTEST_XARGS:-xargs -L 1 -P 1} maper | tee maper.log

EOF

echo "Script 'run-maper-example.sh' written."
