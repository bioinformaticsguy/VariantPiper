#!/bin/bash

#SBATCH --partition=shortterm
#SBATCH --time=3-00:00:00
#SBATCH --nodes=1
#SBATCH -c 16
#SBATCH --mem=64GB
#SBATCH --job-name=variantpiper
#SBATCH --output=logs/slurm_%j_%u_%N.out
#SBATCH --error=logs/slurm_%j_%u_%N.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=alihassan1697@gmail.com

# ============================================================
# VariantPiper — SLURM submission script (omics cluster)
# ============================================================
# Usage:
#   sbatch submit_job_omics.sh <configfile> [sample_id R1 R2]
#
# Examples:
#   # Use a config file (standard):
#   sbatch submit_job_omics.sh config/config.yaml
#
#   # Override sample inline — no separate config file needed:
#   sbatch submit_job_omics.sh config/config.yaml HG002 \
#     /data/.../R1.fastq.gz \
#     /data/.../R2.fastq.gz
#
# The inline sample replaces whatever samples are in the config file.
#
# Override any SLURM resource at submission time, e.g.:
#   sbatch --mem=200GB submit_job_omics.sh config/config.yaml   # BWA-MEM2 index build
#   sbatch --time=2-00:00:00 submit_job_omics.sh config/config.yaml
# ============================================================

CONFIGFILE="${1:-config/config.yaml}"
SAMPLE_ID="${2:-}"
SAMPLE_R1="${3:-}"
SAMPLE_R2="${4:-}"

# --- Singularity ---
module load singularity/v4.1.3

# --- Conda setup ---
MINIFORGE_PATH="/work/hassan/hassan/miniforge"
source "${MINIFORGE_PATH}/etc/profile.d/conda.sh"
conda activate snakemake

# --- Setup ---
mkdir -p logs

# Merge stdout + stderr into one timestamped file — easy to share
TIMESTAMP=$(date +%Y%m%dT%H%M%S)
RUN_LOG="logs/run_${TIMESTAMP}_${SLURM_JOB_ID:-interactive}.log"
exec > >(tee -a "$RUN_LOG") 2>&1

echo "=============================================="
echo "  VariantPiper (omics cluster)"
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
CONFIG_ARGS=(--config "singularity_bind=/data")

if [ -n "$SAMPLE_ID" ] && [ -n "$SAMPLE_R1" ] && [ -n "$SAMPLE_R2" ]; then
    SAMPLES_JSON="{\"${SAMPLE_ID}\":{\"R1\":\"${SAMPLE_R1}\",\"R2\":\"${SAMPLE_R2}\"}}"
    CONFIG_ARGS+=(--config "samples=${SAMPLES_JSON}")
fi

# --- Unlock in case a previous job was killed or timed out ---
snakemake --snakefile workflow/Snakefile --configfile "$CONFIGFILE" --unlock 2>/dev/null || true

# --- Run ---
snakemake \
    --snakefile workflow/Snakefile \
    --configfile "$CONFIGFILE" \
    "${CONFIG_ARGS[@]}" \
    --use-conda \
    --conda-prefix /work/hassan/hassan/snakemake-conda \
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
