# Results Experience Redesign Plan

## Goals (based on stakeholder priorities)

1. **Improve reporting workflows first** (priority over debugging UX).
2. Support **intermediate process-modeling users** (not novices, not experts).
3. Prefer **top-level navigation** over nested subtabs for faster access.
4. Make **CSV export** the primary output, with optional secondary formats.

---

## Proposed Information Architecture (top-level tabs)

Split the current Results surface into dedicated top-level tabs to reduce cognitive load and improve discoverability:

1. **Results – Summary**
   - KPI cards: convergence status, final residual, iteration count.
   - Report highlights: key stream and unit metrics from latest solve.
   - “What changed vs previous run” section for deltas.

2. **Results – Trends**
   - Multi-trace plotting workspace (configurable X/Y, target, axis, normalize).
   - Presets for common report plots.
   - Clean legend and publication-ready labels.

3. **Results – Tables**
   - Stream table + unit table in one reporting-oriented workspace.
   - Column chooser and sorting for report preparation.
   - One-click CSV export per table and combined export.

4. **Results – Stability**
   - Keep advanced stability workflows isolated.
   - Pole map and sweep summary.
   - Stability status and threshold notes for report appendices.

5. **Results – Export**
   - Centralized export panel.
   - CSV-first export options for trends, snapshots, summaries.
   - Reproducibility metadata (project title, timestamp, units, selected filters).

---

## Feature Plan (reporting-first)

## Phase 1 — Reporting Foundation (highest priority)

### 1) CSV-first export model
- Add export actions for:
  - Current plotted traces (`trace_name`, `x`, `y`, units, smoothing/normalization flags).
  - Snapshot history (iteration-wise raw values).
  - Summary KPI table (latest run).
  - Stream and unit result tables.
- Standardize file naming:
  - `<project>_results_summary_<timestamp>.csv`
  - `<project>_results_traces_<timestamp>.csv`
  - `<project>_results_snapshots_<timestamp>.csv`
- Include unit columns and metadata fields to avoid ambiguity in external reports.

### 2) Summary view for report narratives
- Add a summary model (`resultsSummary`) populated at solve completion.
- Surface report-centric fields:
  - Solve status, residual, iterations.
  - Key stream metrics (flow, T, P, selected composition).
  - Key unit metrics (duty, power, conversion where available).
- Add “delta vs prior run” to improve before/after analysis.

### 3) Tables workspace for report prep
- Consolidate stream/unit tables under one tab section.
- Add quick filters (stream name/unit type), sortable columns, and export selected/all rows.
- Preserve currently selected display units in CSV output metadata.

---

## Phase 2 — Usability and clarity improvements

### 4) Trends workspace redesign
- Replace fixed “Plot 1..4” rows with dynamic trace management:
  - Add/remove trace.
  - Reorder traces.
  - Toggle visibility.
- Keep defaults simple with advanced controls collapsible.
- Use user-facing metric labels and include units directly in axis labels/legend.

### 5) Better presets for non-expert modelers
- Replace technical presets with report-friendly presets:
  - **Convergence Report**
  - **Mass & Thermal Snapshot**
  - **Energy & Utilities**
- Presets should auto-select meaningful targets (first feed stream, key units, etc.).

### 6) Configuration validation and guidance
- Detect incompatible metric/target combinations proactively.
- Show non-blocking inline warnings (“Metric requires stream target”).
- Keep a visible “configuration issues” list in Trends tab.

---

## Phase 3 — Advanced analysis separation

### 7) Stability as dedicated top-level workflow
- Move all stability controls and visuals into a dedicated tab.
- Provide separate visuals:
  - Pole plot.
  - Max real pole vs sweep parameter chart.
- Add interpretation text suitable for direct reporting copy.

### 8) Cross-tab workflow improvements
- Add “Send to report” actions from Trends/Stability/Tables into Export queue.
- Enable exporting a single “report bundle” as multiple CSVs in one action.

---

## Data/Model changes required

1. Introduce a reusable **metric registry**:
   - Display label
   - internal key
   - unit domain
   - allowed target scope (`global`, `stream`, `unit`)

2. Replace hard-coded trace UI handles with **trace config collection**:
   - `resultsTraceConfigs`
   - Each entry stores X/Y/target/component/scale/axis/normalize/visible.

3. Add persistent **resultsSummary** model for report views and CSV output.

4. Add **export service helpers**:
   - Build trace export table
   - Build snapshot export table
   - Build summary export table
   - Write CSV with metadata header rows or companion metadata CSV.

---

## Implementation sequencing

1. Create top-level tabs and move existing controls with minimal behavior change.
2. Implement CSV exports for existing data model (quick win).
3. Add summary model and summary tab.
4. Replace fixed trace controls with dynamic trace model.
5. Add validation, presets, and enhanced labels.
6. Refine stability tab and reporting text.

---

## Acceptance criteria

1. User can export at least 4 distinct CSV outputs (summary, traces, snapshots, stream/unit tables).
2. A report-ready summary screen is visible immediately after solve.
3. Navigating to reporting tasks takes at most one top-level tab click.
4. Trend configuration errors are explained inline (no silent no-plot state).
5. Default presets produce useful plots without manual target tuning.

---

## Risks and mitigations

1. **Risk:** Top-level tab growth increases UI sprawl.
   - **Mitigation:** Keep strict tab purpose and minimal controls per tab.

2. **Risk:** Dynamic trace refactor introduces regressions.
   - **Mitigation:** Add compatibility adapter so old preset logic can still map to new model during transition.

3. **Risk:** CSV schema churn across versions.
   - **Mitigation:** Version CSV schema in metadata (`schema_version` column/value).

---

## Immediate next build slice (recommended)

- Ship a first PR containing:
  1. New top-level Results tab split (skeleton + control relocation).
  2. CSV exports for summary/traces/snapshots.
  3. Summary KPI panel populated after solve.

This gives immediate value for your primary goal (better reporting) before deeper plotting refactors.
