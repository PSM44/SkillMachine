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
MB-GRC-026I_USECASE_FOLDER_UPLOAD_PACKAGE
==========

REGLA:
La carpeta del usecase es el paquete operativo de subida a la IA.

CARPETA_A_SUBIR:
C:\01. GitHub\Skills\90.USECASE\04.REPOSITORY_STRUCTURE_REPAIR

REGLAS:
- Subir el contenido completo de la carpeta del usecase correspondiente.
- No usar Temp\TO_UPLOAD_TO_IA.
- No pedir el repo completo por defecto.
- Si falta contexto, pedir paths exactos adicionales desde SkillsLake, GRCLake, 00.CATALOG, SyS u otra ruta necesaria.
- Si se detecta oportunidad de crear o mejorar Skill/GRC, registrarla como candidato; no crear canon automáticamente.
