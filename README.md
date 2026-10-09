MAPER
=====

This software segments structural magnetic resonance images
automatically into anatomical regions using a database of segmented
images (atlases) as a knowledge base.

MAPER exemplifies ensemble machine learning to approximate solutions
to an ill-posed problem: there is no objective arbiter for drawing a
boundary between anatomical regions in the brain on an _in vivo_
image.  MAPER achieves high consistency and accuracy with
respect to manual reference segmentations.

Robustness is achieved by calculating an initial, coarse
transformation between image-derived tissue probability maps, which is
used as a starting point for registering the intensity images.
Process yields are ca. 99.5% or higher (for example when segmenting
[ADNI](http://adni.loni.usc.edu/) baseline T1-weighted images using
the [Hammers Adult Brain Atlas
Database](https://brain-development.org/brain-atlases/adult-brain-atlases/)).
Segmentation results tend to be plausible even in severe brain atrophy
and other abnormal brain configurations.


### Publication

The rationale and principle are described in detail in the following
paper.

>    Heckemann, R. A., Keihaninejad, S., Aljabar, P., Rueckert, D.,
>    Hajnal, J. V., Hammers, A., May 2010. Improving intersubject image
>    registration using tissue-class information benefits robustness
>    and accuracy of multi-atlas based anatomical
>    segmentation. NeuroImage 51 (1),
>    221-227. http://dx.doi.org/10.1016/j.neuroimage.2010.01.072

If you use this software in your own work, please acknowledge MAPER by
citing the above.

MAPER is based on earlier work on multi-atlas based segmentation:

>    Heckemann, R. A., Hajnal, J. V., Aljabar, P., Rueckert, D.,
>    Hammers, A., October 2006. Automatic anatomical brain MRI
>    segmentation combining label propagation and decision
>    fusion. NeuroImage 33 (1),
>    115-126. http://dx.doi.org/10.1016/j.neuroimage.2006.05.061
    
Since the 2010 paper, MAPER has been rewritten three times and ported
to MIRTK for the registration steps. The principal idea remains the 
same, however.


### Platform

Tested on Linux (NixOS 19.03, Ubuntu 16.04, CentOS 7) and on macOS
(Big Sur -- needs Bash updated to version 5.1.4 or higher).  Works
well with multi-core and large-scale cluster architectures, as
registering multiple atlas images to a target image is embarrassingly
parallel.


### Dependencies

* [MIRTK](https://github.com/BioMedIA/MIRTK)
* [NiftySeg](https://github.com/KCL-BMEIS/NiftySeg)

For non-niche dependencies, cf. [`default.nix`](https://github.com/soundray/maper/blob/master/default.nix).

### Instructions

Clone or download & unpack, then test with
```
cd maper && export PATH=$PWD:$PATH
mkdir ~/testrun && cd ~/testrun
run-maper-example-generate.sh
# Modify run-maper-example.sh if and as desired
bash run-maper-example.sh
```
This downloads a mini-set of atlases with seven members and runs MAPER 
with one of the atlas images as the target.

Use the following to invoke MAPER for a single image using the mini-atlas 
from the above example. The image is assumed to be a T1-weighted 3D 
skullstripped MR, ie. every non-brain voxel is set to zero 
intensity, and the image file is stored in `~/testrun/mybrain-T1w.nii.gz`:
```
mkdir MAPER-MyBrain
printf "id, mri\nMyBrain, mybrain-T1w.nii.gz\n" >target.csv
launchlist-gen -src-description mini-atlas-n7r95/source-description.csv \
               -tgt-description target.csv \
               -output-dir MAPER-MyBrain  
bash launchlist.sh
```
To parallelize the above onto seven threads, replace the last line with
```
cut -d ' ' -f 2- launchlist.sh | xargs -L 1 -P 7 maper
```

### Use with the [Hammers Adult Brain Atlas Database](https://brain-development.org/brain-atlases/adult-brain-atlases/)

Download and unpack the database in `~/atlas`. A download with the subdirectory
`Hammers-n30r95` is prepared for MAPER with
```
mkdir ~/atlas/ancillaries
atlas-ancillaries.sh ~/atlas ~/atlas/ancillaries
```
and one with the subdirectory `Hammers-n30r120` with
```
hammers-atlas-db-n30r120-ancillaries.sh ~/atlas ~/atlas/ancillaries
```
Either script downloads and unpacks the ancillary data needed for MAPER in the
given location, including the source description csv file. Point
`launchlist-gen` to this file via the `-src-description` option.

### Multithreaded registration

In addition to the parallelization approach with `xargs` noted under 
*Instructions* above, MAPER supports threaded execution of MIRTK 
commands, if MIRTK is built with TBB support. This is less 
memory-intensive than shell-level parallelization. Use the `-threads` 
option to `launchlist-gen` and `maper`.

### Parallel runs and killed jobs

Parallel `maper` jobs that write to the same output directory fuse a
target's results once, after the last of them has finished. The job that
does the fusion holds a lock directory (`fusion-semaphore-*`) and touches
its `owner` file every `MAPER_LOCK_HEARTBEAT` seconds (default 15). If
that job is killed outright (SIGKILL, power loss, an OOM kill), the lock
stays behind, but the next `maper` run that finds it quiet for longer than
`MAPER_LOCK_TIMEOUT` seconds (default 300) takes it over and carries on.
The timeout must be longer than twice the heartbeat. Normal exits and
SIGTERM release the lock themselves.

If every job of a target finished while a dead job's lock still looked
alive, nobody is left to fuse: re-run any one `maper` command of that
target after the timeout has passed (it skips what is already done).

Feedback welcome at metrimorphics@soundray.de

### Tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core) and
needs neither MIRTK nor NiftySeg: `tests/stubs` provides stand-ins that
record their calls, create the expected output files and can be made to
fail (`STUB_FAIL=mirtk:register`). The tests therefore cover `maper`'s
control flow and argument handling, not registration quality.

    bats tests/

The three Python scripts (`canonicalize-nifti.py`, `reorient2std-nifti.py`,
`centre-origin-nifti.py`) have pytest tests that build their images with
nibabel, so no data files are needed (`pip install -r tests/requirements.txt`):

    python3 -m pytest tests/

`tests/lint.sh` runs shellcheck over all shell scripts and fails on any
finding, down to style (settings in `.shellcheckrc`).

`nix flake check` builds the Nix package and checks what it installs. It also
runs a segmentation with the *installed* `maper`, with MIRTK and NiftySeg being
the stubs again, and the installed scripts that prepare an atlas database. The
package replaces `PATH` with a short list of store paths, so a command that
exists on most systems but not there (`awk`, `hostname`, ...) would otherwise
fail only on a user's machine. `nix-build default.nix` builds the same package
without flakes, with the nixpkgs revision that `flake.lock` pins.
`nix build .#container` builds the image that `build-sif` turns into an
Apptainer image.

The four checks run on GitHub Actions for every push and pull request
(`.github/workflows/tests.yml`).

#### Running the tests after a change

The shell tests need `bats` and `bc`, the Python tests need pytest, nibabel and
numpy, the lint needs shellcheck. With Nix, one command provides all of them:

    nix-shell -p bats bc shellcheck 'python3.withPackages (ps: with ps; [ pytest nibabel numpy ])'

(if Nix does not know `<nixpkgs>` on your machine, add `-I nixpkgs=flake:nixpkgs`).
In that shell, from the top of the repository:

    tests/lint.sh                 # shellcheck, a few seconds
    bats tests/                   # the shell tests, 3-4 minutes
    python3 -m pytest tests/      # the Python tests, under a minute
    nix flake check               # the Nix package and its checks

While working on one thing, run only the tests that belong to it:

    bats tests/maper.bats --filter "fusion lock"
    python3 -m pytest tests/test_centre_origin.py -k "nan"

`bats --print-output-on-failure` shows what a failing test printed.

NixOS has no `/bin/bash` and no tools in `/usr/bin`; a script or test that assumes
them fails there. On another Linux system, `tests/as-nixos.sh` runs a command in a
layout where `/usr/bin` and `/bin` hold only `env` and `sh`, without changing the
system:

    tests/as-nixos.sh bats tests/

The tools must come from the `nix-shell` above (anything in `/usr/bin` would be
hidden), and it needs `unshare` and either root or user namespaces.
A change to `maper` that adds or alters behaviour should come with a test in
`tests/maper.bats`, written first and seen to fail; the helpers `run_maper`
and `stub_calls` are in `tests/test_helper.bash`.

### Apptainer image

On an x86-64 Linux system with Nix and Apptainer installed, build a MAPER Apptainer image with reproducibly pinned dependencies:

    ./build-sif

This creates `maper.sif`. An alternative output filename can be supplied:

    ./build-sif maper-test.sif

The container contents are built from the nixpkgs revision pinned in
`flake.lock`.
