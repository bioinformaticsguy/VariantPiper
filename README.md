# VariantPiper

A Snakemake pipeline for germline variant calling from paired-end Illumina WGS data.

## Pipeline steps

| Step | Tool | Status |
|------|------|--------|
| 1. Quality control | fastp | ready |
| 2. Alignment | BWA-MEM2 | in progress |
| 3. SNV/indel calling | DeepVariant | planned |
| 4. SV calling | TBD | planned |
| 5. Cohort joint-genotyping | GATK | planned |

---

## Requirements

- [Miniforge](https://github.com/conda-forge/miniforge) (Anaconda/Miniconda and the `defaults` channel are **not** supported)
- Snakemake >= 7

Install Snakemake into a dedicated conda environment:

```bash
conda create -n snakemake -c conda-forge -c bioconda snakemake
conda activate snakemake
```

---

## Setup

**1. Clone the repository**

```bash
git clone <repo-url>
cd VariantPiper
```

**2. Download and index all resources**

```bash
bash install.sh
```

This downloads the hg38 reference genome, creates samtools and BWA-MEM2 indexes,
and pulls the DeepVariant Singularity image. Run on a **compute node** (not the
login node) — BWA-MEM2 indexing needs ~60 GB RAM.

Individual steps can be skipped if already done:

```bash
# Skip BWA-MEM2 indexing (e.g. if index already exists)
bash install.sh --skip-bwa-index

# Skip DeepVariant image pull (e.g. if singularity is not yet loaded)
bash install.sh --skip-deepvariant

# Custom output directories
bash install.sh --ref-dir /path/to/ref --singularity-dir /path/to/sif
```

See `bash install.sh --help` for all options.

**3. Configure your samples**

Edit `config/config.yaml` and add your samples under the `samples` section:

```yaml
samples:
  GS487:                                  # replace with your sample ID
    R1: "input/GS487/GS487_R1.fastq.gz"  # path to R1 (relative to project root)
    R2: "input/GS487/GS487_R2.fastq.gz"  # path to R2

  sample2:
    R1: "input/sample2/sample2_R1.fastq.gz"
    R2: "input/sample2/sample2_R2.fastq.gz"
```

**4. Set the reference genome path** (required from Step 2 onward)

```yaml
reference: "resources/reference/hg38.fa"
```

If you used a custom `--ref-dir` with `install.sh`, update this path accordingly.

---

## Running the pipeline

All commands should be run from the **project root**.

**Dry-run** (check what will be executed without running anything):

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/config.yaml \
          --use-conda \
          --cores 4 \
          --dry-run
```

**Full run:**

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/config.yaml \
          --use-conda \
          --cores 4
```

**On an HPC cluster** (SLURM example):

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/config.yaml \
          --use-conda \
          --executor slurm \
          --jobs 50
```

---

## Output structure

```
output/
└── {sample}/
    ├── logs/
    │   └── fastp.log
    └── qc/
        ├── {sample}_R1.trimmed.fastq.gz
        ├── {sample}_R2.trimmed.fastq.gz
        ├── {sample}_fastp.html
        └── {sample}_fastp.json
```

---

## Test data

Small test dataset (10,000 reads) is provided in `test_data/` for local development.
The sample ID `test` in `config/config.yaml` points to these files — replace it with
your real sample ID and paths when running on actual data.
