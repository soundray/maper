MAPER
=====

Multi-atlas propagation with enhanced registration as described in
Heckemann et al., Neuroimage 2010
(http://soundray.org/maper/heckemann-labelfusion-neuroimage-2006.pdf).

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


