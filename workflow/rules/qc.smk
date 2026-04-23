# =============================================================================
# Step 1 — Quality Control with fastp
# =============================================================================
# Trims adapters, filters low-quality bases/reads, and produces an HTML+JSON
# QC report per sample.  Trimmed reads are passed to Step 2 (alignment).
#
# Multi-lane samples: R1/R2 in the config may be a string (single file) or a
# list (multiple lanes/files). When a list is given, fastp reads all files
# via process substitution (zcat concatenates them on the fly) — no temporary
# concatenated file is written to disk.
#
# cleanup_trimmed: when true in config, trimmed FASTQs are marked temp() and
# deleted automatically by Snakemake as soon as alignment finishes.
# =============================================================================

_CLEANUP_TRIMMED = config.get("cleanup_trimmed", False)


def _r1(wc):
    v = config["samples"][wc.sample]["R1"]
    return v if isinstance(v, list) else [v]


def _r2(wc):
    v = config["samples"][wc.sample]["R2"]
    return v if isinstance(v, list) else [v]


rule fastp:
    input:
        r1=_r1,
        r2=_r2,
    output:
        r1=(temp("{outdir}/{sample}/qc/{sample}_R1.trimmed.fastq.gz")
            if _CLEANUP_TRIMMED else
            "{outdir}/{sample}/qc/{sample}_R1.trimmed.fastq.gz"),
        r2=(temp("{outdir}/{sample}/qc/{sample}_R2.trimmed.fastq.gz")
            if _CLEANUP_TRIMMED else
            "{outdir}/{sample}/qc/{sample}_R2.trimmed.fastq.gz"),
        html="{outdir}/{sample}/qc/{sample}_fastp.html",
        json="{outdir}/{sample}/qc/{sample}_fastp.json",
    log:
        "{outdir}/{sample}/logs/fastp.log",
    threads: 4
    resources:
        mem_mb=8000,
        runtime=120,
    conda:
        "../envs/fastp.yaml"
    params:
        min_length=config["fastp"]["min_read_length"],
        quality=config["fastp"]["qualified_quality_phred"],
        extra=config["fastp"].get("extra", ""),
    shell:
        """
        fastp \
            --in1 <(zcat {input.r1}) \
            --in2 <(zcat {input.r2}) \
            --out1 {output.r1} \
            --out2 {output.r2} \
            --html {output.html} \
            --json {output.json} \
            --length_required {params.min_length} \
            --qualified_quality_phred {params.quality} \
            --thread {threads} \
            {params.extra} \
            2> {log}
        """
