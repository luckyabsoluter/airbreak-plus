# Debian 12 vs 13 Experiment

This experiment runs a fair, per-image comparison.

- All images run the same build workflow: `make binaries`
- Output is reported as per-image `PASS/FAIL`
- `debian13-remediated` can be included as an extra case
- Makefile checksum is captured and verified across all images to ensure fair comparison

## Run

```bash
./experiments/debian12-13/run-compare.sh
```

Optional modes:

```bash
# Skip remediation path
RUN_REMEDIATION=0 ./experiments/debian12-13/run-compare.sh

# Return non-zero if any image fails
FAIL_ON_ANY=1 ./experiments/debian12-13/run-compare.sh
```

## What it does

0. Cleans experiment output directory
1. Builds images:
   - `experiments/debian12-13/Dockerfile.debian12`
   - `experiments/debian12-13/Dockerfile.debian13`
   - Optionally: `experiments/debian12-13/Dockerfile.debian13-remediated`
2. Captures toolchain versions (`arm-none-eabi-gcc`, `arm-none-eabi-ld`)
3. Captures and verifies Makefile checksum across all images
4. Runs the same build command for each image:
   - `make binaries BUILD=<case-output-dir>`
   - Uses isolated output dirs:
     - `experiments/debian12-13/out/build-debian12`
     - `experiments/debian12-13/out/build-debian13`
     - `experiments/debian12-13/out/build-debian13-remediated`
5. Prints a result matrix with:
   - case name
   - `PASS/FAIL`
   - exit code
   - gcc/ld version lines
   - Makefile checksum
6. Verifies that all images used the same Makefile for a fair comparison
