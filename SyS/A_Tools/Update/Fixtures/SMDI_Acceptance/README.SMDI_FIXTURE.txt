SMDI_ACCEPTANCE_FIXTURE_DESIGN.V0.1
DECISION=DEC-CQ-003=B
STATUS=DESIGN_CANDIDATE
DO_NOT_MIX_INTO_CORE_HARNESS=YES

INTENT:
Separate SMDI acceptance evidence (checkpoint hashes, ALREADY_APPLIED direct proof,
recover action proof) into this fixture area; keep Test-SkillsMachineUpdate.ps1 core MVP clean.

NOTE:
Prior defective 153-line core patch preserved outside repo under %TEMP%\MB-SM-075A-EVIDENCE
and must not be reintroduced without rework of PowerShell -or/PSBoundParameters defects.