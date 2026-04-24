# =============================================================================
# Step 1 — Quality Control with fastp
# =============================================================================
# Two rules:
#
#   merge_lanes  — concatenates multi-lane FASTQ files into one R1 and one R2
#                  per sample.  Uses cat, which simply concatenates gzip blocks;
#                  the result is a valid multi-stream gzip file that any
#                  gzip-aware reader handles correctly.  For single-lane samples
#                  this is a byte-identical passthrough.  Outputs are marked
#                  temp() and deleted automatically once fastp completes.
#
#   fastp        — adapter trimming and QC on the merged (single-file) input.
#                  Receives a regular gzip file on disk — no process
#                  substitution or pipe tricks, which caused fastp's gzip
#                  reader to stop at the first stream boundary.
#
# cleanup_trimmed: when true in config, fastp trimmed outputs are also marked
# temp() and deleted after alignment completes, saving ~30-50 GB per sample.
# =============================================================================

_CLEANUP_TRIMMED = config.get("cleanup_trimmed", False)


def _r1(wc):
    v = config["samples"][wc.sample]["R1"]
    return v if isinstance(v, list) else [v]


def _r2(wc):
    v = config["samples"][wc.sample]["R2"]
    return v if isinstance(v, list) else [v]


rule merge_lanes:
    """
    Concatenate all R1 (and R2) lane files into one gzip file per read end.
    cat on gzip files produces a valid concatenated gzip stream; fastp and
    zlib read it correctly as a regular file on disk.
    """
    input:
        r1=_r1,
        r2=_r2,
    output:
        r1=temp("{outdir}/{sample}/qc/{sample}_R1.merged.fastq.gz"),
        r2=temp("{outdir}/{sample}/qc/{sample}_R2.merged.fastq.gz"),
    resources:
        mem_mb=512,
        runtime=120,
    shell:
        """
        cat {input.r1} > {output.r1}
        cat {input.r2} > {output.r2}
        """


rule fastp:
    """
    Trim adapters and low-quality bases with fastp.
    Takes the merged single-file R1/R2 from merge_lanes as regular gzip files.
    """
    input:
        r1="{outdir}/{sample}/qc/{sample}_R1.merged.fastq.gz",
        r2="{outdir}/{sample}/qc/{sample}_R2.merged.fastq.gz",
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
            --in1 {input.r1} \
            --in2 {input.r2} \
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
