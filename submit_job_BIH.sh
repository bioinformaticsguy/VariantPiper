#!/bin/bash

#SBATCH --partition=standard
#SBATCH --time=1-00:00:00
#SBATCH --nodes=1
#SBATCH -c 16
#SBATCH --mem=64GB
#SBATCH --job-name=variantpiper
#SBATCH --output=logs/slurm_%j_%u_%N.out
#SBATCH --error=logs/slurm_%j_%u_%N.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=Ali.Hassan@mdc-berlin.de

# ============================================================
# VariantPiper — SLURM submission script (BIH HPC)
# ============================================================
# Usage:
#   sbatch submit_job_BIH.sh <configfile> [sample_id R1 R2]
#
# Examples:
#   # Use a config file (standard):
#   sbatch submit_job_BIH.sh config/config_HG002.yaml
#
#   # Override sample inline — no separate config file needed:
#   sbatch submit_job_BIH.sh config/config.yaml A4842 \
#     /data/cephfs-2/.../R1.fastq.gz \
#     /data/cephfs-2/.../R2.fastq.gz
#
# The inline sample replaces whatever samples are in the config file.
# The singularity bind path is set to /data/cephfs-1 by default;
# if R1/R2 live on a different filesystem (e.g. cephfs-2), the script
# automatically extends the bind to cover both.
#
# Override any SLURM resource at submission time, e.g.:
#   sbatch --partition=highmem --mem=200GB submit_job_BIH.sh config/config.yaml
#   sbatch --time=2-00:00:00 --job-name=A4842 submit_job_BIH.sh config/config.yaml A4842 R1 R2
#
# Prerequisites:
#   - BWA-MEM2 index must already exist (resources/reference/)
#     If not: sbatch --partition=highmem --mem=200GB submit_job_BIH.sh config/config.yaml
#   - DeepVariant Singularity image and Delly exclusion list must exist.
#     Run install.sh --skip-deepvariant if only the exclusion list is missing.
# ============================================================

CONFIGFILE="${1:-config/config.yaml}"
SAMPLE_ID="${2:-}"
SAMPLE_R1="${3:-}"
SAMPLE_R2="${4:-}"

# --- Singularity ---
# Apptainer (Singularity successor) is pre-installed as a system package on this cluster.
# No module load needed — singularity/apptainer is already in PATH.

# --- Conda setup ---
MINIFORGE_PATH="/data/cephfs-1/work/groups/kircher/users/alhassa_m/miniforge"
source "${MINIFORGE_PATH}/etc/profile.d/conda.sh"
conda activate snakemake

# --- Setup ---
mkdir -p logs

# Merge stdout + stderr into one timestamped file — easy to share
TIMESTAMP=$(date +%Y%m%dT%H%M%S)
RUN_LOG="logs/run_${TIMESTAMP}_${SLURM_JOB_ID:-interactive}.log"
exec > >(tee -a "$RUN_LOG") 2>&1

echo "=============================================="
echo "  VariantPiper (BIH HPC)"
echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID:-interactive}"
echo "Node:              $(hostname)"
echo "Working directory: $(pwd)"
echo "Snakemake version: $(snakemake --version)"
echo "Date:              $(date)"
echo "CPUs:              ${SLURM_CPUS_PER_TASK}"
echo "Memory:            ${SLURM_MEM_PER_NODE:-unknown} MB"
echo "Config:            $CONFIGFILE"
if [ -n "$SAMPLE_ID" ]; then
    echo "Sample (inline):   $SAMPLE_ID"
    echo "  R1: $SAMPLE_R1"
    echo "  R2: $SAMPLE_R2"
fi
echo "Run log:           $RUN_LOG"
echo "=============================================="

# --- Build Snakemake config overrides ---
# Use a bash array so each --config item is passed as a single quoted token,
# avoiding word-splitting on spaces inside JSON values.

# Singularity bind: always include cephfs-1 (reference + output);
# extend to cover the filesystem where R1/R2 live if different.
BIND="/data/cephfs-1"
if [ -n "$SAMPLE_R1" ]; then
    R1_ROOT=$(echo "$SAMPLE_R1" | grep -oP '^/[^/]+/[^/]+' || echo "")
    if [ -n "$R1_ROOT" ] && [ "$R1_ROOT" != "/data/cephfs-1" ]; then
        BIND="${BIND},${R1_ROOT}"
    fi
fi

CONFIG_ARGS=(--config "singularity_bind=${BIND}")

# Inline sample override: compact JSON (no spaces) avoids word-splitting
if [ -n "$SAMPLE_ID" ] && [ -n "$SAMPLE_R1" ] && [ -n "$SAMPLE_R2" ]; then
    SAMPLES_JSON="{\"${SAMPLE_ID}\":{\"R1\":\"${SAMPLE_R1}\",\"R2\":\"${SAMPLE_R2}\"}}"
    CONFIG_ARGS+=(--config "samples=${SAMPLES_JSON}")
fi

# --- Refresh mtimes so scratch cleanup does not delete resource files ---
# Scratch deletes files not modified for 14 days using mtime. Downloaded/decompressed
# files may carry old mtimes from the source server. Touch them before each run.
touch resources/reference/hg38.fa resources/reference/hg38.fa.* \
      resources/singularity/*.sif resources/delly/*.tsv 2>/dev/null || true

# --- Run ---
snakemake \
    --snakefile workflow/Snakefile \
    --configfile "$CONFIGFILE" \
    "${CONFIG_ARGS[@]}" \
    --use-conda \
    --conda-prefix /data/cephfs-1/work/groups/kircher/users/alhassa_m/snakemake-conda \
    --cores "${SLURM_CPUS_PER_TASK}" \
    --rerun-incomplete

EXIT_CODE=$?

echo "=============================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "Pipeline finished successfully"
else
    echo "Pipeline FAILED with exit code $EXIT_CODE"
    echo ""
    echo "--- Last 50 lines of Snakemake internal log ---"
    SMLOG=$(ls -t .snakemake/log/*.snakemake.log 2>/dev/null | head -1)
    if [ -n "$SMLOG" ]; then
        echo "Snakemake log: $SMLOG"
        tail -50 "$SMLOG"
    fi
fi
echo "=============================================="
echo "Full run log: $RUN_LOG"
echo "=============================================="

exit "$EXIT_CODE"
