# 04.REPOSITORY_STRUCTURE_REPAIR — Skill

## Purpose
Repository structure repair package:
snapshot -> target structure -> CIS migration plan -> apply -> validation.

## Delivery (policy compliant)
- 00.BUNDLE.CORE.txt
- 01.BUNDLE.CONTINUITY.txt
- 02.BUNDLE.GOVERNANCE.txt
- USECASE.MANIFEST.json
- SKILL.md (this file)

## Canonicality
HUMAN is canonical; this is an operational delivery artifact for the USECASE.


==========
MB-GRC-026H_CONTEXT_PACKAGE_REQUEST
==========

REGLA:
Si el contexto adjunto no es suficiente para operar este usecase sin inventar estado, la IA debe pedir explícitamente al humano generar y subir un paquete temporal de contexto.

COMANDO_BASE:
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "90.USECASE\Prepare-ToUploadToIA.ps1" -UseCase "04.REPOSITORY_STRUCTURE_REPAIR"

OUTPUT_ESPERADO:
Temp\TO_UPLOAD_TO_IA

REGLAS:
- Pedir solo paths adicionales necesarios, no el repo completo.
- Temp\TO_UPLOAD_TO_IA es output temporal, regenerable y no canónico.
- La fuente de verdad sigue siendo SkillsLake, GRCLake, 00.CATALOG, 90.USECASE, registries y manifests.
- Si falta un Skill/GRC/Catalog necesario, pedirlo por path exacto.
- Si se detecta oportunidad de crear o mejorar Skill/GRC, registrarla como candidato; no crear canon automáticamente.
