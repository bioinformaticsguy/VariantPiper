#!/bin/bash
# ============================================================
# VariantPiper — batch submission script
# Submits one SLURM job per sample in a TSV samplesheet.
# ============================================================
# Usage:
#   bash submit_batch.sh <configfile> <batch_samplesheet.tsv> [extra sbatch args]
#
# Examples:
#   bash submit_batch.sh config/config_batch.yaml samplesheets/batch1.tsv
#   bash submit_batch.sh config/config_batch.yaml samplesheets/batch1.tsv --mem=128GB
#   bash submit_batch.sh config/config_batch.yaml samplesheets/batch1.tsv --time=4-00:00:00
#
# Each sample gets its own SLURM job running submit_job_OMICS.sh.
# Per-sample samplesheets are written to samplesheets/per_sample/.
# ============================================================

set -euo pipefail

CONFIGFILE="${1:?ERROR: provide a config file as argument 1}"
BATCHSHEET="${2:?ERROR: provide a batch samplesheet TSV as argument 2}"
shift 2
EXTRA_SBATCH=("$@")   # any extra sbatch flags, e.g. --mem=128GB

if [ ! -f "$CONFIGFILE" ]; then
    echo "ERROR: config file not found: $CONFIGFILE" >&2
    exit 1
fi
if [ ! -f "$BATCHSHEET" ]; then
    echo "ERROR: samplesheet not found: $BATCHSHEET" >&2
    exit 1
fi

mkdir -p samplesheets/per_sample logs

# Extract unique sample IDs from column 1 (skip header)
SAMPLES=$(awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$BATCHSHEET" | sort -u)

if [ -z "$SAMPLES" ]; then
    echo "ERROR: no samples found in $BATCHSHEET" >&2
    exit 1
fi

HEADER=$(head -1 "$BATCHSHEET")
N=0

echo "=============================================="
echo "  VariantPiper batch submission"
echo "=============================================="
echo "Config:      $CONFIGFILE"
echo "Samplesheet: $BATCHSHEET"
echo "Extra sbatch: ${EXTRA_SBATCH[*]:-none}"
echo "----------------------------------------------"

for SAMPLE in $SAMPLES; do
    OUTSHEET="samplesheets/per_sample/${SAMPLE}.tsv"

    # Write per-sample samplesheet (header + rows for this sample)
    printf '%s\n' "$HEADER" > "$OUTSHEET"
    awk -F'\t' -v s="$SAMPLE" 'NR > 1 && $1 == s' "$BATCHSHEET" >> "$OUTSHEET"

    JOB_OUTPUT=$(sbatch \
        --job-name="vp_${SAMPLE}" \
        "${EXTRA_SBATCH[@]}" \
        submit_job_OMICS.sh "$CONFIGFILE" "$OUTSHEET")
    JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')

    echo "  Submitted $SAMPLE → job $JOB_ID  (sheet: $OUTSHEET)"
    N=$((N + 1))
done

echo "----------------------------------------------"
echo "  $N job(s) submitted."
echo "=============================================="
