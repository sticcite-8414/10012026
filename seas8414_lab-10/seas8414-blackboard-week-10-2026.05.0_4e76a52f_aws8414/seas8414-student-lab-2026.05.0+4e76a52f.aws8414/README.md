# SEAS-8414 Breakwater Student Lab Package

Start with `student-lab/README.md`, then follow the phase guide assigned by the course.

The runnable lab environment is in `student-lab/`.

Quick start:

```bash
cd student-lab
./run-phase01-lab.sh
```

The runner performs the Phase 1 path end to end: preflight checks, Docker Compose startup,
API readiness, discovery-owned scan execution, Breakwater HTML report export, and a local HTML
run summary under `student-lab/reports/`.

The package also includes:

- `docs/phase1-lab.pdf` - PDF export of the first lab guide
- `docs/phase1-run-green-pass2-20260505T135958Z.mp4` - prior Phase 1 lab run evidence
- `student-lab/phase1-lab.md` through `student-lab/phase12-lab.md` - student lab guides
- `student-lab/phase1-homework.md` through `student-lab/phase12-homework.md` - homework prompts
- `student-lab/ground-truth.json` - simulation ground truth for local comparison
- `student-lab/api-cheatsheet.md` - API command reference
- `student-lab/run-phase01-lab.sh` - Phase 1 end-to-end runner and report generator

Teaching-only materials are intentionally excluded.
