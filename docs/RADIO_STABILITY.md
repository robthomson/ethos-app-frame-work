# Radio Stability Notes

This note captures the practical rules we learned while debugging radio-only hangs, watchdog trips, and flaky first-load behavior during page ports.

Use it as a checklist when adding or porting app pages.

## Why This Matters

The simulator is forgiving compared to real radios.

A page can appear "mostly fine" in sim and still:

- hit `Max instructions count reached` on radio
- hang the progress dialog on first load
- starve MSP traffic with unrelated background reads
- leave blank menus or partially built forms after a watchdog hit

On radio, a watchdog is effectively fatal for that run, so prevention matters more than recovery.

## Core Rules

### 1. Keep page-enter paths light

Do not do expensive work directly in page enter, menu enter, or first form build if it can be deferred.

Avoid:

- eager layout preparation before the first MSP read completes
- full form rebuilds on every reload
- repeated control mutation every wakeup
- non-essential cache pruning in page transition code

Prefer:

- a lightweight loading state first
- deferred work via callbacks
- incremental control updates once the page is built

### 2. Use the app callback queue for page work

This app has more than one callback path.

For page-local defers, prefer the app-owned callback queue:

- `node.app.callback:now(...)`
- `node.app.callback:inSeconds(...)`

Do not default to the framework callback queue for page-specific work unless there is a clear reason. Keeping app work on the app callback loop makes watchdog attribution clearer and avoids mixing page defers with unrelated framework/task callbacks.

### 3. Reload should be incremental by default

Most reloads do not need a full form rebuild.

Default behavior should be:

- perform the MSP read
- update existing controls in place
- keep the current form structure alive

Only use `reloadFull` when structure really changes, for example:

- fields appear/disappear due to API version
- field layout changes with mode/profile
- controls do not exist yet

### 4. If layout is stable, build controls before data arrives

For pages whose structure does not depend on loaded MSP values, prefer:

- build the full form immediately
- keep controls blank until real values arrive
- keep controls disabled until the page load completes
- patch values into the existing controls after the read finishes

Do not:

- seed fake or placeholder numeric values just to make the page look populated
- block form construction behind a simple MSP read when the layout is already known

In shared MSP pages, this is the preferred pattern for "fixed layout, delayed data" pages because it gives a faster UI without inventing data.

### 5. Pause MSP polling while admin is active, not sensor publishing

When the admin/app UI is active:

- stop background MSP sensor polling
- keep republishing the last known sensor values

This prevents background MSP traffic from competing with foreground page reads while still keeping sensor consumers fed with the latest cached values.

### 6. Background work and app work have separate budgets

Treat app wakeup and background wakeup as separate CPU-risk surfaces.

Even if each loop is "acceptable" on its own, both running hot can still create radio-only instability. If app UI is active, be careful not to duplicate work across both paths.

### 7. Handle bitmap subfields in shared plumbing

If an API exposes bitmap children such as `parent->bit`, support that in shared MSP plumbing rather than in page files.

The correct behavior is:

- expose bitmap children through field metadata
- read child values by extracting bits from the parent integer
- write child changes by recombining bits back into the parent integer

Do not paper over missing bitmap metadata in a page with local hardcoded dropdown tables unless it is a temporary emergency workaround.

### 8. Repeated wakeup mutation is dangerous

Page helpers that walk fields and enable/disable controls on every wakeup can be enough to trip the watchdog on radio.

Prefer:

- do nothing until the page is loaded and controls exist
- reapply UI state only when a small signature changes
- examples: mode, profile, voltage source, form build count

### 9. Loader and error paths must be lightweight

Progress dialogs and error rendering should not depend on the heavy success path finishing perfectly.

Prefer:

- close loaders as soon as the required step is complete
- keep error rendering simple
- show full error text in a full-width area when possible

If the page fails, the user should still be able to see the real error without another crash.

## Porting Checklist

Before merging a new page or port:

1. Does first load do only the minimum needed work?
2. Are deferred page tasks using `app.callback` instead of the framework callback queue?
3. Does reload update values in place unless `reloadFull` is truly required?
4. If the layout is stable, does the page build controls immediately and wait for real data instead of showing fake defaults?
5. Are background MSP reads paused while the app is active?
6. Are cached sensor values still republished while polling is paused?
7. Are any bitmap child fields handled centrally instead of in the page?
8. Does any wakeup helper mutate controls every frame? If yes, can it become signature-driven?
9. Can error text be fully seen on-device?
10. Has the page been tested from a fresh app start, not just after reopening?

## Symptoms And Likely Causes

### First load fails, second load works

Usually means too much synchronous work is happening during initial page enter, API preparation, or first form build.

### Progress loader hangs

Often means loader close depends on a later rebuild or callback that never arrives after an earlier failure or watchdog.

### Dropdown renders but values are empty

Often means metadata was not carried through from API definitions to the built control. Bitmap child fields are a common cause.

### Simulator works, radio hangs

Usually means the callback/build/wakeup path is too close to the radio instruction budget.

### Unrelated MSP IDs appear during page load

Often means background MSP sensor polling is competing with the page's own foreground read.

## Practical Guidance For Future Ports

- Start with the lightest possible loading path.
- If the page layout is fixed, prebuild the controls and patch values in after load.
- Blank disabled controls are better than fake defaults.
- Add page-specific logic only after the base page is stable.
- If a page needs custom wakeup behavior, gate it behind "loaded and controls exist".
- If a field type feels special-case, first ask whether the API/factory layer should own it.
- When debugging watchdogs, trust the radio more than the simulator.

## Files Worth Reviewing

These areas were central to the issues fixed so far:

- `src/rfsuite/app/lib/msp_page.lua`
- `src/rfsuite/app/controllers/form_host.lua`
- `src/rfsuite/app/controllers/page_host.lua`
- `src/rfsuite/runtime.lua`
- `src/rfsuite/tasks/sensors.lua`
- `src/rfsuite/sensors/providers/msp.lua`
- `src/rfsuite/mspapi/factory.lua`
- `src/rfsuite/app/modules/profile_governor/lib.lua`

