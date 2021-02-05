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
the [Hammers<sub>mith</sub> Atlas
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

Tested on Linux (NixOS 19.03, Ubuntu 16.04, CentOS 7).  Works well
with multi-core and large-scale cluster architectures, as registering
multiple atlas images to a target image is embarrassingly parallel.


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

### Use with the [Hammers<sub>mith</sub> Atlas Database](https://brain-development.org/brain-atlases/adult-brain-atlases/))

Download and unpack the atlas database in `~/atlas`, then run
```
mkdir ~/atlas/ancillaries
hammers_mith-ancillaries.sh ~/atlas ~/atlas/ancillaries
```
This will download and unpack the ancillary data needed for MAPER in the 
given location, including the source description csv file. Point 
`launchlist-gen` to this file via the `-src-description` option.

### Multithreaded registration

In addition to the parallelization approach with `xargs` noted under 
*Instructions* above, MAPER supports threaded execution of MIRTK 
commands, if MIRTK is built with TBB support. This is less 
memory-intensive than shell-level parallelization. Use the `-threads` 
option to `launchlist-gen` and `maper`.

Feedback welcome at metrimorphics@soundray.de
