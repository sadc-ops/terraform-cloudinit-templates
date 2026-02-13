#!/usr/bin/env bash
# =============================================================================
# NVIDIA Data Center GPU Driver Installation Script (+ optional CUDA Toolkit)
# =============================================================================
# Tested on: Ubuntu 22.04 LTS (Jammy) and Ubuntu 24.04 LTS (Noble)
# Target GPUs: NVIDIA data center GPUs (Ampere and newer)
# Script should be run as root.
#
# Usage:
#   ./install_nvidia.sh --driver-branch <NUMBER> [OPTIONS]
#
# Required:
#   --driver-branch <NUMBER>   NVIDIA driver branch number (e.g. 535, 570, 580)
#
# Optional:
#   --cuda-version  <X-Y>     CUDA toolkit version in APT format (e.g. 12-4, 13-1)
#                              When specified, the CUDA toolkit is installed.
#                              When omitted, only the driver is installed.
#   --skip-tests               Skip post-install GPU and CUDA verification tests.
#   --log-file <PATH>          Log all output to this file (default: /var/log/install_nvidia.log)
#   --help                     Show this help message and exit
#
# Post-install tests:
#   After installation, the script runs verification tests to confirm the GPU
#   hardware is accessible and the software stack is functional:
#     - Driver test: queries each GPU's name, driver version, memory, and
#       temperature via nvidia-smi to confirm driver-to-hardware communication.
#     - CUDA test (only when toolkit is installed): compiles and executes a
#       vector addition kernel on every detected GPU to verify the full
#       pipeline — nvcc compilation, GPU memory allocation, kernel dispatch,
#       and result correctness. All CUDA API calls are error-checked.
#   Use --skip-tests to disable these checks (e.g. in automated deployments
#   where a reboot is required before the GPU is accessible).
#
# Examples:
#   ./install_nvidia.sh --driver-branch 580
#   ./install_nvidia.sh --driver-branch 580 --cuda-version 13-1
#   ./install_nvidia.sh --driver-branch 535 --cuda-version 12-4
#   ./install_nvidia.sh --driver-branch 580 --cuda-version 13-1 --skip-tests
#   ./install_nvidia.sh --driver-branch 580 --log-file /tmp/nvidia-install.log
#
# The driver branch and CUDA toolkit version must be compatible. Consult the
# NVIDIA Data Center Driver support matrix before mixing versions:
#   R535 — LTSB, EOL June 2026,  max CUDA 12.x
#   R570 — Production, EOL Feb 2026, max CUDA 12.x
#   R580 — LTSB, EOL August 2028, max CUDA 13.x
#
# References:
#   [1] NVIDIA Data Center Drivers:
#       https://docs.nvidia.com/datacenter/tesla/drivers/
#   [2] CUDA Installation Guide (Linux):
#       https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
#   [3] CUDA Toolkit Release Notes:
#       https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
#   [4] NVIDIA Driver Installation Guide (Ubuntu):
#       https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/
#   [5] LinuxCapable — How to Install CUDA on Ubuntu:
#       https://linuxcapable.com/how-to-install-cuda-on-ubuntu-linux/
# =============================================================================
set -euxo pipefail

# ---------------------------------------------------------------------------
# Configuration — populated via command-line flags (see --help).
# ---------------------------------------------------------------------------

# NVIDIA driver branch number (e.g. 535, 570, 580). REQUIRED.
nvidia_driver_branch_number=""

# CUDA Toolkit major-minor version in APT format (e.g. "13-1" for CUDA 13.1).
# When set, the CUDA toolkit is installed. When empty, only the driver is
# installed.
cuda_toolkit_version=""

# Whether to skip post-install verification tests.
skip_tests=false

# Log file path. All output (stdout and stderr) is written to this file in
# addition to the terminal. Override via --log-file.
log_file="/var/log/install_nvidia.log"

# Supported Ubuntu versions (must match NVIDIA CUDA repo).
SUPPORTED_UBUNTU_VERSIONS=("22.04" "24.04")

# ---------------------------------------------------------------------------
# State flags
# ---------------------------------------------------------------------------
__is_driver_installed=false
__is_module_loaded=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") --driver-branch <NUMBER> [OPTIONS]

Install NVIDIA data center GPU driver and (optionally) CUDA toolkit on Ubuntu.

Required:
  --driver-branch <NUMBER>   NVIDIA driver branch number
                             Common values: 535, 570, 580

Optional:
  --cuda-version  <X-Y>     CUDA toolkit version in APT format
                             Examples: 12-4, 12-6, 13-1
                             When specified, the CUDA toolkit is installed.
                             When omitted, only the driver is installed.
  --skip-tests               Skip post-install GPU and CUDA verification tests.
  --log-file <PATH>          Log all output to this file
                             (default: /var/log/install_nvidia.log)
  --help                     Show this help message and exit

Driver / CUDA compatibility matrix:
  R535 (LTSB)       → CUDA 12.x
  R570 (Production) → CUDA 12.x
  R580 (LTSB)       → CUDA 13.x

Examples:
  $(basename "$0") --driver-branch 580
  $(basename "$0") --driver-branch 580 --cuda-version 13-1
  $(basename "$0") --driver-branch 535 --cuda-version 12-4
  $(basename "$0") --driver-branch 580 --cuda-version 13-1 --skip-tests
  $(basename "$0") --driver-branch 580 --log-file /tmp/nvidia-install.log
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --driver-branch)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --driver-branch requires a value."
          exit 1
        fi
        nvidia_driver_branch_number="$2"
        shift 2
        ;;
      --cuda-version)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --cuda-version requires a value."
          exit 1
        fi
        cuda_toolkit_version="$2"
        shift 2
        ;;
      --skip-tests)
        skip_tests=true
        shift
        ;;
      --log-file)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --log-file requires a value."
          exit 1
        fi
        log_file="$2"
        shift 2
        ;;
      --help|-h)
        usage
        ;;
      *)
        echo "ERROR: Unknown option: $1"
        echo "Run '$(basename "$0") --help' for usage."
        exit 1
        ;;
    esac
  done
}

validate_config() {
  if [[ -z "${nvidia_driver_branch_number}" ]]; then
    echo "ERROR: --driver-branch is required."
    echo "Run '$(basename "$0") --help' for usage."
    exit 1
  fi

  if ! [[ "${nvidia_driver_branch_number}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --driver-branch must be a numeric value (e.g. 535, 570, 580)."
    echo "       Got: '${nvidia_driver_branch_number}'"
    exit 1
  fi

  if [[ -n "${cuda_toolkit_version}" ]]; then
    if ! [[ "${cuda_toolkit_version}" =~ ^[0-9]+-[0-9]+$ ]]; then
      echo "ERROR: --cuda-version must be in APT format X-Y (e.g. 12-4, 13-1)."
      echo "       Got: '${cuda_toolkit_version}'"
      exit 1
    fi
  fi

  echo ">>> Configuration:"
  echo "      Driver branch:  R${nvidia_driver_branch_number}"
  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo "      CUDA Toolkit:   ${cuda_toolkit_version//-/.}"
  else
    echo "      CUDA Toolkit:   not requested"
  fi
  echo "      Skip tests:     ${skip_tests}"
  echo "      Log file:       ${log_file}"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

requires_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Please run as root."
    exit 1
  fi
}

validate_os() {
  # Ensure we're running a supported Ubuntu version.
  # NVIDIA's CUDA network repository only provides packages for these.
  if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: /etc/os-release not found. Cannot determine OS version."
    exit 1
  fi

  local id version_id
  id=$(. /etc/os-release && echo "${ID}")
  version_id=$(. /etc/os-release && echo "${VERSION_ID}")

  if [[ "${id}" != "ubuntu" ]]; then
    echo "ERROR: This script is designed for Ubuntu. Detected: ${id}"
    exit 1
  fi

  local supported=false
  for v in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
    if [[ "${version_id}" == "${v}" ]]; then
      supported=true
      break
    fi
  done

  if [[ "${supported}" != true ]]; then
    echo "ERROR: Ubuntu ${version_id} is not supported."
    echo "Supported versions: ${SUPPORTED_UBUNTU_VERSIONS[*]}"
    exit 1
  fi

  echo ">>> OS validated: Ubuntu ${version_id}"
}

detect_distro() {
  # Build the distro string used in NVIDIA's repo URLs, e.g. "ubuntu2204"
  local id version_id
  id=$(. /etc/os-release && echo "${ID}")
  version_id=$(. /etc/os-release && echo "${VERSION_ID}")
  echo "${id}${version_id}" | sed -e 's/\.//g'
}

# ---------------------------------------------------------------------------
# Installation functions
# ---------------------------------------------------------------------------

install_prerequisites() {
  # Per the official CUDA Installation Guide (Section 4.8.1 — Prepare Ubuntu)
  # and the LinuxCapable guide:
  #   - build-essential / gcc: compiler toolchain needed by DKMS to compile
  #     driver kernel modules (and for building CUDA programs if toolkit is installed)
  #   - linux-headers: required by DKMS to compile driver kernel modules
  #   - dkms: manages kernel modules so they persist across kernel updates
  #   - curl / wget / ca-certificates: secure downloads and repository management
  echo ">>> Installing build prerequisites ..."
  apt-get update
  apt-get install -y \
    build-essential \
    gcc \
    linux-headers-"$(uname -r)" \
    ca-certificates \
    software-properties-common \
    dkms \
    curl \
    wget
}

configure_cuda_repository() {
  # Set up NVIDIA's CUDA APT repository using the official two-step process:
  #   1. Download the pin file (ensures NVIDIA packages take priority)
  #   2. Install cuda-keyring (manages GPG keys + sources.list entry)
  #
  # Source: CUDA Installation Guide, Section 4.8.2/4.8.3 (Ubuntu)
  # Also: LinuxCapable guide (https://linuxcapable.com/how-to-install-cuda-on-ubuntu-linux/)
  echo ">>> Configuring NVIDIA CUDA APT repository ..."

  local distro arch
  distro=$(detect_distro)
  arch="x86_64"

  # Step 1: Download and install the APT pin file.
  # This gives NVIDIA packages priority 600, preventing Ubuntu's default
  # packages from shadowing them.
  if [[ ! -f /etc/apt/preferences.d/cuda-repository-pin-600 ]]; then
    wget "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${arch}/cuda-${distro}.pin" \
      -O /tmp/cuda-repository-pin-600
    mv /tmp/cuda-repository-pin-600 /etc/apt/preferences.d/cuda-repository-pin-600
  fi

  # Step 2: Install the cuda-keyring package (handles GPG keys + repo config).
  # Using dpkg -s to check if already installed — this is more robust than
  # checking for specific file names, since cuda-keyring may create either a
  # .list file (Ubuntu 22.04) or a .sources file (deb822 format, Ubuntu 24.04)
  # depending on the system's apt configuration.
  if ! dpkg -s cuda-keyring &>/dev/null; then
    wget "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${arch}/cuda-keyring_1.1-1_all.deb" \
      -O /tmp/cuda-keyring_1.1-1_all.deb
    dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
    rm -f /tmp/cuda-keyring_1.1-1_all.deb
  fi

  apt-get update
}

install_nvidia_driver() {
  # Install the NVIDIA data center driver using the cuda-drivers meta-package.
  #
  # For data center GPUs (A40, A100, H100, etc.), drivers should be installed
  # separately from the toolkit. The NVIDIA Data Center Drivers documentation
  # states [1]:
  #   "Since the cuda or cuda-<release> packages also install the drivers,
  #    these packages may not be appropriate for data center deployments."
  #
  # cuda-drivers-<branch> installs the proprietary kernel module, which
  # supports all GPU architectures from Maxwell onwards.
  #
  # Alternative for Turing+ GPUs (including A40/A100): use the open kernel
  # module via "nvidia-open-${nvidia_driver_branch_number}" instead:
  #   apt-get install -y nvidia-open-${nvidia_driver_branch_number}
  # The open module provides better integration with modern kernel features
  # and is NVIDIA's recommended direction for Turing+ architectures.
  echo ">>> Installing NVIDIA data center driver (R${nvidia_driver_branch_number}) ..."
  if apt-get install -y "cuda-drivers-${nvidia_driver_branch_number}"; then
    __is_driver_installed=true
  else
    __is_driver_installed=false
  fi
}

install_cuda_toolkit() {
  # Install the CUDA SDK, libraries, compilers, and development tools.
  # The cuda-toolkit-X-Y package does NOT install or modify GPU drivers,
  # which is the correct approach for data center deployments.
  #
  # Source: CUDA Installation Guide, Section 4.12.2 (Meta Packages)
  echo ">>> Installing CUDA Toolkit ${cuda_toolkit_version//-/.} ..."
  if ! apt-get install -y "cuda-toolkit-${cuda_toolkit_version}"; then
    echo "ERROR: CUDA toolkit installation failed."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Post-install functions
# ---------------------------------------------------------------------------

load_nvidia_module() {
  echo ">>> Loading NVIDIA kernel module ..."
  if modprobe -vi nvidia; then
    nvidia-smi
    modinfo nvidia
    __is_module_loaded=true
  else
    __is_module_loaded=false
  fi
}

unload_and_blacklist_nouveau_kernel_module() {
  echo ">>> Blacklisting nouveau kernel module ..."

  # Unload nouveau if currently loaded
  if lsmod | grep -q nouveau; then
    rmmod -v nouveau || true
  fi

  # Persist the blacklist across reboots
  if [[ ! -f /etc/modprobe.d/blacklist-nouveau.conf ]]; then
    cat <<-"EOF" | tee /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
  fi
}

deny_xserver_gpu() {
  # Prevent Xserver from claiming GPU resources on headless data center nodes.
  # Only relevant if an X11 configuration file exists.
  # Source: CUDA Installation Guide, Section 15.5
  #   "How can I tell X to ignore a GPU for compute-only use?"
  if [[ -f /usr/share/X11/xorg.conf.d/10-nvidia.conf ]]; then
    echo ">>> Commenting out Xserver NVIDIA config ..."
    sed -i 's/^\([^#]\)/#\1/g' /usr/share/X11/xorg.conf.d/10-nvidia.conf
  fi
}

blacklist_nvidia_packages_from_unattended_upgrades() {
  # Prevent unattended-upgrades from automatically updating NVIDIA/CUDA
  # packages, which could break driver/toolkit compatibility unexpectedly.
  #
  # The 50unattended-upgrades config file uses // for comments (APT config syntax).
  #
  # References:
  #   https://askubuntu.com/questions/1131060
  #   https://stackoverflow.com/questions/72560165

  local conf="/etc/apt/apt.conf.d/50unattended-upgrades"
  if [[ -f "${conf}" ]] && ! grep -q "nvidia" "${conf}"; then
    echo ">>> Adding NVIDIA packages to unattended-upgrades blacklist ..."
    sed -i '/Unattended-Upgrade::Package-Blacklist\s*{/,/}/ {
      /}/ i\
    // exclude nvidia and cuda packages from automatic updates\
    "nvidia-";\
    "libnvidia-";\
    "cuda-";
    }' "${conf}"
  fi
}

verify_installation() {
  # Quick check that installed binaries are present and callable.
  # This confirms the packages installed correctly; the post-install tests
  # (test_gpu_driver, test_cuda_toolkit) separately verify that the hardware
  # and full compilation pipeline are functional.
  echo ">>> Verifying installed binaries ..."

  echo "--- nvidia-smi ---"
  nvidia-smi

  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo ""
    echo "--- nvcc --version ---"
    local nvcc_bin
    nvcc_bin=$(resolve_nvcc)
    if [[ -n "${nvcc_bin}" ]]; then
      "${nvcc_bin}" --version
    else
      echo "WARNING: nvcc not found. CUDA toolkit may not be installed correctly."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Post-install tests
# ---------------------------------------------------------------------------

resolve_nvcc() {
  # Resolve the path to nvcc. APT-installed CUDA places it under
  # /usr/local/cuda/bin which may not be in PATH on a fresh install.
  if command -v nvcc &>/dev/null; then
    command -v nvcc
  elif [[ -x /usr/local/cuda/bin/nvcc ]]; then
    echo "/usr/local/cuda/bin/nvcc"
  fi
}

test_gpu_driver() {
  # Query GPU properties using nvidia-smi structured output to confirm the
  # driver can communicate with the GPU hardware. This goes beyond a simple
  # "nvidia-smi" invocation by parsing specific fields to verify the driver
  # can read device attributes from each installed GPU.
  echo ">>> Driver test: querying GPU properties ..."

  local gpu_info
  if ! gpu_info=$(nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,temperature.gpu \
                             --format=csv,noheader,nounits 2>&1); then
    echo "FAIL: nvidia-smi structured query failed."
    echo "${gpu_info}"
    return 1
  fi

  local gpu_index=0
  while IFS=',' read -r name driver_ver mem_total mem_free temp; do
    # Trim leading/trailing whitespace from each field
    name=$(echo "${name}" | xargs)
    driver_ver=$(echo "${driver_ver}" | xargs)
    mem_total=$(echo "${mem_total}" | xargs)
    mem_free=$(echo "${mem_free}" | xargs)
    temp=$(echo "${temp}" | xargs)

    echo "  GPU ${gpu_index}:"
    echo "    Name:         ${name}"
    echo "    Driver:       ${driver_ver}"
    echo "    Memory:       ${mem_free} / ${mem_total} MiB free"
    echo "    Temperature:  ${temp}°C"
    gpu_index=$((gpu_index + 1))
  done <<< "${gpu_info}"

  if [[ ${gpu_index} -eq 0 ]]; then
    echo "FAIL: No GPUs detected by nvidia-smi."
    return 1
  fi

  echo "PASS: Driver test — ${gpu_index} GPU(s) detected and responding."
  return 0
}

test_cuda_toolkit() {
  # Compile and run a minimal CUDA program to verify the full toolkit pipeline:
  #   nvcc compilation → GPU memory allocation → kernel dispatch → result check.
  #
  # The test runs on EVERY detected GPU (not just device 0) to confirm all
  # passed-through GPUs are functional at the compute level.
  #
  # For each GPU, the test program:
  #   1. Selects the device and queries its properties (name, compute
  #      capability, memory, multiprocessor count) via the CUDA runtime API.
  #   2. Allocates host and device memory for two input vectors and one output.
  #   3. Copies input data to the GPU (cudaMemcpyHostToDevice).
  #   4. Launches a vector_add kernel: c[i] = a[i] + b[i], 1024 elements.
  #   5. Synchronizes and checks for asynchronous execution errors.
  #   6. Copies the result back (cudaMemcpyDeviceToHost) and verifies every
  #      element equals the expected value (1.0 + 2.0 = 3.0).
  #
  # Every CUDA API call is checked via a CUDA_CHECK macro. This ensures that
  # failures at any stage (memory allocation, transfers, kernel execution)
  # produce a clear diagnostic message rather than a cryptic segfault.
  #
  # This exercises the compiler, runtime library, memory management, kernel
  # dispatch, device synchronization, and data transfer — the essential
  # building blocks of any CUDA workload.

  local nvcc_bin
  nvcc_bin=$(resolve_nvcc)
  if [[ -z "${nvcc_bin}" ]]; then
    echo "FAIL: nvcc not found. Cannot run CUDA test."
    return 1
  fi

  local test_dir
  test_dir=$(mktemp -d /tmp/cuda-test-XXXXXX)

  cat > "${test_dir}/vector_add.cu" <<'CUDA_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>

/* Macro to check every CUDA API call and bail with a clear message on failure.
   This is critical for a diagnostic test — silent failures (e.g. a cudaMalloc
   returning NULL) would produce cryptic segfaults instead of actionable output. */
#define CUDA_CHECK(call)                                                      \
    do {                                                                       \
        cudaError_t _err = (call);                                             \
        if (_err != cudaSuccess) {                                             \
            fprintf(stderr, "FAIL [GPU %d]: %s at %s:%d (%s)\n",              \
                    dev, cudaGetErrorString(_err), __FILE__, __LINE__, #call); \
            return 1;                                                          \
        }                                                                      \
    } while (0)

__global__ void vector_add(const float *a, const float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

/* Run the vector addition test on a single GPU.
   Returns 0 on success, 1 on failure. */
static int test_device(int dev) {
    CUDA_CHECK(cudaSetDevice(dev));

    /* ---- Device query ---- */
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, dev));
    printf("  GPU %d:\n", dev);
    printf("    Device:           %s\n", prop.name);
    printf("    Compute:          sm_%d%d\n", prop.major, prop.minor);
    printf("    Memory:           %lu MB\n",
           (unsigned long)(prop.totalGlobalMem / (1024 * 1024)));
    printf("    Multiprocessors:  %d\n", prop.multiProcessorCount);

    /* ---- Host memory ---- */
    const int N = 1024;
    const size_t size = N * sizeof(float);

    float *h_a = (float *)malloc(size);
    float *h_b = (float *)malloc(size);
    float *h_c = (float *)malloc(size);
    if (!h_a || !h_b || !h_c) {
        fprintf(stderr, "FAIL [GPU %d]: Host memory allocation failed\n", dev);
        free(h_a); free(h_b); free(h_c);
        return 1;
    }

    for (int i = 0; i < N; i++) {
        h_a[i] = 1.0f;
        h_b[i] = 2.0f;
    }

    /* ---- Device memory ---- */
    float *d_a = NULL, *d_b = NULL, *d_c = NULL;
    CUDA_CHECK(cudaMalloc(&d_a, size));
    CUDA_CHECK(cudaMalloc(&d_b, size));
    CUDA_CHECK(cudaMalloc(&d_c, size));

    /* ---- Host → Device transfer ---- */
    CUDA_CHECK(cudaMemcpy(d_a, h_a, size, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_b, h_b, size, cudaMemcpyHostToDevice));

    /* ---- Kernel launch ---- */
    int threads = 256;
    int blocks  = (N + threads - 1) / threads;
    vector_add<<<blocks, threads>>>(d_a, d_b, d_c, N);

    /* Check for launch configuration errors */
    CUDA_CHECK(cudaGetLastError());

    /* Wait for kernel completion and check for execution errors.
       This is where asynchronous runtime errors surface — a launch-only
       check (cudaGetLastError) would miss errors that occur during
       kernel execution. */
    CUDA_CHECK(cudaDeviceSynchronize());

    /* ---- Device → Host transfer ---- */
    CUDA_CHECK(cudaMemcpy(h_c, d_c, size, cudaMemcpyDeviceToHost));

    /* ---- Verify results ---- */
    int passed = 1;
    for (int i = 0; i < N; i++) {
        if (h_c[i] != 3.0f) {
            fprintf(stderr, "FAIL [GPU %d]: h_c[%d] = %f, expected 3.0\n",
                    dev, i, h_c[i]);
            passed = 0;
            break;
        }
    }

    /* ---- Cleanup ---- */
    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    free(h_a);
    free(h_b);
    free(h_c);

    if (passed) {
        printf("    Kernel test:      PASS (vector_add, %d elements)\n", N);
    }
    return passed ? 0 : 1;
}

int main(void) {
    int device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&device_count);
    if (err != cudaSuccess || device_count == 0) {
        fprintf(stderr, "FAIL: No CUDA devices found (%s)\n",
                cudaGetErrorString(err));
        return 1;
    }

    printf("  CUDA devices found: %d\n\n", device_count);

    int failures = 0;
    for (int dev = 0; dev < device_count; dev++) {
        if (test_device(dev) != 0) {
            failures++;
        }
    }

    if (failures > 0) {
        fprintf(stderr, "\nFAIL: %d of %d GPU(s) failed the CUDA test.\n",
                failures, device_count);
        return 1;
    }

    printf("\n  All %d GPU(s) passed the CUDA test.\n", device_count);
    return 0;
}
CUDA_EOF

  echo ">>> CUDA test: compiling vector_add.cu ..."
  if ! "${nvcc_bin}" -o "${test_dir}/vector_add" "${test_dir}/vector_add.cu" 2>&1; then
    echo "FAIL: nvcc compilation failed."
    rm -rf "${test_dir}"
    return 1
  fi

  echo ">>> CUDA test: running vector_add ..."
  if "${test_dir}/vector_add"; then
    echo "PASS: CUDA test — compilation and kernel execution successful on all GPUs."
  else
    echo "FAIL: CUDA test program returned an error."
    rm -rf "${test_dir}"
    return 1
  fi

  rm -rf "${test_dir}"
  return 0
}

run_post_install_tests() {
  # Run post-install verification tests. The driver test always runs; the
  # CUDA toolkit test only runs when a toolkit version was specified.
  local test_failed=false

  echo "--- Driver test ---"
  if ! test_gpu_driver; then
    test_failed=true
  fi

  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo ""
    echo "--- CUDA toolkit test ---"
    if ! test_cuda_toolkit; then
      test_failed=true
    fi
  fi

  echo ""
  if [[ "${test_failed}" == true ]]; then
    echo "WARNING: One or more post-install tests failed."
    echo "The installation may still be functional after a reboot."
  else
    echo "All post-install tests passed."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # Parse arguments first (before any output) so that --log-file is resolved
  # before setting up the logging redirect.
  parse_args "$@"

  # Set up logging. Redirect both stdout and stderr through tee so that all
  # output is written to the log file AND still passed through to the caller
  # (terminal, cloud-init, etc.). This must happen after parse_args (so
  # --log-file is resolved) but before any substantive output.
  local log_dir
  log_dir=$(dirname "${log_file}")
  mkdir -p "${log_dir}"
  exec > >(tee -a "${log_file}") 2>&1

  # 1. Validate configuration
  echo "========================================="
  echo "  Step 1: Validate configuration"
  echo "========================================="
  echo ">>> Logging to: ${log_file}"
  validate_config

  # 2. Pre-flight checks
  echo "========================================="
  echo "  Step 2: Pre-flight checks"
  echo "========================================="
  requires_root
  validate_os

  # 3. System update
  echo "========================================="
  echo "  Step 3: System update"
  echo "========================================="
  apt-get update && apt-get upgrade -y

  # 4. Install build prerequisites
  echo "========================================="
  echo "  Step 4: Install prerequisites"
  echo "========================================="
  install_prerequisites

  # 5. Configure NVIDIA CUDA APT repository (pin file + keyring)
  echo "========================================="
  echo "  Step 5: Configure CUDA repository"
  echo "========================================="
  configure_cuda_repository

  # 6. Blacklist nouveau before driver installation
  echo "========================================="
  echo "  Step 6: Blacklist nouveau"
  echo "========================================="
  unload_and_blacklist_nouveau_kernel_module

  # 7. Install NVIDIA driver
  echo "========================================="
  echo "  Step 7: Install NVIDIA driver (R${nvidia_driver_branch_number})"
  echo "========================================="
  install_nvidia_driver

  if [[ "${__is_driver_installed}" != true ]]; then
    echo "ERROR: NVIDIA driver installation failed."
    exit 1
  fi
  echo "NVIDIA driver (R${nvidia_driver_branch_number}) installed successfully."

  # 8. Install CUDA Toolkit (only when --cuda-version was specified)
  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo "========================================="
    echo "  Step 8: Install CUDA Toolkit ${cuda_toolkit_version//-/.}"
    echo "========================================="
    install_cuda_toolkit
  else
    echo "========================================="
    echo "  Step 8: CUDA Toolkit — skipped (no --cuda-version specified)"
    echo "========================================="
  fi

  # 9. Post-install configuration
  echo "========================================="
  echo "  Step 9: Post-install configuration"
  echo "========================================="
  deny_xserver_gpu

  # 10. Load NVIDIA module (may require reboot on first install)
  echo "========================================="
  echo "  Step 10: Load NVIDIA module"
  echo "========================================="
  load_nvidia_module
  if [[ "${__is_module_loaded}" != true ]]; then
    echo "WARNING: NVIDIA module did not load. A reboot is likely required."
    echo "After reboot, verify with: nvidia-smi"
    if [[ -n "${cuda_toolkit_version}" ]]; then
      echo "  Also verify CUDA with: nvcc --version"
    fi
  else
    echo "NVIDIA module loaded successfully."
    verify_installation
  fi

  # 11. Post-install tests (only when module loaded and tests not skipped)
  if [[ "${__is_module_loaded}" == true ]] && [[ "${skip_tests}" != true ]]; then
    echo "========================================="
    echo "  Step 11: Post-install tests"
    echo "========================================="
    run_post_install_tests
  elif [[ "${skip_tests}" == true ]]; then
    echo "========================================="
    echo "  Step 11: Post-install tests — skipped (--skip-tests)"
    echo "========================================="
  else
    echo "========================================="
    echo "  Step 11: Post-install tests — skipped (module not loaded)"
    echo "========================================="
  fi

  # 12. Final cleanup
  echo "========================================="
  echo "  Step 12: Cleanup and lockdown"
  echo "========================================="
  apt-get update && apt-get upgrade -y
  apt-get autoclean
  apt-get autoremove -y
  blacklist_nvidia_packages_from_unattended_upgrades

  echo "========================================="
  echo "  Installation complete."
  echo "========================================="
  echo ""
  echo "Summary:"
  echo "  Driver branch:  R${nvidia_driver_branch_number}"
  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo "  CUDA Toolkit:   ${cuda_toolkit_version//-/.}"
  else
    echo "  CUDA Toolkit:   not installed"
  fi
  echo ""
  echo "If the NVIDIA module did not load, reboot now:"
  echo "  sudo reboot"
  echo ""
  echo "After reboot, verify with:"
  echo "  nvidia-smi"
  if [[ -n "${cuda_toolkit_version}" ]]; then
    echo "  nvcc --version"
  fi
}

main "$@"