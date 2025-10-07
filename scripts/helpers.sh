#!/usr/bin/env bash
# Ensures the script stops on any error, making it safer.
set -euo pipefail

# --- Global Configuration Variables ---

# Defines the root path for this project's cgroups.
readonly PROJECT_CG_ROOT="/sys/fs/cgroup/ProjetoCompNuvem2"

# Defines the base period for CPU quota calculation, in microseconds.
# 100000µs = 100ms = 0.1s. This is a common and recommended default.
readonly CPU_PERIOD_US=100000


# --- Cgroup Management Functions ---

# Ensures the base cgroup root directory exists and enables necessary controllers.
# This function should be called once by a main setup script.
ensure_cgroot() {
  if [ ! -d "${PROJECT_CG_ROOT}" ]; then
    # Create the main directory with sudo if it doesn't exist.
    sudo mkdir -p "${PROJECT_CG_ROOT}"
  fi

  # Enable cpu and cpuset controllers in the parent cgroup's subtree_control.
  # This allows child cgroups (our environments) to use these controllers.
  if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "+cpu +cpuset" | sudo tee /sys/fs/cgroup/cgroup.subtree_control > /dev/null 2>/dev/null || true
  fi
}

# Moves a given PID into a specific cgroup using sudo.
# This is the action that applies the resource limits to the process.
# Input 1: The full path to the target cgroup.
# Input 2: The PID of the process to move.
move_pid_to_cgroup() {
  local cgpath="$1"
  local pid="$2"
  if [ ! -d "${cgpath}" ]; then
    echo "ERROR: cgroup path does not exist: ${cgpath}" >&2
    return 2
  fi
  echo "${pid}" | sudo tee "${cgpath}/cgroup.procs" > /dev/null
}


# --- Value Conversion Functions ---

# Converts a human-readable size string (e.g., "512M", "2G") into bytes.
# Input: A string like "1024", "256K", "512M", "2G".
# Output: The corresponding value in bytes.
to_bytes() {
  local val="$1"
  if [[ "$val" =~ ^([0-9]+)([KkMmGg]?)$ ]]; then
    local n=${BASH_REMATCH[1]}
    local suf=${BASH_REMATCH[2]}
    case "$suf" in
      K|k) echo $(( n * 1024 )) ;;
      M|m) echo $(( n * 1024 * 1024 )) ;;
      G|g) echo $(( n * 1024 * 1024 * 1024 )) ;;
      "")  echo "$n" ;;
    esac
  else
    echo "ERROR: Invalid memory format: $val" >&2
    return 2
  fi
}

# Calculates the cpu.max string ("quota period") from a given percentage.
# Input: An integer percentage (e.g., 50 for 50%) or "max"/"none".
# Output: A string like "50000 100000" or "max 100000".
cpu_max_from_percent() {
  local percent="$1"
  if [ "${percent}" = "max" ] || [ "${percent}" = "none" ]; then
    echo "max ${CPU_PERIOD_US}"
    return 0
  fi
  if ! [[ "${percent}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid cpu percentage: ${percent}" >&2
    return 2
  fi
  local quota=$(( percent * CPU_PERIOD_US / 100 ))
  if [ "$quota" -lt 1 ]; then quota=1; fi
  echo "${quota} ${CPU_PERIOD_US}"
}


# --- PID and Directory Utility Functions ---

# Finds the host PID by searching for a process that has a specific nspid.
# A process running inside a PID namespace has a different PID there (nspid)
# than on the host. This function maps the nspid back to the real host PID.
# Input: A PID from inside a namespace (nspid).
# Output: The corresponding PID on the host system.
find_host_pid_by_nspid() {
  local nspid_to_find="$1"
  for proc_dir in /proc/[0-9]*; do
    local host_pid=$(basename "$proc_dir")
    if [ -f "${proc_dir}/status" ]; then
      local nspid_line
      nspid_line=$(grep '^NSpid:' "${proc_dir}/status" 2>/dev/null || true)
      if [ -n "$nspid_line" ]; then
        local last_nspid=$(echo "$nspid_line" | awk '{print $NF}')
        if [ "$last_nspid" = "${nspid_to_find}" ]; then
          echo "${host_pid}"
          return 0
        fi
      fi
    fi
  done
  return 1
}

# Safely creates an output directory and sets the correct ownership and permissions.
# Input: The path of the directory to create.
ensure_output_dir() {
  local outdir="$1"
  mkdir -p "${outdir}"
  sudo chown "$(id -u):$(id -g)" "${outdir}" || true
  chmod 755 "${outdir}" || true
}