# Agent Handoff

This repo is the next-gen framework migration of the old `rfsuite`.

## Current State

- Core background systems now working in the new framework:
  - MSP transport/session handling
  - telemetry abstraction
  - sensor publication for `sim`, `msp`, `crsf/elrs`, and `sport/frsky`
  - timer
  - flight mode
  - audio callouts
  - flight CSV logging
- App/menu work has started, but is still scaffold-level.

## Important Learnings

- Ethos nested `require(...)` resolution is flaky.
  - We hit this with `telemetry.sources.sim` and `app.radios`.
  - Prefer guarded direct file loading for leaf modules when Ethos fails nested package resolution.
  - Example pattern already used in:
    - `src/rfsuite/tasks/telemetry.lua`
    - `src/rfsuite/app/app.lua`

- Root app exit needs `system.exit()`.
  - Internal teardown alone is not enough to dismiss the Ethos tool surface.
  - Old suite behavior confirmed this.

- App RAM clearing matters.
  - Framework app lifecycle was changed so app instances are disposable:
    - create on activate
    - destroy on deactivate
  - See:
    - `src/rfsuite/framework/core/init.lua`
    - `src/rfsuite/runtime.lua`

- Scheduler fairness was added because MSP/callback pressure can starve other work.
  - Critical tasks run first.
  - Normal tasks use capped round-robin scheduling.
  - See:
    - `src/rfsuite/framework/core/init.lua`
    - `src/rfsuite/runtime.lua`

- Heavy boot-time work caused `Max instructions count reached`.
  - Fixes included:
    - staggering sensor providers
    - bounding ELRS frame drain
    - deferring non-essential audio during post-connect
    - removing recursive smartfuel/smartconsumption telemetry calls

- Sensor boot behavior:
  - startup `sensor lost` muting exists
  - MSP blackbox placeholders seed `0` values before first successful MSP reply
  - ELRS needed stable CRSF sensor handle access to avoid very slow updates

## App/Menu Notes

- The current app is in `src/rfsuite/app/app.lua`.
- It now uses Ethos forms and old-suite-inspired menu sizing/icon layout.
- `src/rfsuite/app/radios.lua` was copied from the old suite to preserve screen-aware button sizing.
- The root menu tree is in:
  - `src/rfsuite/app/menu/root.lua`
  - `src/rfsuite/app/menu/menus/*.lua`

- The intended direction is:
  - keep the old visual/menu behavior
  - keep the old menu tree
  - but avoid a single huge always-loaded manifest
  - use split lazy menu registries instead

- Current app/menu state is not finished.
  - Layout/nav behavior is closer to the old suite, but not yet full parity.
  - Leaf pages are still mostly scaffold placeholders, not migrated module pages.

## Good Next Steps

- Continue app/menu parity work by comparing directly against old:
  - `src/rfsuite/app/lib/ui.lua` in the legacy repo
  - especially header title placement, nav buttons, grouped main menu layout, and focus behavior
- Move from scaffold page nodes to real page/module loading
- Keep memory discipline:
  - load only current menu/page data
  - clear page/module/icon refs on exit

## Legacy Repo Used For Reference

- `/mnt/c/github/rotorflight-lua-ethos-suite`

