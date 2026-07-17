# KAFCO Inventory Cycle & Reorder Window Analytics

**A data-driven spare-parts procurement model for multi-year maintenance shutdown cycles.**

Built from an industrial attachment at Karnaphuli Fertilizer Company (KAFCO), Bangladesh. Full pipeline: **Excel → PostgreSQL → Tableau**, with a quantified benchmark against naive procurement heuristics.

> 📊 **[View the live Tableau dashboard →](#)** *(https://public.tableau.com/app/profile/mir.al.musaddek.fahim/viz/KAFCOInventoryCycleReorderAnalytics/KAFCOInventoryDashboard?publish=yes)*

---

## ⚠️ Data Disclosure

This project uses a **synthetically generated dataset** (400 records) modeled on realistic KAFCO procurement patterns and industry-standard spare-parts categories. Real operational data was not available for this attachment. All item codes, dates, and figures are simulated for portfolio and learning purposes and do **not** represent actual KAFCO records or vendor performance.

---

## Business Problem

KAFCO's spare-parts procurement for major maintenance shutdowns spans multi-year lead times, but purchase orders are typically triggered without a structured, data-backed timeline. This project answers two questions:

1. **Consumption Velocity** — how fast is each spare-part category actually consumed relative to the ~3.3–3.5 year shutdown cycle?
2. **Optimal Reorder Windows** — on what exact date should a purchase order be placed so the part arrives *exactly* when the next shutdown begins?

```
Reorder Date = Shutdown Date − Average Lead Time (per category) − Safety Buffer
```

---

## Key Findings

| Category | Avg Lead Time (days) | Safety Buffer (days) | % Slow-Moving | Recommended PO Date |
|---|---|---|---|---|
| Mechanical | 193.8 | 76 | **37.5%** | 14-Dec-2026 |
| Civil | 163.7 | 49 | **100.0%** | 09-Feb-2027 |
| Piping | 139.8 | 51 | 67.5% | 03-Mar-2027 |
| Instrumentation | 136.5 | 42 | 32.0% | 15-Mar-2027 |
| HVAC | 112.9 | 43 | 13.3% | 07-Apr-2027 |
| Electrical | 109.8 | 42 | 12.5% | 11-Apr-2027 |
| Chemical | 86.9 | 37 | 25.0% | 09-May-2027 |
| Utility | 86.0 | 34 | 40.0% | 13-May-2027 |
| Safety | 63.6 | 30 | 10.0% | 08-Jun-2027 |
| Lubrication | 39.1 | 23 | 15.0% | 10-Jul-2027 |

**Target shutdown: 10-Sep-2027** (next in KAFCO's historical ~3.3–3.5 year cycle: 2017 → 2021 → 2024 → 2027)

### Benchmarked against naive procurement rules

A flat "order 90 days before shutdown" heuristic — common in plants without formal analytics — was tested against the data-driven model:

| Metric | Flat 90-Day Rule | Lead-Time-Only (No Buffer) | Data-Driven Model |
|---|---|---|---|
| Categories exposed to stockout risk | 9 of 10 | 10 of 10 | **0** |
| Items exposed (of 400) | 380 (95.0%) | 400 (100%) | **0** |
| Worst-case days late | 179.8 (Mechanical) | 76.0 (Mechanical) | **0** |
| Item-weighted avg days late | 103.0 | 51.2 | **0** |

**Decision:** the per-category, data-driven reorder calendar is adopted over both naive alternatives — it removes a quantified stockout-risk exposure that would otherwise affect the large majority of the catalogue. See `report/KAFCO_Project_Report.docx` (Section 5) for full methodology and caveats.

---

## Methodology & Pipeline

| Phase | Tool | What it produced |
|---|---|---|
| 1. Data Foundation | Microsoft Excel | 400-row synthetic dataset (10 categories); pivot summary with COUNTIF/AVERAGEIF/SUMIF and charts |
| 2. Analysis | PostgreSQL (pgAdmin) | 10-step SQL script → cycle-time segmentation, turnover classification (NTILE), lead-time variability, statistically-derived safety buffers (95% service level), reorder-date calculation |
| 3. Visualization | Tableau Public | 4-worksheet interactive dashboard (Velocity Breakdown, Turnover by Category, Reorder Timeline, Slow-Moving Risk) with filter actions |
| 4. Reporting | Word / Excel | Formal write-up with baseline comparison and quantified decision |

**Core calculations:**
- **Days of Supply** = quantity received ÷ (annual demand rate ÷ 365)
- **Turnover Rate** = annual demand rate ÷ quantity received, ranked and split into Fast/Medium/Slow tiers via `NTILE(3)`
- **Coefficient of Variation** = stddev(lead time) ÷ avg(lead time), used to rank supplier predictability per category
- **Safety Buffer** = 1.65 × stddev(lead time) — a standard industrial 95%-service-level formula, not a flat assumption

---

## Repository Structure

```
kafco-inventory-analytics/
├── README.md
├── data/
│   ├── raw/
│   │   └── KAFCO_ItemCode_Category_Dates_400.csv     # 400-row source dataset
│   └── processed/
│       ├── kafco_category_kpi.csv                    # SQL output: 10 rows, category KPIs
│       └── kafco_item_detail.csv                      # SQL output: 400 rows, item-level detail
├── sql/
│   └── KAFCO_SQL.sql                                   # 10-step PostgreSQL analysis script
├── tableau/
│   └── KAFCO_Inventory_Cycle___Reorder_Analytics.twb   # Tableau workbook
└── report/
    ├── KAFCO_Project_Report.docx                       # Full write-up: methodology, findings, decision
    └── KAFCO_Baseline_Comparison.xlsx                  # Live-formula benchmark backing Section 5
```

---

## Tools Used

`Microsoft Excel` · `PostgreSQL` · `pgAdmin` · `Tableau Public`

---

## Limitations

- Dataset is synthetic; absolute dates and buffer sizes are a methodology demonstration, not an operational schedule.
- The safety-stock formula assumes approximately normal lead-time variability; this was not tested against the data's actual distribution.
- No unit-cost field exists in the dataset, so all comparisons are measured in **schedule-risk days and SKU counts**, not currency — no cost-saving figure is claimed.

Full limitations and recommendations are documented in `report/KAFCO_Project_Report.docx`.

---

## Author

**Fahim** — Data Analytics Portfolio Project
Based on Industrial Attachment at Karnaphuli Fertilizer Company (KAFCO), Bangladesh
