# Week 08 Command Plan

Runner invocation:

```bash
make week08
# or
./run-week08-lab.sh
```

Environment:

- API base: `http://localhost:8100`
- Subnet: `172.30.0.0/24`
- Runtime directory: `seas8414-student-lab-2026.05.0+4e76a52f.aws8414/student-lab`

Core commands executed:

```bash
docker compose up -d
./wait-for-lab.sh
curl http://localhost:8100/health
POST http://localhost:8100/v1/auth/register
POST http://localhost:8100/v1/auth/login
GET http://localhost:8100/v1/scanning/smart-scan/history?limit=1
POST http://localhost:8100/v1/scanning/smart-scan
GET http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results
docker compose down -v --remove-orphans
```

Week-specific API and probe commands are recorded as JSON/text evidence files in this directory.
