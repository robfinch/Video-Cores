# gfx acccelerator
## Overview
This is a modified version of the orsoc graphics accelerator found on opencores.org
Modifications include:
* bus master width of 256-bits (my soc uses this bus width) (bus slave remains 32-bit)
* text character blitter added, extra registers added
* use of a single master read/write port, previously multiple ports were present
* ability to plot points
* separate bus slave clock and core (master) clock
* support for 24-bit RGB888 color

