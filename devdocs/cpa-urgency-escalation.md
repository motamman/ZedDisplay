# CPA Urgency Escalation — Design Notes

## Problem
Once a vessel is at alarm level, no further alerting happens regardless of how much worse the situation gets. CPA could halve and TCPA could drop from 30 minutes to 30 seconds — the user gets no update.

## Proposed Cadence

| TCPA Range | Re-alert Interval | Notes |
|---|---|---|
| > 5 minutes | 60 seconds | Standard — current behavior |
| 2–5 minutes | 30 seconds | Increasing urgency |
| 1–2 minutes | 20 seconds | Situation is imminent |
| < 1 minute | 10 seconds | Critical — encounter happening now |

These intervals apply to ACK'd alerts. DISMISS kills the alert permanently regardless of TCPA.

## Open Questions

1. **Audio restart on cadence change?** When TCPA crosses a threshold (e.g., drops below 5 min), should audio restart even if previously ACK'd? This is the real urgency signal — the situation escalated since you last acknowledged. Likely yes.

2. **Snackbar vs audio at <1 minute:** At this point the user should be looking at the radar/chart, not reading snackbars. Consider audio-only (short tone every 10s) with no snackbar blocking the view.

3. **Post-pass relaxation:** Once TCPA goes negative (vessel has passed), urgency cadence should relax back to standard or clear after sustained divergence.

4. **Multiple vessels:** The most urgent vessel (shortest TCPA) should drive the cadence. Don't let a 20-minute TCPA vessel's slow cadence delay re-alerts for a 90-second TCPA vessel.

5. **CPA tightening:** Should CPA getting significantly worse (e.g., halving) also trigger a re-alert regardless of TCPA? A vessel at CPA 0.1nm with TCPA 10 minutes is worse than CPA 0.4nm with TCPA 2 minutes.

## Implementation Notes
- The re-show timer lives in `AlertCoordinator` (currently fixed 15s interval)
- Per-alert cadence would require the coordinator to check TCPA from the alert's `callbackData` (CpaVesselAlert)
- Or CPA service manages its own re-alert timer and re-submits to the coordinator (simpler, keeps domain logic in CPA)
- Divergence threshold (`cpa_divergence_seconds` in StorageService) should probably also scale with TCPA
