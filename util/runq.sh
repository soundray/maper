#!/bin/bash

# This takes the name of a directory containing scripts and executes
# the scripts

maperutil=$(dirname "$0")
. "$maperutil"/maperutil.rc
. "$maperutil"/common
maperutil=$(normalpath "$maperutil")

dir=$1 ; shift

td=$(tempdir)
trap 'rm -rf $td >/dev/null 2>&1' 0
trap 'cp -r $td $outdir/' 1 2 3 13 15
cd $td

# Hack to get number of cores on Linux and Mac
# Better to set $par in maperutil.rc
: ${par:=$(grep -c ^processor /proc/cpuinfo || sysctl -n hw.ncpu || echo 1)}

# Functions 

brake() { while true ; do j=$(jobs -r | wc -l) ; test $j -le $1 &&
break ; done ; }

case "$MAPER_ENV" in

        single)  
	for i in $(ls $dir/*) ; do bash $i ; done
	;;

	multicore_shell)   
	for i in $(ls $dir/*) ; do bash $i & brake $par ; done
	;;

	multicore_apis)
	for i in $(ls $dir/*) ; do bash $i ; done
	;;

	ge)
	fatal "Grid Engine not yet implemented"

	;;

        pbs)
	fatal "Portable Batch System not yet implemented"

	;;
	*) 
	fatal "$MAPER_ENV not implemented"

	;;
esac

exit 0
