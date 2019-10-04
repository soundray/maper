MAPER
=====

This software segments structural magnetic resonance images
automatically into anatomical regions using a database of segmented
images (atlases) as a knowledge base.

MAPER exemplifies ensemble machine learning to approximate answers to
an ill-posed problem: there is no objective arbiter for drawing a
boundary between anatomical regions in the brain on an _in vivo_
image.  However, MAPER achieves high consistency and accuracy with
respect to manual reference segmentations.

Robustness is achieved by calculating an initial, coarse
transformation between image-derived tissue probability maps, which is
used as a starting point for registering the intensity images.
Process yields are ca. 99.5% (measured on ADNI baseline images).
Segmentation results are plausible even in severe brain atrophy.


### Publication

If you use this software in your own work, please acknowledge MAPER by
citing

>    Heckemann, R. A., Keihaninejad, S., Aljabar, P., Rueckert, D.,
>    Hajnal, J. V., Hammers, A., May 2010. Improving intersubject image
>    registration using tissue-class information benefits robustness
>    and accuracy of multi-atlas based anatomical
>    segmentation. NeuroImage 51 (1),
>    221-227. http://dx.doi.org/10.1016/j.neuroimage.2010.01.072


MAPER is based on earlier work on multi-atlas based segmentation:

>    Heckemann, R. A., Hajnal, J. V., Aljabar, P., Rueckert, D.,
>    Hammers, A., October 2006. Automatic anatomical brain MRI
>    segmentation combining label propagation and decision
>    fusion. NeuroImage 33 (1),
>    115-126. http://dx.doi.org/10.1016/j.neuroimage.2006.05.061
    

### Platform

Tested on Linux (NixOS 19.03, Ubuntu 16.04, CentOS 7).  Works well
with multi-core and large-scale cluster architectures, as registering
multiple atlas images to a target image is embarrassingly parallel.


### Dependencies

* MIRTK (https://github.com/BioMedIA/MIRTK)
* NiftySeg (https://github.com/KCL-BMEIS/NiftySeg)


### Instructions

Clone or download & unpack, then test with

```
cd maper && export PATH=$PWD:$PATH
mkdir ~/testrun && cd ~/testrun
run-maper-example.sh
```

Feedback welcome at metrimorphics@soundray.de


