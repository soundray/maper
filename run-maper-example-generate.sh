#!/bin/bash

ppath=$(realpath "$BASH_SOURCE")
pdir=$(dirname "$ppath")
pname=$(basename "$ppath")

set -e 

cat <<EOF 

This program generates a test script (run-maper-example.sh) in the
present working directory. Please edit the file and modify the
settings according to your local requirements.  Then run it with
'bash run-maper-example.sh' or (more verbose) 'bash -vx
run-maper-example.sh'

The script will download a minimal atlas database (19 MByte) to the
present working directory and run MAPER single-threaded in quicktest
mode, writing to \$PWD/test/.  It should finish in 45 minutes or
less.

For more extensive testing, consider setting \$quicktest to false and
\$threads to the number of available cores. The runtime will then be
approximately 120 minutes divided either by seven or by \$threads,
whichever is smaller.

Continue? Please enter 'y'

EOF

read reply
if [[ $reply != "y" ]] ; then echo "Not continuing" ; exit ; fi
echo

cat >run-maper-example.sh <<EOF

set -e 
### Set paths here

##nix-path-goes-here##
# export PATH=/opt/mirtk/bin:\$PATH
# export PATH=/opt/niftyseg/seg-apps:\$PATH

### Set number of parallel threads (or set MAPERTEST_XARGS environment variable instead)

threads=1

### Set \$quicktest to false to run a full test

quicktest=TRUE

########
### For basic testing, nothing needs modifying below this line
########

ppath=\$(realpath "\$BASH_SOURCE")
pdir=\$(dirname "\$ppath")
pname=\$(basename "\$ppath")


[[ \$quicktest == "FALSE" ]] || quicktestarg="-quicktest"

[[ -z \$MAPERTEST_XARGS ]] && MAPERTEST_XARGS="xargs -L 1 -P \$threads"


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
type mirtk >/dev/null 2>&1 || fatal "MIRTK not found. Please ensure mirtk binary is on executable path"
type seg_maths >/dev/null 2>&1 || fatal "NiftySeg not found. Please ensure seg_maths is on executable path"

### Download mini atlas
atlas=mini-atlas-n7r95
if [[ ! -e \$atlas.tar ]] ; then
    dlcommand="wget -O -"
    url=https://github.com/soundray/maper/releases/download/0.9.0-rc/\$atlas.tar
    # url=https://soundray.org/maper/\$atlas.tar
    type wget >/dev/null 2>&1 || dlcommand="curl -fL --output -"
    \$dlcommand \$url >\$atlas.tar || fatal "Download failed. wget or curl must be installed"
fi
[[ ! -e \$atlas.tar ]] && fatal "No tarfile found -- something went wrong"

tar xf \$atlas.tar || fatal "Atlas unpacking failed"

set -v

launchlist-gen \\
    \$quicktestarg -output-dir \$PWD/test -threads 1 \\
    -src-base \$atlas -src-description \$atlas/source-description.csv \\
    -tgt-base \$atlas -tgt-description \$atlas/test-target.csv \\
    -launchlist launchlist.sh || fatal "Launchlist not generated"

time cat launchlist.sh | cut -d ' ' -f 2- | \${MAPERTEST_XARGS:-xargs -L 1 -P 1} maper | tee maper.log

EOF

echo "Script 'run-maper-example.sh' written."
