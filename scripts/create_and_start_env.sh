#!/usr/bin/env bash
# Ensures the script stops on any error, making it safer.
set -euo pipefail

# Imports the helper functions from the helpers.sh file.
source "$(dirname "$0")/helpers.sh"

# --- 1. Input Validation and Argument Parsing ---
# Usage Example:
# ./create_and_start_env.sh env01 0 256 50 512M "none" "python3 /root/sample_service.py"

if [ $# -lt 7 ]; then
  echo "Usage: $0 <env_id> <cpuset> <cpu.weight> <cpu_percent|max> <memory|none> <io_limits|none> \"<command>\"" >&2
  exit 2
fi

# Assigns command-line arguments to descriptive variable names.
ENV="$1"; CPUSET="$2"; CPU_WEIGHT="$3"; CPU_PERCENT="$4"; MEMORY="$5"; IO_LIM="$6"
shift 6
CMD="$*"

# --- 2. Path and Directory Definitions ---
# The root path for cgroups is defined in helpers.sh (PROJECT_CG_ROOT).
CGROOT="${PROJECT_CG_ROOT}"
CG="${CGROOT}/${ENV}"
OUTROOT="/vagrant/outputs/${ENV}"
LOG="${OUTROOT}/out.log"

echo "~> Starting creation of environment '${ENV}'..."

# --- 3. Prepare Cgroup Environment ---
echo "~> 1/11: Preparing cgroup environment..."
# Ensures the main project cgroup exists and controllers are enabled.
ensure_cgroot
# Creates the specific cgroup directory for this environment with sudo.
sudo mkdir -p "${CG}"
sudo chmod 755 "${CG}"

# --- 4. Apply CPU Affinity and Weight ---
echo "~> 2/11: Applying cpuset and cpu.weight..."
# cpuset.cpus: Pins the processes in the cgroup to specific CPU cores (e.g., "0" or "0-1").
echo "${CPUSET}" | sudo tee "${CG}/cpuset.cpus" > /dev/null
# cpu.weight: A relative weight for CPU time distribution when there is contention.
# Default is 100. Higher is more priority.
echo "${CPU_WEIGHT}" | sudo tee "${CG}/cpu.weight" > /dev/null

# --- 5. Apply Memory Limit (Optional) ---
if [ "${MEMORY}" != "none" ]; then
  echo "~> 3/11: Applying memory limit (${MEMORY})..."
  MEM_BYTES=$(to_bytes "${MEMORY}")
  echo "${MEM_BYTES}" | sudo tee "${CG}/memory.max" > /dev/null
fi

# --- 6. Apply CPU Limit (Optional) ---
if [ -n "${CPU_PERCENT}" ]; then
  echo "~> 4/11: Applying CPU quota limit (${CPU_PERCENT}%)..."
  CPU_LINE=$(cpu_max_from_percent "${CPU_PERCENT}")
  echo "${CPU_LINE}" | sudo tee "${CG}/cpu.max" > /dev/null
fi

# --- 7. Apply I/O Limit (Optional) ---
if [ "${IO_LIM}" != "none" ]; then
  echo "~> 5/11: Applying I/O limit..."
  # To get the device, we must ensure the output path exists first.
  ensure_output_dir "${OUTROOT}"
  local_dev=$(df --output=source "${OUTROOT}" | tail -1 | tr -d '[:space:]')
  MAJMIN=$(lsblk -no MAJ:MIN "${local_dev}" 2>/dev/null || true)
  if [ -n "${MAJMIN}" ]; then
    # Expected IO_LIM format: "rbps=1048576,wbps=524288"
    IOSTR="${MAJMIN} ${IO_LIM//, / }"
    echo "${IOSTR}" | sudo tee "${CG}/io.max" > /dev/null || true
  else
    echo "WARN: Could not get MAJ:MIN for ${local_dev}. Skipping io.max limit."
  fi
fi

# --- 8. Prepare Output Directory ---
echo "~> 6/11: Preparing output directory and log file..."
ensure_output_dir "${OUTROOT}"
touch "${LOG}" || true
chmod 644 "${LOG}" || true

# --- 9. Start Process in New PID Namespace ---
echo "~> 7/11: Starting command in new namespace..."
# We use 'unshare' to create a new PID namespace for the command.
# This is a robust PID detection method: the new process writes its own PID
# (as seen from inside the namespace) to a file that the host can read.
sudo unshare --pid --fork --mount-proc -- bash -lc "nohup ${CMD} > ${LOG} 2>&1 & echo \$! > ${OUTROOT}/.inner_pid"

# Give the process a moment to start and write the pid file.
sleep 0.2

# --- 10. Map Namespace PID to Host PID ---
echo "~> 8/11: Reading PID from within the namespace..."
if [ ! -f "${OUTROOT}/.inner_pid" ]; then
  echo "ERROR: Could not find inner PID file at ${OUTROOT}/.inner_pid. Check the log: ${LOG}" >&2
  exit 1
fi
INNER_PID=$(cat "${OUTROOT}/.inner_pid" | tr -d '[:space:]')

echo "~> 9/11: Mapping namespace PID (${INNER_PID}) to host PID..."
# Use our robust helper function to find the real host PID.
HOST_PID=$(find_host_pid_by_nspid "${INNER_PID}" || true)
if [ -z "${HOST_PID}" ]; then
  # Fallback to the heuristic method if the main one fails.
  HOST_PID=$(lsof -t "${LOG}" 2>/dev/null || true)
fi

if [ -z "${HOST_PID}" ]; then
  echo "ERROR: Could not map inner PID (${INNER_PID}) to a host PID." >&2
  exit 1
fi

# --- 11. Move Process to Cgroup and Finalize ---
echo "~> 10/11: Moving Host PID (${HOST_PID}) to cgroup..."
# This is the final step that applies all configured resource limits to the process.
move_pid_to_cgroup "${CG}" "${HOST_PID}"

echo "~> 11/11: Saving metadata..."
# Save all relevant information to a metadata file for easy access later.
cat > "${OUTROOT}/metadata.txt" <<EOF
ENV=${ENV}
INNER_PID=${INNER_PID}
HOST_PID=${HOST_PID}
CPUSET=${CPUSET}
CPU_WEIGHT=${CPU_WEIGHT}
CPU_PERCENT=${CPU_PERCENT}
MEMORY=${MEMORY}
IO=${IO_LIM}
CMD=${CMD}
LOG=${LOG}
CGPATH=${CG}
CREATED=$(date --iso-8601=seconds)
EOF

echo "SUCESS: Environment ${ENV} created. HOST_PID=${HOST_PID}. Log at ${LOG}"