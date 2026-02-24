#!/bin/bash
#
# VariantPiper — Resource Setup Script
#
# Downloads and indexes all reference files required by the pipeline.
# Conda environments are managed by Snakemake (--use-conda) and do not
# need manual setup.
#
# Usage: ./install.sh [options]
#   -r, --ref-dir DIR             Reference genome directory (default: ./resources/reference)
#   -s, --singularity-dir DIR     Singularity images directory (default: ./resources/singularity)
#   --deepvariant-version VER     DeepVariant version to pull (default: 1.6.1)
#   --skip-bwa-index              Skip BWA-MEM2 indexing
#   --skip-deepvariant            Skip DeepVariant Singularity image pull
#   --force                       Force re-download even if files already exist
#   -h, --help                    Show this help message
#

set -e

# ---------------------------------------------------------------------------
# Default configuration
# ---------------------------------------------------------------------------
REF_DIR="${PWD}/resources/reference"
SINGULARITY_DIR="${PWD}/resources/singularity"
DEEPVARIANT_VERSION="1.6.1"
SKIP_BWA_INDEX=false
SKIP_DEEPVARIANT=false
FORCE=false

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
    cat << 'EOF'
VariantPiper — Resource Setup Script

Usage: ./install.sh [options]

Options:
    -r, --ref-dir DIR             Reference genome directory (default: ./resources/reference)
    -s, --singularity-dir DIR     Singularity images directory (default: ./resources/singularity)
    --deepvariant-version VER     DeepVariant version to pull (default: 1.6.1)
    --skip-bwa-index              Skip BWA-MEM2 indexing (use if index already exists
                                  or you want to index manually later)
    --skip-deepvariant            Skip DeepVariant Singularity image pull
    --force                       Force re-download even if files already exist
    -h, --help                    Show this help message

This script will:
    1. Download UCSC hg38 reference genome FASTA (~970 MB compressed, ~3.2 GB uncompressed)
    2. Index the reference with samtools faidx
    3. Create BWA-MEM2 index files (~30 GB disk, ~60 GB RAM — skip with --skip-bwa-index)
    4. Pull the DeepVariant Singularity image (~15 GB)  — skip with --skip-deepvariant

Requirements:
    - wget or curl
    - samtools       (conda install -c conda-forge -c bioconda samtools)
    - bwa-mem2       (conda install -c conda-forge -c bioconda bwa-mem2)   [unless --skip-bwa-index]
    - singularity    (available as a module on most HPC clusters)          [unless --skip-deepvariant]

Notes:
    - BWA-MEM2 indexing requires ~60 GB of RAM. Run this on a compute node,
      not the login node (e.g. srun --mem=65G --pty bash -i on SLURM clusters).
    - The resulting resource paths match the defaults in config/config.yaml.
      If you change --ref-dir or --singularity-dir, update config/config.yaml accordingly.

Conda environments are managed automatically by Snakemake.
To run the pipeline after setup:
    conda activate snakemake
    snakemake --snakefile workflow/Snakefile --configfile config/config.yaml --use-conda --cores 4
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--ref-dir)              REF_DIR="$2";               shift 2 ;;
        -s|--singularity-dir)      SINGULARITY_DIR="$2";       shift 2 ;;
        --deepvariant-version)     DEEPVARIANT_VERSION="$2";   shift 2 ;;
        --skip-bwa-index)          SKIP_BWA_INDEX=true;        shift ;;
        --skip-deepvariant)        SKIP_DEEPVARIANT=true;      shift ;;
        --force)                   FORCE=true;                 shift ;;
        -h|--help)                 show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Requirements check
# ---------------------------------------------------------------------------
check_requirements() {
    log_info "Checking requirements..."

    # Download tool
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log_error "Neither wget nor curl found. Please install one of them."
        exit 1
    fi
    log_success "Download tool available ($(command -v wget &>/dev/null && echo wget || echo curl))"

    # samtools
    if ! command -v samtools &> /dev/null; then
        log_error "samtools not found. Install it with:"
        log_error "  conda install -c conda-forge -c bioconda samtools"
        exit 1
    fi
    log_success "samtools available ($(samtools --version | head -1))"

    # bwa-mem2 (optional)
    if [ "$SKIP_BWA_INDEX" = false ]; then
        if ! command -v bwa-mem2 &> /dev/null; then
            log_warn "bwa-mem2 not found — BWA-MEM2 indexing will be skipped."
            log_warn "Install it with: conda install -c conda-forge -c bioconda bwa-mem2"
            log_warn "Then re-run: ./install.sh --skip-deepvariant"
            SKIP_BWA_INDEX=true
        else
            log_success "bwa-mem2 available ($(bwa-mem2 version 2>&1 | head -1))"
        fi
    else
        log_info "BWA-MEM2 indexing skipped (--skip-bwa-index)"
    fi

    # singularity (optional)
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        if ! command -v singularity &> /dev/null; then
            log_warn "singularity not found — DeepVariant image pull will be skipped."
            log_warn "On HPC clusters singularity is usually available via: module load singularity"
            log_warn "Then re-run: ./install.sh --skip-bwa-index"
            SKIP_DEEPVARIANT=true
        else
            log_success "singularity available ($(singularity --version))"
        fi
    else
        log_info "DeepVariant image pull skipped (--skip-deepvariant)"
    fi

    log_success "Requirement check done"
}

# ---------------------------------------------------------------------------
# Download helper — wget/curl with retries
# ---------------------------------------------------------------------------
download_file() {
    local url="$1"
    local output="$2"
    local desc="${3:-file}"
    local max_retries=3
    local retry=0

    log_info "Downloading $desc..."

    while [ $retry -lt $max_retries ]; do
        if command -v wget &> /dev/null; then
            if [ -t 1 ]; then
                wget -c --progress=bar:force -O "$output" "$url" 2>&1 && return 0
            else
                wget -c -q -O "$output" "$url" && return 0
            fi
        else
            if [ -t 1 ]; then
                curl -L -C - --progress-bar -o "$output" "$url" && return 0
            else
                curl -sL -C - -o "$output" "$url" && return 0
            fi
        fi

        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            log_warn "Download failed, retrying ($retry/$max_retries)..."
            sleep 5
        fi
    done

    log_error "Failed to download $desc after $max_retries attempts"
    return 1
}

# ---------------------------------------------------------------------------
# Step 1 — Reference genome
# ---------------------------------------------------------------------------
download_reference() {
    log_info "Setting up hg38 reference genome..."
    mkdir -p "$REF_DIR"

    local ref_gz="$REF_DIR/hg38.fa.gz"
    local ref_fa="$REF_DIR/hg38.fa"

    # Download
    if [ ! -f "$ref_gz" ] && [ ! -f "$ref_fa" ] || [ "$FORCE" = true ]; then
        download_file \
            "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz" \
            "$ref_gz" \
            "UCSC hg38 FASTA (~970 MB)" || return 1
        log_success "Reference downloaded: $ref_gz"
    else
        log_info "Reference already exists, skipping download"
    fi

    # Decompress (samtools faidx requires an uncompressed or bgzipped FASTA)
    if [ ! -f "$ref_fa" ] || [ "$FORCE" = true ]; then
        log_info "Decompressing reference (~3.2 GB)..."
        gunzip -k "$ref_gz"
        log_success "Decompressed: $ref_fa"
    else
        log_info "Uncompressed FASTA already exists, skipping decompression"
    fi

    log_success "Reference genome ready: $ref_fa"
}

# ---------------------------------------------------------------------------
# Step 2 — samtools faidx index
# ---------------------------------------------------------------------------
index_fai() {
    local ref_fa="$REF_DIR/hg38.fa"
    local ref_fai="$REF_DIR/hg38.fa.fai"

    log_info "Creating samtools faidx index..."

    if [ ! -f "$ref_fai" ] || [ "$FORCE" = true ]; then
        samtools faidx "$ref_fa"
        log_success "FAI index created: $ref_fai"
    else
        log_info "FAI index already exists, skipping"
    fi
}

# ---------------------------------------------------------------------------
# Step 3 — BWA-MEM2 index
# ---------------------------------------------------------------------------
index_bwa_mem2() {
    if [ "$SKIP_BWA_INDEX" = true ]; then
        log_info "Skipping BWA-MEM2 indexing (--skip-bwa-index)"
        return 0
    fi

    local ref_fa="$REF_DIR/hg38.fa"

    log_info "Creating BWA-MEM2 index..."
    log_warn "This requires ~60 GB RAM and ~30 GB disk space and may take several hours."
    log_warn "Make sure you are on a compute node, not the login node."

    # Check if index already complete (all expected files present)
    local all_present=true
    for ext in 0123 amb ann bwt.2bit.64 pac; do
        [ ! -f "${ref_fa}.${ext}" ] && all_present=false && break
    done

    if [ "$all_present" = true ] && [ "$FORCE" = false ]; then
        log_info "BWA-MEM2 index already exists, skipping"
        return 0
    fi

    bwa-mem2 index "$ref_fa"
    log_success "BWA-MEM2 index created in $REF_DIR"
}

# ---------------------------------------------------------------------------
# Step 4 — DeepVariant Singularity image
# ---------------------------------------------------------------------------
pull_deepvariant() {
    if [ "$SKIP_DEEPVARIANT" = true ]; then
        log_info "Skipping DeepVariant image pull (--skip-deepvariant)"
        return 0
    fi

    mkdir -p "$SINGULARITY_DIR"

    local image="$SINGULARITY_DIR/deepvariant_${DEEPVARIANT_VERSION}.sif"

    log_info "Pulling DeepVariant v${DEEPVARIANT_VERSION} Singularity image (~15 GB)..."

    if [ ! -f "$image" ] || [ "$FORCE" = true ]; then
        singularity pull "$image" \
            "docker://google/deepvariant:${DEEPVARIANT_VERSION}" || return 1
        log_success "DeepVariant image saved: $image"
    else
        log_info "DeepVariant image already exists, skipping"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "=============================================="
    echo "  Setup Complete!"
    echo "=============================================="
    echo ""
    echo "Reference files in $REF_DIR:"
    echo "  hg38.fa              — reference FASTA"
    echo "  hg38.fa.fai          — samtools index"
    if [ "$SKIP_BWA_INDEX" = false ]; then
        echo "  hg38.fa.0123         — BWA-MEM2 index"
        echo "  hg38.fa.bwt.2bit.64  — BWA-MEM2 index"
        echo "  hg38.fa.amb/ann/pac  — BWA-MEM2 index"
    fi
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        echo ""
        echo "Singularity images in $SINGULARITY_DIR:"
        echo "  deepvariant_${DEEPVARIANT_VERSION}.sif"
    fi
    echo ""
    echo "Make sure config/config.yaml points to the correct paths:"
    echo "  reference: \"$REF_DIR/hg38.fa\""
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        echo "  deepvariant_sif: \"$SINGULARITY_DIR/deepvariant_${DEEPVARIANT_VERSION}.sif\""
    fi
    echo ""
    echo "To run the pipeline:"
    echo "  conda activate snakemake"
    echo "  snakemake --snakefile workflow/Snakefile \\"
    echo "            --configfile config/config.yaml \\"
    echo "            --use-conda --cores 4"
    echo ""
    echo "Snakemake will create all required conda environments on the first run."
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  VariantPiper — Resource Setup"
    echo "=============================================="
    echo ""

    check_requirements

    echo ""
    log_info "Setup will:"
    echo "  1. Download UCSC hg38 reference FASTA  (~970 MB compressed)"
    echo "  2. Index reference with samtools faidx"
    if [ "$SKIP_BWA_INDEX" = false ]; then
        echo "  3. Create BWA-MEM2 index               (~30 GB disk, ~60 GB RAM)"
    else
        echo "  3. BWA-MEM2 indexing                   SKIPPED"
    fi
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        echo "  4. Pull DeepVariant v${DEEPVARIANT_VERSION} image   (~15 GB)"
    else
        echo "  4. DeepVariant image pull              SKIPPED"
    fi
    echo ""
    echo "  Output directories:"
    echo "    Reference : $REF_DIR"
    echo "    Singularity: $SINGULARITY_DIR"
    echo ""

    if [ -t 0 ]; then
        read -p "Continue? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "Setup cancelled"
            exit 0
        fi
    else
        log_info "Non-interactive mode — proceeding..."
    fi

    echo ""
    download_reference
    echo ""
    index_fai
    echo ""
    index_bwa_mem2
    echo ""
    pull_deepvariant
    echo ""
    print_summary
}

main
