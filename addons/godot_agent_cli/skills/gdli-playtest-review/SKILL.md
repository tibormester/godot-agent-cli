---
name: gdli-playtest-review
description: Use when reviewing or verifying that a feature actually works in a Godot game — playtest it like a real user via screenshots and UI clicks (by @eN ref), NOT by forcing state with eval/scripts. Pairs visual proof with scene-tree truth and tells you how to find and act on UI.
---

# gdli — playtest & review (play like a user)

**Principle: practice like you play.** A feature is proven only when you reach it the way a player would —
real input through the UI — and *see* it work. So:

- **Don't cheat.** Driving state with `eval`, `node set`, or `scene load` proves your script ran, not that the
  feature works. Reach the state through gameplay/UI instead.
- **Vision models lie.** Don't trust a screenshot alone. Pair every visual check with **structural** proof from
  the scene tree (`inspect` / `inspect --diff`). Both must agree.
- **Raise confidence by removing shortcuts.** Disable the modules that let you mutate state by fiat,
  leaving `input` + `observe` (and harmless read-only `introspect`). `--disable` takes **one** module
  per call, so it's one line each:
  ```
  gdli config --disable eval
  gdli config --disable node
  gdli config --disable scene
  gdli config --disable file
  ```
  Now the only way forward is real input + reading the result. (`gdli config` shows state; `core` can't be
  disabled; `gdli config --enable <m>` restores one.)

## The loop
1. `gdli screenshot --out step.webp` — look at the current frame.
2. `gdli inspect --ui` — flat map of **visible Controls** (path → entry). Each entry carries a `ref` (`@eN`),
   `type` (the Godot class, e.g. `Button`), a screen `rect` `[x, y, w, h]`, and a `props` dict — `text` lives
   in `props` (only when the node has one). This is how you *find* what to act on (match by `type` + `props.text`,
   or pick by `rect`). A `@eN` ref is **stable** — it tracks that node for the rest of the session (survives
   reparent/rename), so you can reuse it across actions. Re-run `inspect --ui` to discover **new** UI (e.g.
   a window that just opened) or to read fresh `rect`s. If a node is gone, its ref **errors** (it won't
   silently act at (0,0)) — so a stale ref is loud, not a false pass.
3. Act through input, addressing targets by ref (no pixel math): `gdli click --ref @e4`, `gdli key I`, `gdli act inventory`.
4. Re-screenshot **and** `gdli inspect --diff` to confirm the change in both the picture and the tree.

## Finding & acting on UI
- `inspect --ui` is the map: read it to pick the right `@eN` by its `type` + `props.text` (or `rect`).
- Coordinate verbs take `--ref` in place of `x y` (the ref resolves to the Control's center): `click`/`hover`/`scroll`
  use `--ref`; `drag` uses `--ref` (from) and `--ref2` (to). Input is **game-only** (inert in the editor).
- For deeper structure, `inspect --root <path|@ref>` scopes to a subtree.

## Worked example — drag an inventory item between slots
```
gdli launch                               # game running
gdli screenshot --out 1-start.webp
gdli inspect --ui                         # find the inventory button → say it's @e3 ("Bag")
gdli act open_inventory                   # an InputMap action; or: gdli key I  /  gdli click --ref @e3
gdli screenshot --out 2-open.webp
gdli inspect --ui                         # re-read to discover the now-visible slot refs
                                          # find source slot (@e9, has the item) + target slot (@e14, empty)
gdli drag --ref @e9 --ref2 @e14           # drag from one slot's center to the other, like a player
gdli screenshot --out 3-moved.webp        # visual proof
gdli inspect --diff                       # structural proof: the diff lists the item's add/remove + prop changes
```
`--diff` snapshots the whole scene before/after the command and reports `added`/`removed`/`changed` paths
(so the moved item shows up). If the screenshot shows the move but the diff doesn't (or vice-versa), it did
**not** work — investigate, don't pass it.

## Reporting
State what you *did* (the input sequence), attach before/after screenshots, and quote the `--diff` that confirms it.
"It looks right" is not a pass; "I clicked X, dragged Y→Z, and the tree shows the item moved" is.
