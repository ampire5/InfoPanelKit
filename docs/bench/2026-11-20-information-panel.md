# Information panel readability

The production AppKit view was mounted in a window over a bright gradient with seven file, video and diagnostics
rows. Both widths were rendered and inspected. A long label truncates with its full text available as a tooltip.
Common technical values stay visible at 190 points.

| Width | First open (main-thread CPU, ms) | Three returns (ms) |
| --- | ---: | --- |
| 190 pt | 19.9 | 0.57, 0.07, 0.05 |
| 380 pt | 7.8 | 0.49, 0.06, 0.05 |

Apple Silicon, macOS 27.2.1, debug build. The first row includes the first AppKit panel construction in the process.
The measurement stops after layout and excludes screenshot capture. The tests exercise selection and copy, collapse,
reorder, resize and host event forwarding.
