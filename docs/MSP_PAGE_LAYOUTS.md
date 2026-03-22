# MSP Page Layouts

`app/lib/msp_page.lua` gives us a lightweight way to build MSP-backed pages without recreating the old `requestPage()` monolith.

## Use `rows` vs `matrix`

- Use `kind = "rows"` when each row has its own shape or a different number of controls.
- Use `kind = "matrix"` when the page is naturally tabular and the same columns repeat across multiple rows.

Good examples:

- `Autolevel`: rows are flight modes, columns are `Gain` and `Max`
- `PID Bandwidth`: rows are cutoff groups, columns are `Roll`, `Pitch`, and `Yaw`

## Width Conventions

Layout sizing is string-based:

- `"34%"` for percentages
- `"12px"` for fixed pixel values

This applies to both `rows` and `matrix` layouts for page-level sizing such as `rowLabelWidth`, `slotGap`, and `rightPadding`.

For matrix pages, label alignment is also configurable:

- `rowLabelAlign = "left" | "center" | "right"`
- `columnAlign = "left" | "center" | "right"`
- `fieldAlign = "left" | "center" | "right"`
- `fieldWidth = "50%"` or `"90px"` when the editor should be narrower than the full column
- `columnWidth = "112px"` and `columnPack = "left" | "center" | "right"` when the whole matrix should be packed instead of stretched

Typical Ethos-style usage is:

- row labels left aligned
- column headers right aligned or centered depending on the page

## Matrix Shape

A matrix page declares:

- `rows`
- `columns`
- `fields`

Each field points to a row id and column id.

```lua
layout = {
    kind = "matrix",
    rowLabelWidth = "28%",
    rowLabelAlign = "left",
    columnAlign = "right",
    columnWidth = "112px",
    columnPack = "right",
    fieldWidth = "60px",
    slotGap = "12px",
    rightPadding = "12px",
    rows = {
        {id = "gyro", t = "@i18n(app.modules.profile_pidbandwidth.name)@"},
        {id = "dterm", t = "@i18n(app.modules.profile_pidbandwidth.dterm_cutoff)@"},
        {id = "bterm", t = "@i18n(app.modules.profile_pidbandwidth.bterm_cutoff)@"}
    },
    columns = {
        {id = "roll", t = "@i18n(app.modules.profile_pidbandwidth.roll_full)@"},
        {id = "pitch", t = "@i18n(app.modules.profile_pidbandwidth.pitch_full)@"},
        {id = "yaw", t = "@i18n(app.modules.profile_pidbandwidth.yaw_full)@"}
    },
    fields = {
        {row = "gyro", column = "roll", apikey = "gyro_cutoff_0"},
        {row = "gyro", column = "pitch", apikey = "gyro_cutoff_1"},
        {row = "gyro", column = "yaw", apikey = "gyro_cutoff_2"},
        {row = "dterm", column = "roll", apikey = "dterm_cutoff_0"},
        {row = "dterm", column = "pitch", apikey = "dterm_cutoff_1"},
        {row = "dterm", column = "yaw", apikey = "dterm_cutoff_2"},
        {row = "bterm", column = "roll", apikey = "bterm_cutoff_0"},
        {row = "bterm", column = "pitch", apikey = "bterm_cutoff_1"},
        {row = "bterm", column = "yaw", apikey = "bterm_cutoff_2"}
    }
}
```

Reference implementation:

- [pidbandwidth.lua](/mnt/c/Github/ethos-app-frame-work/src/rfsuite/app/modules/profile_pidbandwidth/pidbandwidth.lua)

## Page Metadata Still Comes From MSP

The wrapper still hydrates field metadata from the MSP definition tables:

- min / max / default
- help
- suffix / unit
- prefix
- values for choice fields

That means layout stays declarative and field behavior remains definition-driven.
