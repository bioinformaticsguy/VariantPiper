# Usage

VariantPiper v1.0.0 is a Phase I short-read WGS pipeline. It produces aligned
BAMs, QC outputs, DeepVariant SNV/indel calls, Manta SV calls, and release-ready
metadata/manifests for downstream VIPER.

Annotation, prioritization, VEP, CADD, ClinVar, gnomAD, SpliceAI, IGV candidate
BED generation, reports, and cohort analysis are intentionally not part of this
pipeline.

## 1. Prepare Inputs

Create a tab-separated sample sheet. A minimal paired-end sample sheet needs:

```text
sample	lane	fastq_1	fastq_2
SAMPLE001	1	data/SAMPLE001_R1.fastq.gz	data/SAMPLE001_R2.fastq.gz
```

Optional columns such as `family_id`, `role`, and `sex` are copied into the
cohort-ready manifest when present. See `config/example_samples.tsv`.

Multiple rows with the same `sample` are treated as lanes of the same sample.

## 2. Configure

Start from the example config:

```bash
cp config/example_config.yaml config/my_run.yaml
```

Edit at least:

- `samplesheet`
- `outdir`
- `reference`
- `deepvariant.sif`
- `deepvariant.singularity_bind`

Useful optional settings:

- `keep_full_deepvariant_vcf: true` keeps the full DeepVariant VCF under `snv_calls/`.
- `keep_per_base_coverage: true` keeps the large mosdepth per-base BED.
- `coverage_regions_bed: path/to/regions.bed` adds region-level coverage output.

## 3. Run

Dry-run:

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/my_run.yaml \
          --use-conda \
          --cores 4 \
          --dry-run
```

Local run:

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/my_run.yaml \
          --use-conda \
          --cores 16
```

SLURM run with the bundled profile:

```bash
snakemake --snakefile workflow/Snakefile \
          --configfile config/my_run.yaml \
          --profile profiles/slurm
```

## 4. Main Outputs

Per sample, the main Phase I outputs are:

- `output/{sample}/alignment/{sample}.markdup.bam`
- `output/{sample}/alignment/{sample}.markdup.bam.bai`
- `output/{sample}/snv_calls/{sample}.pass.vcf.gz`
- `output/{sample}/snv_calls/{sample}.pass.vcf.gz.tbi`
- `output/{sample}/snv_calls/{sample}.g.vcf.gz`
- `output/{sample}/snv_calls/{sample}.g.vcf.gz.tbi`
- `output/{sample}/sv_calls/{sample}.manta.vcf.gz`
- `output/{sample}/sv_calls/{sample}.manta.vcf.gz.tbi`
- `output/{sample}/qc/coverage/{sample}.mosdepth.summary.txt`
- `output/{sample}/qc/{sample}_multiqc_report.html`
- `output/{sample}/ngsbits_samplegender/{sample}_ngsbits_sex.tsv`
- `output/{sample}/metadata/{sample}.variantpiper_phase1.yaml`
- `output/{sample}/metadata/{sample}.phase1_outputs.tsv`
- `output/{sample}/metadata/{sample}.cohort_inputs.tsv`
- `output/{sample}/metadata/{sample}.checksums.txt`

The PASS SNV/indel VCF and Manta VCF are the main VIPER handoff files. The
gVCF is always retained for future Phase II cohort SNV calling.
