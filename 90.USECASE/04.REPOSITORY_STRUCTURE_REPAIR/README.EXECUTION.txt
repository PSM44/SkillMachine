==========================================
USECASE — 04.REPOSITORY_STRUCTURE_REPAIR
==========================================

01) MODE (default): PLAN_ONLY
   - Snapshot first (RADAR)
   - Propose target structure
   - Write CIS plan + rollback
   - APPLY only after approval

02) FLOW
   2.1 Snapshot (read-only)
   2.2 Diagnose + propose structure
   2.3 CIS migration plan
   2.4 Apply safely (no hard delete)
   2.5 Validate + evidence
   2.6 Handoff (BATON)

03) DONE
   - Validate-System PASS
   - Validate-Release PASS
   - Evidence paths recorded
