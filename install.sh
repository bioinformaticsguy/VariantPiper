#!/bin/bash
#
# VariantPiper — Resource Setup Script
#
# Downloads reference files required by the pipeline.
# Reference indexes (samtools faidx, BWA-MEM2) are generated automatically
# by Snakemake rules on the first pipeline run — no manual setup needed.
#
# Usage: ./install.sh [options]
#   -r, --ref-dir DIR             Reference genome directory (default: ./resources/reference)
#   -s, --singularity-dir DIR     Singularity images directory (default: ./resources/singularity)
#   --deepvariant-version VER     DeepVariant version to pull (default: 1.6.1)
#   --singularity-module NAME     Module name to load for Singularity (default: singularity)
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
SINGULARITY_MODULE="singularity"
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
    --singularity-module NAME     Module name for Singularity (default: singularity)
                                  Use this if your cluster loads it under a different name,
                                  e.g. --singularity-module apptainer
    --skip-deepvariant            Skip DeepVariant Singularity image pull
    --force                       Force re-download even if files already exist
    -h, --help                    Show this help message

This script will:
    1. Download UCSC hg38 reference genome FASTA (~970 MB compressed, ~3.2 GB uncompressed)
    2. Pull the DeepVariant Singularity image (~15 GB)

Reference indexes (samtools faidx, BWA-MEM2) are NOT generated here.
They are created automatically by Snakemake on the first pipeline run using
dedicated rules with their own conda environments — no manual tool installation needed.

Requirements:
    - wget or curl
    - Singularity (loaded automatically via the module system)

Notes:
    - The resulting resource paths match the defaults in config/config.yaml.
      If you use --ref-dir or --singularity-dir, update config/config.yaml accordingly.

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
        --singularity-module)      SINGULARITY_MODULE="$2";    shift 2 ;;
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

    # Singularity — try PATH first, then module system
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        if ! command -v singularity &> /dev/null; then
            log_info "singularity not in PATH — attempting: module load ${SINGULARITY_MODULE}"
            load_module "${SINGULARITY_MODULE}"
            if ! command -v singularity &> /dev/null; then
                log_warn "Could not load singularity. DeepVariant image pull will be skipped."
                log_warn "To retry: module load ${SINGULARITY_MODULE} && ./install.sh --skip-deepvariant is NOT needed,"
                log_warn "just re-run ./install.sh after loading the module."
                SKIP_DEEPVARIANT=true
            else
                log_success "singularity loaded via module ($(singularity --version))"
            fi
        else
            log_success "singularity available ($(singularity --version))"
        fi
    else
        log_info "DeepVariant image pull skipped (--skip-deepvariant)"
    fi

    log_success "Requirement check done"
}

# ---------------------------------------------------------------------------
# Module loader — handles clusters where 'module' is a shell function
# that needs to be initialised first
# ---------------------------------------------------------------------------
load_module() {
    local module_name="$1"

    # If module command is already available, use it directly
    if command -v module &> /dev/null; then
        module load "$module_name" && return 0
    fi

    # Otherwise try common module system init paths
    local init_paths=(
        /etc/profile.d/modules.sh
        /usr/share/lmod/lmod/init/bash
        /usr/share/modules/init/bash
    )
    if [ -n "${MODULESHOME:-}" ]; then
        init_paths=("$MODULESHOME/init/bash" "${init_paths[@]}")
    fi

    for init in "${init_paths[@]}"; do
        if [ -f "$init" ]; then
            # shellcheck source=/dev/null
            source "$init"
            module load "$module_name" && return 0
        fi
    done

    return 1
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

    if [ ! -f "$ref_fa" ] || [ "$FORCE" = true ]; then
        if [ ! -f "$ref_gz" ] || [ "$FORCE" = true ]; then
            download_file \
                "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz" \
                "$ref_gz" \
                "UCSC hg38 FASTA (~970 MB)" || return 1
            log_success "Reference downloaded: $ref_gz"
        else
            log_info "Compressed reference already exists, skipping download"
        fi

        log_info "Decompressing reference (~3.2 GB)..."
        gunzip -k "$ref_gz"
        log_success "Decompressed: $ref_fa"
    else
        log_info "Reference FASTA already exists, skipping"
    fi

    log_success "Reference genome ready: $ref_fa"
}

# ---------------------------------------------------------------------------
# Step 2 — DeepVariant Singularity image
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
    echo "  hg38.fa                 — reference FASTA"
    echo ""
    echo "  Indexes will be generated automatically on the first pipeline run:"
    echo "  hg38.fa.fai             — samtools faidx (via Snakemake + conda)"
    echo "  hg38.fa.{0123,...}      — BWA-MEM2 index  (via Snakemake + conda)"
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        echo ""
        echo "Singularity images in $SINGULARITY_DIR:"
        echo "  deepvariant_${DEEPVARIANT_VERSION}.sif"
    fi
    echo ""
    echo "Make sure config/config.yaml points to the correct paths:"
    echo "  reference:       \"$REF_DIR/hg38.fa\""
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
    echo "  1. Download UCSC hg38 reference FASTA  (~970 MB compressed / ~3.2 GB uncompressed)"
    if [ "$SKIP_DEEPVARIANT" = false ]; then
        echo "  2. Pull DeepVariant v${DEEPVARIANT_VERSION} image   (~15 GB)"
    else
        echo "  2. DeepVariant image pull              SKIPPED"
    fi
    echo ""
    echo "  Output directories:"
    echo "    Reference  : $REF_DIR"
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
    pull_deepvariant
    echo ""
    print_summary
}

main
