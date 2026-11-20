# SEAS-8414 Phase 10 Blackboard Package

This ZIP is prepared for Blackboard course-content upload after the release-ready
student lab package gate passes.

Contents:
- `runtime/` with the curated student lab runtime ZIP
- `MANIFEST.json` and `SHA256SUMS`

Quick start for Phase 10:

```bash
mkdir -p "$HOME/seas8414-week10"
cd "$HOME/seas8414-week10"
unzip seas8414-blackboard-week-10-2026.05.0_4e76a52f_aws8414.zip
cd seas8414-blackboard-week-10-2026.05.0_4e76a52f_aws8414
make week10
```

The Makefile calls `run-week10-lab.sh`. It uses the locally supplied Blackboard package (without downloading the public ZIP),
extracts the bundled nested runtime ZIP, starts Docker Compose without pulling or
building Docker images, runs the Week 10 API workflow, saves evidence under `lab-results/week-10/evidence/`, writes
`lab-results/week-10/index.html`, and cleans up containers with
`docker compose down -v --remove-orphans` at exit.

All required Docker images must already be available locally. Missing packages or images
cause an error instead of an automatic download. These restrictions do not block
outbound connections initiated by running containers.

Do not run the Docker lab from `/tmp` on macOS. Docker Desktop and Colima can reject bind mounts
from temporary directories. Use a normal user-writable folder such as `$HOME/seas8414-week10`,
`Downloads`, or `Desktop`.

Manual runtime extraction:

```bash
unzip runtime/seas8414-student-lab-2026.05.0+4e76a52f.aws8414.zip -d runtime-extracted
cd runtime-extracted/seas8414-student-lab-2026.05.0+4e76a52f.aws8414/student-lab
```

Release ID: `2026.05.0+4e76a52f.aws8414`
