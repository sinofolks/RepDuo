---
name: GreenBody Calibration
description: Visual specification of the local calibration report as implemented.
colors:
  page: "#121514"
  surface: "#1b201e"
  surface-raised: "#252b28"
  stage: "#090b0a"
  ink: "#f1f4f2"
  muted: "#b3beb7"
  line: "#3a433e"
  accent: "#bddc69"
  accent-ink: "#1c2708"
  cyan: "#72dce9"
  orange: "#ffb476"
  warning: "#f4d593"
  warning-bg: "#30291b"
  warning-border: "#625336"
  danger: "#ffb0a7"
  danger-bg: "#332320"
  danger-border: "#6e4641"
  control-hover: "#303a33"
  control-hover-border: "#6b7b70"
  control-active: "#3a483d"
  history-current: "#253020"
  history-link-hover: "#29342b"
typography:
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif'
    fontSize: "14px"
    lineHeight: 1.5
  title:
    fontSize: "1.5rem"
    fontWeight: 650
    lineHeight: 1.25
    letterSpacing: "-.025em"
  heading:
    fontSize: "1.13rem"
    fontWeight: 620
    lineHeight: 1.3
  table:
    fontSize: ".86rem"
  table-heading:
    fontSize: ".86rem"
    fontWeight: 550
  status:
    fontSize: ".78rem"
  mono:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: ".85rem"
  index:
    fontSize: "1.5rem"
    fontWeight: 650
    lineHeight: 1.2
rounded:
  status: "5px"
  control: "7px"
  warning: "8px"
  radius: "12px"
spacing:
  inline-tight: "6px"
  inline: "9px"
  control-inset: "12px"
  surface-inset: "16px"
  space: "20px"
  detail-gap: "28px"
  section: "32px"
components:
  button:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "7px 12px"
  button-hover:
    backgroundColor: "{colors.control-hover}"
  button-active:
    backgroundColor: "{colors.control-active}"
  select:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "7px 32px 7px 11px"
  select-hover:
    backgroundColor: "{colors.control-hover}"
  inspection:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.radius}"
  warning:
    backgroundColor: "{colors.warning-bg}"
    textColor: "{colors.warning}"
    rounded: "{rounded.warning}"
    padding: "12px 15px"
  warning-invalid:
    backgroundColor: "{colors.danger-bg}"
    textColor: "{colors.danger}"
  status:
    textColor: "{colors.muted}"
    typography: "{typography.status}"
    rounded: "{rounded.status}"
    padding: "3px 7px"
  status-provisional:
    backgroundColor: "{colors.warning-bg}"
    textColor: "{colors.warning}"
  status-invalid:
    backgroundColor: "{colors.danger-bg}"
    textColor: "{colors.danger}"
  history-run-link:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "3px 5px"
  history-run-link-hover:
    backgroundColor: "{colors.history-link-hover}"
    textColor: "{colors.accent}"
---

# Design System: GreenBody Calibration

## Overview

This specification is scoped to the standalone local report in this directory. It records the shipped implementation; it does not define RepDuo's iOS identity or a project-wide visual language.

Evidence: the inline CSS, semantic HTML and state handlers in `report-template.html`, the generated `report.html`, and the approved scope in `PRODUCT.md` and `report-brief.md`. On 2026-09-13, the generated report matched the template exactly apart from its embedded JSON payload. This documentation is a source inspection, not another browser or visual review. The payload contained five complete, provisional records; other states below are source-defined behavior.

The YAML frontmatter is the normative token layer. Descriptive component keys identify observed rules; they do not introduce new CSS variables. No metaphor, synthesized tonal ramp, unimplemented component or new visual commitment is specified.

## Colors

### Primary

The green `accent` colors native range and checkbox controls, links, visible focus outlines, selected text backgrounds and positive history differences. `accent-ink` is the selected-text and skip-link foreground.

### Secondary

`cyan` identifies reference contours and points. `orange` identifies candidate contours and points and negative history differences. The viewport has a written reference/candidate legend, so these roles are not communicated by color alone.

`warning`, `warning-bg` and `warning-border` are shared by the report warning and provisional status. Invalid records use `danger`, `danger-bg` and `danger-border`, together with explicit invalid text.

### Neutral

`page` is the report background; `surface` is the inspection container; `surface-raised` is the button/select fill; `stage` is the image backdrop. `ink` is primary text, `muted` is supporting text, and `line` separates controls, tables and sections. There is one dark screen theme, declared through `color-scheme: dark`.

The control hover fill and border change together; active buttons use the separate active fill. The current history row has its own background, while hovering a run button changes both its fill and text. Print-specific colors are recorded under Layout rather than treated as a second screen theme.

## Typography

All screen text uses the system stack in `body`, except protocol/run identifiers and raw data, which use the monospace stack. Controls inherit the font. There are no downloaded fonts.

The title, section headings, tables, status badges and summary index use the frontmatter roles. Table headings are left-aligned except numeric columns. Numeric values use tabular numerals and right alignment. The summary index remains in the metrics table footer; it has no separate score-hero component.

Supporting text varies by use: metric descriptions are `.78rem` with `1.45` line height and a `36ch` maximum width, reducing to `.76rem` at the intermediate breakpoint. Metadata and section notes use `.85rem`; raw measurement blocks use `.73rem` with `1.45` line height; provenance uses `.8rem`. Long identifiers and raw text wrap anywhere. These values describe existing local roles, not a modular type scale.

## Layout

The centered shell has a maximum width of `1456px` and desktop padding of `25px 28px 42px`. Its header places the title and run picker in a flex row. The run select is `360px` wide by default. The warning precedes the workspace.

The workspace is a two-column grid: `minmax(0, 1fr) 374px`, with a `22px` gap. The inspection viewport is first; metrics are second. The image stage is `min(65vh, 650px)` high with a `360px` minimum. Images use absolute positioning and `object-fit: contain`; SVG uses the same stage geometry. The toolbar is above the image; the blend controls are below it. The default blend row has `auto minmax(80px, 1fr) 42px auto` columns.

Regional and landmark tables form an equal two-column grid with a `28px` gap and `32px` top margin. History, recommendations and the provenance disclosure follow in document order. Metrics use a fixed table layout with column widths of `65%`, `19%` and `16%`.

### Responsive behavior

- At `max-width: 1080px`, the metrics column becomes `330px` and the workspace gap `18px`. Shell padding becomes `22px 20px 36px`. The run picker is capped at `48%` and its select fills the available width. The inspection toolbar stacks vertically. The stage height becomes `590px`.
- At `max-width: 780px`, shell padding becomes `20px 16px 32px`. The header, workspace and lower detail grid stack. The workspace gap becomes `25px`; the detail grid has a `28px` gap and top margin. The toolbar returns to a wrapping row. The stage becomes `min(66vh, 580px)` with a `340px` minimum. The blend row has `auto minmax(60px, 1fr) 42px` columns, and the reset button occupies its own row with a `36px` minimum height. History controls wrap below their heading. The warning padding becomes `11px 12px`, with `.85rem` text.
- Table content scrolls inside its own container. The regional table has a `395px` minimum width, history `580px`, and the landmark table `410px` at the phone breakpoint. The three regions have descriptive labels, `tabindex="0"` and associated scroll hints. Hints are hidden above `780px` and visible at or below it; they describe horizontal touch scrolling and keyboard arrow use after focus. The metric table is separate and does not have this focusable-region treatment.
- Raw measurements wrap and scroll within a `210px` maximum height. Provenance wraps and scrolls within `420px`. This is contained overflow, not page-wide clipping.

Print rules use a white page, black body text, subdued text in `#444`, a `#fff5dd` warning with `#513e10` text, and a `#111` image stage. The shell loses its width cap and padding; the workspace uses `1.25fr 1fr` with a `500px` stage. Blend controls, run picker, history controls and provenance disclosure are hidden. Major sections request `break-inside: avoid`.

## Elevation & Depth

There are no authored shadows, gradients, backdrop filters or animated elevation effects. Background fills and borders distinguish the page, image stage, inspection container, controls, warnings and current history row. Focus is an outline rather than a shadow.

## Shapes

The inspection container and global empty state share the main radius. Controls, warnings and status/loading badges use their respective frontmatter radii. Containers and controls have `1px` borders; the metrics total has a `2px` top rule. The inspection container clips its contents to its rounded boundary. Table rows have bottom dividers, without enclosing card wrappers. Legend swatches are `18px` by `3px` lines.

## Components

### Controls and focus

Buttons and selects have a `40px` minimum height and the observed default, hover and active treatments. Hover applies to both buttons and selects; the active fill is authored only for buttons. Disabled buttons, inputs and selects use opacity `.48` and a not-allowed cursor. The reset button returns the viewport to overlay mode at `50%` candidate opacity.

The opacity control is a native range input from `0` to `100`, step `1`, with a `28px` height and a separate numeric output. It is disabled outside overlay mode. Its accessible value explicitly says candidate-layer opacity. The repeated-measurements checkbox is `16px` square. There is no custom text-entry field.

Buttons, inputs, selects, links, disclosure summaries and the three scrollable regions have a `2px` accent focus outline with a `3px` offset. The skip link is positioned above the viewport until focused, then appears at the top and targets the inspection section. The sidecar carries the exact focus and overflow rules that do not fit component token properties.

### Inspection viewport

The five modes are interactive overlay, reference only, candidate render only, contour difference and landmarks. Initial state is the newest stored run in overlay mode at `50%` opacity. Mode-specific help stays next to the controls. Reference and candidate layers preserve their captured aspect ratio; switching or dragging updates immediately without authored transitions or automatic animation. The reduced-motion rule disables transitions and forces automatic scroll behavior.

When required assets are missing, centered stage text identifies the missing asset and asks for report regeneration. A small bottom-left label covers image loading. Image decode failure has its own explanatory text. The landmark mode uses the saved derivative when available, otherwise source-defined SVG marks when aligned coordinates exist; without either it shows a message. These are implemented fallback states, not additional modes.

### Warnings, status and empty states

The warning stays above the workspace and pairs an icon with text. Provisional, invalid, measured, completeness-unconfirmed and status-unconfirmed labels come from the saved record state. Provisional and invalid badges have their own foreground, border and background treatments; other labels use the neutral badge. Invalid and unscored records do not receive a fabricated numeric summary.

If no runs exist, the main report is hidden, the run select is disabled and a bordered empty state explains how to produce a record. Missing metric, regional, landmark and history data receive table-row messages. Missing recommendations receive an explanatory list item. A `noscript` notice explains the JavaScript requirement. These states are defined in source; the generated report inspected for this document contains provisional complete records.

### Tables and history

Metric rows combine label, description and optional raw measurements with right-aligned score and normalized displayed weight. The total uses a thicker top divider and the `index` type role. Geometry, appearance and mask-sensitivity values sit in a separate definition list beneath the table.

Regional rows show the band label, height range, optional IoU and separate left/right measurements. Landmark rows include their reference-order number, pixel distance, uncertainty and written state. Neither table substitutes a color-only heat map for values.

History has a protocol select and a show-repeats checkbox. Run names are buttons with a `32px` minimum height, a `320px` maximum width and wrapping text. The current row is filled and the selected run button receives `aria-current`. Repeated candidate content is folded by default with a written count; toggling repeats exposes the stored measurements. Differences show their comparison target, positive/negative treatment or written incomparable/repeat state. A protocol note explains the comparison scope.

### Disclosures

Native details/summary controls expose raw measurements and provenance. Summaries use the shared focus treatment; expanded contents retain wrapping and contained vertical scrolling. There is no modal, tooltip, navigation bar or custom disclosure animation in the implementation.

## Do's and Don'ts

- Do preserve the written reference/candidate legend, pixel units, status labels and comparison notes alongside their color treatments.
- Do preserve image aspect ratios, numeric alignment, identifier wrapping and contained table scrolling when extending this report.
- Do retain the phone scroll hints and labelled keyboard-focusable regions for the regional, landmark and history tables.
- Do keep fallback messages distinguishable from stored measurements; the current UI does not fill missing results with example values.
- Don't present opacity percentages or the heuristic index as a 3D reconstruction percentage.
- Don't promote this local report's tokens or component choices into RepDuo's iOS design system.
