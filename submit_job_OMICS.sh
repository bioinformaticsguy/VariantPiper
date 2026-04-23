#!/bin/bash

#SBATCH --partition=shortterm
#SBATCH --time=3-00:00:00
#SBATCH --nodes=1
#SBATCH -c 16
#SBATCH --mem=128GB
#SBATCH --job-name=variantpiper
#SBATCH --output=logs/slurm_%j_%u_%N.out
#SBATCH --error=logs/slurm_%j_%u_%N.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=alihassan1697@gmail.com

# ============================================================
# VariantPiper — SLURM submission script (omics cluster)
# ============================================================
# Usage:
#   sbatch submit_job_OMICS.sh <configfile> [samplesheet]
#
# Examples:
#   # Config already has samplesheet: key:
#   sbatch submit_job_OMICS.sh config/config_batch.yaml
#
#   # Override samplesheet at submission time:
#   sbatch submit_job_OMICS.sh config/config_batch.yaml samplesheets/A4842_DNA_25.tsv
#
# Override any SLURM resource at submission time, e.g.:
#   sbatch --mem=200GB submit_job_OMICS.sh config/config.yaml   # BWA-MEM2 index build
#   sbatch --time=2-00:00:00 submit_job_OMICS.sh config/config.yaml
# ============================================================

CONFIGFILE="${1:-config/config.yaml}"
SAMPLESHEET="${2:-}"

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
if [ -n "$SAMPLESHEET" ]; then
    echo "Samplesheet:       $SAMPLESHEET"
fi
echo "Run log:           $RUN_LOG"
echo "=============================================="

# --- Build Snakemake config overrides ---
CONFIG_ARGS=(--config "singularity_bind=/data")

if [ -n "$SAMPLESHEET" ]; then
    CONFIG_ARGS+=(--config "samplesheet=${SAMPLESHEET}")
fi

# --- Ensure the snakemake metadata directory exists ---
# Multiple jobs starting simultaneously race to create .snakemake/locks/;
# pre-creating it avoids a FileNotFoundError in the loser jobs.
mkdir -p .snakemake/locks

# --- Unlock in case a previous job was killed or timed out ---
snakemake --snakefile workflow/Snakefile --configfile "$CONFIGFILE" --unlock 2>/dev/null || true

# --- Run ---
# --nolock: safe because each sample writes to its own output/{sample}/ directory;
# no two jobs share output paths, so Snakemake's file locking is not needed and
# only causes conflicts when many jobs start at the same time.
snakemake \
    --snakefile workflow/Snakefile \
    --configfile "$CONFIGFILE" \
    "${CONFIG_ARGS[@]}" \
    --use-conda \
    --conda-prefix /work/hassan/hassan/snakemake-conda \
    --cores "${SLURM_CPUS_PER_TASK}" \
    --rerun-incomplete \
    --nolock

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
