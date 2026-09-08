# Diagram style

Match the slide theme: black text, white background, 20 px base, blue accents.

- Font: Helvetica or Arial, 22-28 pt in the image (it is shown at about half size). Never below 18 pt.
- Colors: fill `#eef5fb` (light blue) for normal nodes, `#edf7ee` (light green) for good/target states, `#fbeeee` (light red) for bad/error states, `#fff8e5` (yellow) for decision or highlight nodes. Borders `#1f4e79`. Edges `#333333`.
- Layout: left-to-right (`rankdir=LR`) for pipelines and processes; top-to-bottom for trees and hierarchies.
- Node shapes: `box` with `style="rounded,filled"`; `ellipse` for start/end; `diamond` for decisions; `record` for UML classes.
- Edge labels short (1-3 words). Arrowheads `normal`; dashed for optional or async.
- Output: PNG, DPI 200, at most 1600 px wide, white background, no transparent areas (PDF export turns transparency dark).
- One idea per diagram. A pipeline with more than 8 nodes becomes two diagrams.
- Charts (`plot.py`): one series in `#1f4e79`, second in `#c0392b`, third in `#27ae60`. Axis labels with units. Title left-aligned, 24 pt. Grid light gray. No 3D, no pie charts.
