---
name: gdli-playtest-review
description: Use when reviewing or verifying that a feature actually works in a Godot game â€” playtest it like a real user via screenshots and UI clicks (by @eN ref), NOT by forcing state with eval/scripts. Pairs visual proof with scene-tree truth and tells you how to find and act on UI.
---

# gdli â€” playtest & review (play like a user)

**Principle: practice like you play.** A feature is proven only when you reach it the way a player would â€”
real input through the UI â€” and *see* it work. So:

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
1. `gdli screenshot --out step.webp` â€” look at the current frame.
2. `gdli inspect --ui` â€” flat map of **visible Controls** (path â†’ entry). Each entry carries a `ref` (`@eN`),
   `type` (the Godot class, e.g. `Button`), a screen `rect` `[x, y, w, h]`, and a `props` dict â€” `text` lives
   in `props` (only when the node has one). This is how you *find* what to act on (match by `type` + `props.text`,
   or pick by `rect`). A `@eN` ref is **stable** â€” it tracks that node for the rest of the session (survives
   reparent/rename), so you can reuse it across actions. Re-run `inspect --ui` to discover **new** UI (e.g.
   a window that just opened) or to read fresh `rect`s. If a node is gone, its ref **errors** (it won't
   silently act at (0,0)) â€” so a stale ref is loud, not a false pass.
3. Mark the baseline when you need structural proof over multiple commands: `gdli inspect --mark before`.
4. Act through input, addressing targets by ref (no pixel math): `gdli click --ref '@e4'`, `gdli key I`, or a game-specific action such as `gdli act gdli_demo_open_inventory`.
5. Re-screenshot **and** compare against the baseline (`gdli inspect --diff before`) to confirm the change in both the picture and the tree.

If a subtree changes constantly but is not part of the feature under review, add a process-global ignore once: `gdli ignore add TerminalPanel`. This is better than repeating `--ignore` and keeps expensive transcript/UI churn out of every diff.

## Finding & acting on UI
- `inspect --ui` is the map: read it to pick the right `@eN` by its `type` + `props.text` (or `rect`).
- Coordinate verbs take `--ref` in place of `x y` (the ref resolves to the Control's center): `click`/`hover`/`scroll`
  use `--ref`; `drag` uses `--ref` (from) and `--ref2` (to), `drag --hold` leaves the button down, and `release` drops it. Input is **game-only** (inert in the editor).
- For deeper structure, `inspect --root <path|@ref>` scopes to a subtree.

## Worked example â€” demo combat and inventory proof
The repo demo scene is a small arena game with a transparent terminal overlay. Use the same pattern in
real games: discover refs, act through UI/input, screenshot, then compare structure. Press `?` in the
demo terminal for the longer documentation-derived walkthrough, but keep review proof input-driven.

![gdli demo console](../../../gdli_plugin_example/docs/assets/demo-console.png)

```
gdli launch --scene res://addons/gdli_plugin_example/demo/main.tscn
gdli ignore add TerminalPanel
gdli screenshot --out addons/gdli_plugin_example/docs/assets/demo-console.png
gdli key D --hold --ticks 8               # move into sword range
gdli key D --release
gdli click 752 286 --ticks 1              # first hit shrinks HP
gdli click 752 286 --ticks 2              # second hit drops Loot1
gdli inspect --mark before_loot
gdli drag --ref Arena/Loot/Loot1 --ref2 Hud/InventoryPanel/Margin/Rows/Slots/Slot1 --ticks 2
gdli drag --ref Hud/InventoryPanel/Margin/Rows/Slots/Slot1 700 230 --hold --diff --ticks 1
gdli release 700 230 --ticks 1
gdli screenshot --out addons/gdli_plugin_example/docs/assets/demo-diff-workflow.png
gdli inspect --diff before_loot
```

![gdli inventory diff proof](../../../gdli_plugin_example/docs/assets/demo-diff-workflow.png)

`--diff` reports the world loot removal and inventory slot text changes. If the screenshot shows the move
but the diff does not, or the diff shows a change that is not visible, investigate before passing the review.

## Reporting
State what you *did* (the input sequence), attach before/after screenshots, and quote the `--diff` that confirms it.
"It looks right" is not a pass; "I clicked X, dragged Yâ†’Z, and the tree shows the item moved" is.
