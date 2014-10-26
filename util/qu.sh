#!/bin/bash

# Takes a command and its parameters, generates a parameter-free
# script according to the config string read from maperutil.rc
# and save it under ~/.maperutil/...

maperutil=$(dirname "$0")
. "$maperutil"/maperutil.rc
. "$maperutil"/common
maperutil=$(normalpath "$maperutil")
export pn=$0

td=$(tempdir)
trap 'rm -rf $td >/dev/null 2>&1' 0
trap 'cp -r $td $outdir/' 1 2 3 13 15

arg=$@

execdir=$HOME/.maperutil/exec
test -e $execdir || mkdir -p $execdir

c=0
case "$MAPER_ENV" in

        single)  
	execscript=$execdir/$(basename $1)-0
	while test -e $execscript ; do
	(( c += 1 ))
	execscript=$execdir/$(basename $1)-$c
	done
	echo $arg >$execscript
	;;

	multicore_shell)   
	execscript=$execdir/$(basename $1)-0
	while test -e $execscript ; do
	(( c += 1 ))
	execscript=$execdir/$(basename $1)-$c
	done
	echo $arg >$execscript
	;;

	multicore_apis)
	execscript=$execdir/$(basename $1)-0
	while test -e $execscript ; do
	(( c += 1 ))
	execscript=$execdir/$(basename $1)-$c
	done
	echo $arg >$execscript

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
