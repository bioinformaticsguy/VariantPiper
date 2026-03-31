#!/bin/bash

#SBATCH --partition=shortterm
#SBATCH --time=1-00:00:00
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
#   sbatch submit_job_omics.sh [config/config.yaml]
#
# Config defaults to config/config.yaml if not provided.
#
# Override any SLURM resource at submission time, e.g.:
#   sbatch --time=2-00:00:00 submit_job_omics.sh config/config_HG002.yaml
#   sbatch --mem=200GB submit_job_omics.sh              # first run: BWA-MEM2 index
#   sbatch --job-name=HG002 submit_job_omics.sh config/config_HG002.yaml
#
# Prerequisites:
#   - BWA-MEM2 index must already exist (resources/reference/)
#     If not: sbatch --mem=200GB submit_job.sh to build it first.
#   - DeepVariant Singularity image and Delly exclusion list must exist.
#     Run install.sh --skip-deepvariant if only the exclusion list is missing.
# ============================================================

CONFIGFILE="${1:-config/config.yaml}"

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
echo "  VariantPiper"
echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID:-interactive}"
echo "Node:              $(hostname)"
echo "Working directory: $(pwd)"
echo "Snakemake version: $(snakemake --version)"
echo "Date:              $(date)"
echo "CPUs:              ${SLURM_CPUS_PER_TASK}"
echo "Memory:            ${SLURM_MEM_PER_NODE:-unknown} MB"
echo "Config:            $CONFIGFILE"
echo "Run log:           $RUN_LOG"
echo "=============================================="

# --- Run ---
snakemake \
    --snakefile workflow/Snakefile \
    --configfile "$CONFIGFILE" \
    --use-conda \
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
