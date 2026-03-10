# VariantPiper

A Snakemake pipeline for germline variant calling from paired-end Illumina WGS data.

## Pipeline steps

| Step | Tool | Status |
|------|------|--------|
| 1. Quality control | fastp | ready |
| 2. Alignment | BWA-MEM2 | in progress |
| 3. SNV/indel calling | DeepVariant | ready |
| 4. SV calling | Delly | ready |
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

This downloads the hg38 reference FASTA and pulls the DeepVariant Singularity
image. Singularity is loaded automatically from the cluster module system.

Reference indexes (samtools faidx, BWA-MEM2) are **not** created here — they are
generated automatically by Snakemake on the first pipeline run using dedicated rules
with their own conda environments.

```bash
# Skip DeepVariant image pull
bash install.sh --skip-deepvariant

# If singularity is loaded under a different module name (e.g. apptainer)
bash install.sh --singularity-module apptainer

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

**On an HPC cluster** (SLURM via the bundled profile):

First, install the SLURM executor plugin once into your snakemake environment:

```bash
conda activate snakemake
conda install -c conda-forge -c bioconda snakemake-executor-plugin-slurm
```

Edit `profiles/slurm/config.yaml` and set `slurm_partition` to match your cluster.
Then run:

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/config.yaml \
          --profile profiles/slurm
```

Snakemake will submit each rule as a separate SLURM job, using the `mem_mb`,
`runtime`, and `threads` values defined in each rule. Never run the full
pipeline (especially BWA-MEM2 indexing) inside an interactive `srun` session —
it will be OOM-killed.

---

## Output structure

```
output/
└── {sample}/
    ├── logs/
    │   ├── fastp.log
    │   ├── bwa_mem2_align.log
    │   ├── picard_markduplicates.log
    │   ├── samtools_index.log
    │   └── deepvariant.log
    ├── qc/
    │   ├── {sample}_R1.trimmed.fastq.gz
    │   ├── {sample}_R2.trimmed.fastq.gz
    │   ├── {sample}_fastp.html
    │   └── {sample}_fastp.json
    ├── alignment/
    │   ├── {sample}.markdup.bam        ← duplicate-marked, sorted BAM
    │   ├── {sample}.markdup.bam.bai    ← BAM index
    │   └── {sample}.markdup_metrics.txt
    ├── snv_calls/
    │   ├── {sample}.vcf.gz             ← SNV + indel calls (DeepVariant)
    │   ├── {sample}.vcf.gz.tbi
    │   ├── {sample}.g.vcf.gz           ← gVCF (for cohort genotyping)
    │   └── {sample}.g.vcf.gz.tbi
    └── sv_calls/
        ├── {sample}.sv.vcf.gz          ← structural variant calls (Delly)
        └── {sample}.sv.vcf.gz.tbi
```

> The intermediate sorted BAM (`{sample}.sorted.bam`) is automatically deleted
> by Snakemake once duplicate marking completes.

---

## Test data

Small test dataset (10,000 reads) is provided in `test_data/` for local development.
The sample ID `test` in `config/config.yaml` points to these files — replace it with
your real sample ID and paths when running on actual data.
