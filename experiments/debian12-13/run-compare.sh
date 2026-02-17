#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

RUN_REMEDIATION="${RUN_REMEDIATION:-1}"
FAIL_ON_ANY="${FAIL_ON_ANY:-0}"

if [[ -t 1 ]]; then
    COLOR_PASS=$'\033[32m'
    COLOR_FAIL=$'\033[31m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_PASS=""
    COLOR_FAIL=""
    COLOR_RESET=""
fi

declare -a NAMES
declare -a IMAGES
declare -a DOCKERFILES
declare -a OUTDIRS
declare -a GCC_LINES
declare -a LD_LINES
declare -a MAKEFILE_SUMS
declare -a EXIT_CODES
declare -a RESULTS

add_case() {
    NAMES+=("$1")
    IMAGES+=("$2")
    DOCKERFILES+=("$3")
    OUTDIRS+=("$4")
}

add_case \
    "debian12" \
    "${IMAGE12:-airbreak-exp:debian12}" \
    "$SCRIPT_DIR/Dockerfile.debian12" \
    "experiments/debian12-13/out/build-debian12"

add_case \
    "debian13" \
    "${IMAGE13:-airbreak-exp:debian13}" \
    "$SCRIPT_DIR/Dockerfile.debian13" \
    "experiments/debian12-13/out/build-debian13"

if [[ "$RUN_REMEDIATION" == "1" ]]; then
    add_case \
        "debian13-remediated" \
        "${IMAGE13_REMEDIATED:-airbreak-exp:debian13-remediated}" \
        "$SCRIPT_DIR/Dockerfile.debian13-remediated" \
        "experiments/debian12-13/out/build-debian13-remediated"
fi

run_in_image() {
    local image="$1"
    shift
    docker run --rm \
        --mount "type=bind,source=$ROOT_DIR,target=/workspace" \
        -w /workspace \
        "$image" \
        bash -lc "$*"
}

echo "[0/5] Clean experiment output directory"
rm -rf "$SCRIPT_DIR/out"
mkdir -p "$SCRIPT_DIR/out"

echo "[1/5] Build images"
for i in "${!NAMES[@]}"; do
    echo " - ${NAMES[$i]} (${IMAGES[$i]})"
    docker build -f "${DOCKERFILES[$i]}" -t "${IMAGES[$i]}" .
done

echo "[2/5] Capture toolchain versions"
for i in "${!NAMES[@]}"; do
    gcc_line="$(run_in_image "${IMAGES[$i]}" "arm-none-eabi-gcc --version | head -n 1")"
    ld_line="$(run_in_image "${IMAGES[$i]}" "arm-none-eabi-ld --version | head -n 1")"
    GCC_LINES+=("$gcc_line")
    LD_LINES+=("$ld_line")
    echo " - ${NAMES[$i]} gcc: $gcc_line"
    echo " - ${NAMES[$i]} ld : $ld_line"
done

echo "[2.5/5] Capture and verify Makefile checksum"
for i in "${!NAMES[@]}"; do
    makefile_sum="$(run_in_image "${IMAGES[$i]}" "sha256sum /workspace/Makefile | cut -d' ' -f1")"
    MAKEFILE_SUMS+=("$makefile_sum")
    echo " - ${NAMES[$i]} Makefile: $makefile_sum"
done

echo "[3/5] Run same build workflow for each image (fair comparison)"
for i in "${!NAMES[@]}"; do
    outdir="${OUTDIRS[$i]}"
    set +e
    run_in_image "${IMAGES[$i]}" "rm -rf $outdir; mkdir -p $outdir; make binaries BUILD=$outdir"
    code=$?
    set -e
    EXIT_CODES+=("$code")
    if [[ "$code" -eq 0 ]]; then
        RESULTS+=("PASS")
        echo " - ${NAMES[$i]}: ${COLOR_PASS}PASS${COLOR_RESET}"
    else
        RESULTS+=("FAIL")
        echo " - ${NAMES[$i]}: ${COLOR_FAIL}FAIL${COLOR_RESET} (exit=$code)"
    fi
done

echo "[4/5] Result matrix"
for i in "${!NAMES[@]}"; do
    if [[ "${RESULTS[$i]}" == "PASS" ]]; then
        status_colored="${COLOR_PASS}${RESULTS[$i]}${COLOR_RESET}"
    else
        status_colored="${COLOR_FAIL}${RESULTS[$i]}${COLOR_RESET}"
    fi
    echo "- ${NAMES[$i]} | ${status_colored} | exit=${EXIT_CODES[$i]}"
    echo "    gcc: ${GCC_LINES[$i]}"
    echo "    ld : ${LD_LINES[$i]}"
    echo "    Makefile: ${MAKEFILE_SUMS[$i]}"
done

echo "[5/5] Verify Makefile consistency"
first_sum="${MAKEFILE_SUMS[0]}"
all_same=true
for i in "${!NAMES[@]}"; do
    if [[ "${MAKEFILE_SUMS[$i]}" != "$first_sum" ]]; then
        all_same=false
        echo "WARNING: ${NAMES[$i]} has different Makefile checksum!"
    fi
done
if [[ "$all_same" == "true" ]]; then
    echo "✓ All images use identical Makefile (checksum: ${first_sum:0:16}...)"
else
    echo "✗ Makefiles differ across images - comparison may not be fair!"
fi

if [[ "$FAIL_ON_ANY" == "1" ]]; then
    for code in "${EXIT_CODES[@]}"; do
        if [[ "$code" -ne 0 ]]; then
            exit 1
        fi
    done
fi

exit 0
