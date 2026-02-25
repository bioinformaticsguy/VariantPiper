#!/bin/bash

#SBATCH --partition=shortterm
#SBATCH --time=1-00:00:00
#SBATCH --nodes=1
#SBATCH -c 16
#SBATCH --mem=200GB
#SBATCH --job-name=variantpiper
#SBATCH --output=logs/slurm_%j_%u_%N.out
#SBATCH --error=logs/slurm_%j_%u_%N.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=alihassan1697@gmail.com

# ============================================================
# VariantPiper — SLURM Submission Script
# ============================================================
# Runs the full pipeline inside a single SLURM job.
# All steps (including BWA-MEM2 indexing) execute on the
# allocated node — no nested SLURM job submission.
#
# Resources:
#   16 CPUs  — used by bwa-mem2 mem (--threads 16)
#   200 GB   — required by bwa-mem2 index (~143 GB peak on hg38, still growing)
#
# Submit with: sbatch submit_job.sh
# ============================================================

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
echo "Memory:            128 GB"
echo "Run log:           $RUN_LOG"
echo "=============================================="

# --- Run ---
snakemake \
    --snakefile workflow/Snakefile \
    --configfile config/config.yaml \
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
