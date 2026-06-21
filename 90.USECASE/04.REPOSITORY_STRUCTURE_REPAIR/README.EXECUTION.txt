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

==========
MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========

STATUS............: ACTIVE
LAYER.............: USECASE_UPLOAD_PACKAGE_CONTROL
IMPORTANT.........:
This file is part of a 90.USECASE upload package. It is operational upload guidance for the IA.
It is not primary canon. If doctrine changes are needed, patch HUMAN, 00.CATALOG, SkillsLake,
GRCLake, registry/build sources, or an approved canonical source, then rebuild packages if applicable.

USECASE_FIRST_RULE:
Before proposing development, scripts, branches, commits, RADAR, Nightshift work, refactors,
or architecture changes, the IA must first identify and state the applicable usecase.

REQUIRED_INITIAL_RESPONSE:
The IA must start by declaring:

1. USECASE_DETECTED
2. USER_GOAL
3. CONFIRMED_CONTEXT
4. MISSING_CONTEXT
5. RECOMMENDED_UPLOADS
6. FOCUS_BOUNDARY
7. NEXT_ACTION

CONTEXT_RULE:
Do not request the full repository by default.
If context is missing, request exact paths or exact Skills/GRC/HUMAN/CATALOG/BATON/RADAR files.

ANTI_DRIFT_RULES:
- Do not treat 90.USECASE as primary canon.
- Do not create or modify canon automatically.
- Do not jump to technical execution before usecase framing.
- Do not use RADAR FULL by default.
- Do not confuse a lab/pilot workload with the central purpose of PS.SkillsMachine.
- Register Skill/GRC improvements as candidates unless the human explicitly approves a minibattle.

DONE_WHEN:
The IA can explain why the current request belongs to this usecase, what context is sufficient,
what context is missing, and the next minimal reversible action.

==========
FIN_MB-GRC-033F_USECASE_UPLOAD_FOCUS_GATE
==========
