# Public SEAS-8414 lab runner targets.

.PHONY: week10 clean-week10

week10:
	./run-week10-lab.sh

clean-week10:
	@if [ -d "seas8414-student-lab-2026.05.0+4e76a52f.aws8414/student-lab" ]; then \
		cd "seas8414-student-lab-2026.05.0+4e76a52f.aws8414/student-lab" && \
		docker compose down -v --remove-orphans; \
	fi
