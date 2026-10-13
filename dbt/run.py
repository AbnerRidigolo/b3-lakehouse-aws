"""Fail closed: validate silver before writing gold; bounded process lifetime.

The container receives temporary credentials through the ECS task role.
No AWS profiles or access keys are baked into this image.
"""
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    required = ['GOLD_DATABASE', 'ATHENA_RESULTS_URI', 'GOLD_DATA_URI', 'ATHENA_WORKGROUP']
    if any(not os.environ.get(key) for key in required):
        raise ValueError('Missing gold runtime configuration')
    # Bounded build, no automatic retries. Step Functions also needs a timeout.
    deadline = time.monotonic() + 1200
    paths = ['--project-dir', str(Path(__file__).parent),
             '--profiles-dir', str(Path(__file__).parent)]
    for command in [['test', '--select', 'tag:source_contract'], ['build', '--fail-fast']]:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Gold execution deadline exceeded')
        result = subprocess.run(['dbt', '--no-use-colors'] + command + paths, timeout=remaining, check=False)
        if result.returncode:
            return result.returncode
    return 0


if __name__ == '__main__':
    sys.exit(main())

