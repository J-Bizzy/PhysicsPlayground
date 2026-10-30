# Circuit Workshop: three directions (Phase 2)

**Decision (2026-10-30, the owner's pick): C, the Solid Schematic.**
- **Why.** "It goes along with the 3d feel the best and how it can be seen as floating in a sense."
- **R not taken.** R, my recommendation below, was not taken. The record of why I made it stays here.
- **What the contract has to solve.** C's two weaknesses: it vanishes in Deep space, and it is the least toy-like of the three. Phase 3's contract (`docs/circuits-kit-contract.md`) answers both.

2026-10-30, on branch `redesign/circuit-kit`. Each direction is milled as the starter loop's hero set: battery, switch, bulb, their carrier and a wire. The script is a throwaway (`directions.py` in the session scratchpad), as the brief asked. It is rendered with `propsheet.py --src <direction> --bare`.

"Bare" means each direction mills its own contacts, blade and filament. Its `contract.json` sets where its wires land and how thick they are. In these renders the filament is lit with no current behind it; that is for looks only.

![The starter loop from the eye. Top: A, B, C. Bottom: today, then R](../Tools/propsheets/directions/loops-room.png)

*Top row: A, B, C. Bottom row: today's bench, then R, the recommendation.*

## A: Snap Tiles (connection first)

![A, B, C and R, leaning in](../Tools/propsheets/directions/heroes-close-room.png)

*Rows from top: A, B, C, R.*

**Silhouette.**
- Each part is a thick moulded tile, 24 × 68 mm in section with 5.5 mm fillets.
- The component stands large on top: a 42 mm cell, and a bulb that stands 9 cm off the tile.
- The contacts are brass **half-studs** cut flush with each tile's end. Two tiles snapped together complete **one round brass button** over the joint, so the joint is its own toy affordance.
- The symbol is inlaid at 1.55 times today's size, with strokes twice as thick, so it reads from the eye.

**Material and colour.**
- Satin graphite tiles, brass studs and straps (brass still means "a wire lands here"), champagne symbols and the champagne band on the + end, and an ebony knob.
- The cell carries a large + and −.
- No new hues.

**Signature: the seat.** In the storyboard (`frames-StoryA.png`):
- the parts start apart;
- the drawn tile leans into the pull over the last centimetre;
- it seats, and the two halves become one button;
- unseating, the joint strains, then pops.

**Honest because:**
- The lean is drawn only. The model's part stays where the hand is.
- The seat is today's exact alignment on release (`CircuitsAlignmentTests`).
- The strain is today's 12 mm `PressLatch` promotion, made visible.

**Weak:**
- The slide switch reads poorly on a part standing upright.
- A symbol on a vertical face is seen **edge-on** when the part stands up, as the switch does in the loop. Today's 45° chamfer exists for exactly this reason.

## B: Cabinet Apparatus (object first)

**Silhouette.**
- The components are oversized and iconic: a lantern cell with coil-spring terminals, a 12 cm Edison pear with a looped filament in a cream ceramic socket, and a knife switch with an ebony ball handle.
- They sit on a low chamfered baseboard.
- The contacts are knurled brass **binding posts**.

**Material and colour.**
- Graphite and brass, with cream ceramic and label, ebony and steel.
- No new hues.

**Signature: the throw** (`frames-StoryB.png`). The blade lifts out of the jaws, overshoots to 64° and settles at 52°. Closing, it drops back into the jaws.

**Honest only if** the model closes the circuit when the drawn blade *enters the jaws*, not at the tap. On the way down, that is about 0.1 s after the tap, which is how a real knife switch behaves. That is a timing change in the model.

**Weak:**
- The posts are still bright upright points at every end.
- Two posts coincide at a joint, so the champagne collar has to stay. Snapping reads less than in A.

## C: Solid Schematic (textbook first)

**Silhouette.** The symbol is made **of revolution**, so it reads from any side:
- The battery's long and short plates are a copper disc (+, the cell's positive electrode) and a zinc disc (−).
- The lamp is a glass sphere on the line with an ink ring for the symbol's circle. Inside, one diagonal is a glowing coil and the other a steel support.
- The switch is a brass blade between a pivot dot and a contact ring.
- The leads are glossy ink rods, the way a wire's dark jacket already says "insulated".

From the eye, the whole loop **is its own schematic**, the strongest bridge to the textbook of the three.

**Signature: the symbol is the mechanism** (`frames-StoryC.png`). Open, the switch is drawn as its symbol. Closed, the line runs straight through.

**Weak:**
- **It disappears in Deep space.** The ink lines that make it read in a bright room vanish against the dark (`loops-studio.png`).
- It is the least toy-like of the three.
- It returns to the "diagram" reading that the 2026-10-18 lab-kit decision moved away from.

## Recommendation: A, with B's knife switch (shown as R)

R is A's tiles, half-studs, cell and bulb, with B's knife switch standing on the tile (`frames-StoryR.png`). Why:
- **A answers the most audit points.**
  - The body owns the silhouette (point 2).
  - The contacts stop shouting and *become* the joint (3).
  - The symbol gains weight (4).
- **A's signature happens on every connection a wearer makes.** B's happens on one part.
- **The audit named the switch as the part that carries the rest,** and B's throw is the best switch interaction on this board. On A's tile it keeps the throw and gains the snap.
- **It is cheaper.** R's starter loop is about 26,000 triangles of parts, against about 85,000 today: 10.7k of milled parts plus 74.5k of Swift's contact spheres and rounded switch boxes, which R mills away. The electron dots are a separate Phase 3 decision.

**What Phase 3 must settle for R:**
- **The symbol** moves from the tile's front face to a 45° band along its top front edge, so it reads lying down and standing up.
- **The half-studs and straps join the carrier asset.**
  - Swift's six contact spheres retire.
  - `terminalTargetRadius` falls from 0.026 to at most 0.022 to pass the collider rule.
  - `carrierTop` moves from −0.012 to −0.006, and `carrierBottom` from −0.026 to −0.030.
- **The champagne joint collar retires.** The completed button *is* the joint.
- **The switch's commit** follows the blade into the jaws (see B), and needs a damped spring added to `RenderKit/Motion`.
- **A seat sound recipe** is added to `SoundEffects`.
- **Every body's |x| clamp is re-argued.** All three directions run straps or leads out to the contacts, which today's 0.059 rule forbids.

**Capabilities.** None of the four hero sets needs anything the model lacks.

**Not decided here:** the other seven parts, the multimeter, the turntable and the wire. Phase 4 carries them in whichever direction is chosen.
