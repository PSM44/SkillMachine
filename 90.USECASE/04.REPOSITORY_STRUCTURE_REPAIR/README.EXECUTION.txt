==========================================
USECASE — 04.REPOSITORY_STRUCTURE_REPAIR
==========================================

01) MODE (default): PLAN_ONLY
   - Snapshot first (RADAR)
   - Full DocumentConsistencyAudit before repair proposal
   - Propose target structure
   - Write CIS plan + rollback
   - APPLY only after approval

02) FLOW
   2.1 Snapshot (read-only)
   2.2 Full DocumentConsistencyAudit on the declared PROJECT_ROOT
   2.3 Diagnose + propose structure
   2.4 CIS migration plan
   2.5 Apply safely (no hard delete)
   2.6 Validate + evidence
   2.7 Handoff (BATON)

03) AUDIT CONTRACT
   - HUMAN is authoritative intent, not infallible truth.
   - Detect contradictions across HUMAN, BATON, registries, manifests, scripts and docs. Do not treat historical WhoAmI as authority. WHOAMI_ACTIVE_CANON=NO.
   - References to other repositories/projects must be tagged as [REF_CRUZADA: <project>].
   - HARD_CONFLICT blocks destructive or mutating repair until human approval.
   - 05.SKILLSMACHINE_UPDATE is never auto-executed from this flow.

03) DONE
   - Validate-System PASS
   - Validate-Release PASS
   - Evidence paths recorded

==========
MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
CANONICAL_COPY_IN_PACKAGE: README.UPLOAD_THIS_USECASE.txt
Apply the upload focus-gate from that file. Do not duplicate the full block here.
==========
FIN_MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
