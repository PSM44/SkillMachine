# NS-PILOT-001 Markdown Task Runner

STATUS: HYBRID_BASELINE_ACCEPTED
DATE: 2026-06-21 01:26:43 -04:00

Purpose: compare Codex Desktop and Claude Code Desktop on the same small repository task, then preserve the accepted hybrid baseline as controlled Nightshift lab evidence.

Allowed agent edit path:
99.LABS/Nightshift/03_EXPERIMENTS/NS-PILOT-001_MARKDOWN_TASK_RUNNER

Allowed evidence path:
99.LABS/Nightshift/04_EVIDENCE/NS-PILOT-001_MARKDOWN_TASK_RUNNER

Forbidden without human approval:
- SkillsLake
- GRCLake
- 90.USECASE
- SyS
- repository root files

Current state: NS-PILOT-001 was executed on Codex and Claude Code branches, reconciled into lab/ns-pilot-001-hybrid, and accepted as a hybrid lab baseline.

Confirmed outputs:
- Codex branch preserved as source/evidence branch.
- Claude branch preserved as source/evidence branch.
- Hybrid branch accepted.
- Unified CLI contract created.
- Parser/report/task_runner implementation present.
- Tests present under tests/.
- Scoring rubric created.
- Management status brief created under 99.LABS/Nightshift/05_REPORTS.

Do not treat this folder as scaffold-only. The original scaffold state is historical.

Next: decide whether to close NS-PILOT-001 as lab evidence, prepare merge-readiness to main, or design NS-PILOT-002.
