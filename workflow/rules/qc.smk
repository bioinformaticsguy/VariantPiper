# =============================================================================
# Step 1 — Quality Control with fastp
# =============================================================================
# Two rules:
#
#   merge_lanes  — concatenates multi-lane FASTQ files into one R1 and one R2
#                  per sample.  Uses zcat | gzip -1 (NOT plain cat) to produce
#                  a standard single-stream gzip file.  fastp uses ISA-L for
#                  gzip decompression; ISA-L does not handle multi-stream gzip
#                  (produced by plain cat of .gz files) and hangs indefinitely
#                  on the second sub-stream boundary.  Recompressing via
#                  zcat | gzip -1 avoids this entirely.  Outputs are temp()
#                  and deleted automatically once fastp completes.
#
#   fastp        — adapter trimming and QC on the merged (single-file) input.
#                  Receives a regular single-stream gzip file on disk.
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

    Uses zcat | gzip -1 (not plain cat) so the output is a single gzip stream.
    fastp uses ISA-L for gzip reading, which hangs indefinitely on multi-stream
    gzip files (produced by plain cat of .gz files).  Recompressing via
    zcat | gzip -1 produces a standard single-stream gzip that ISA-L reads
    correctly.  -1 keeps compression fast; the file is temp() and deleted
    after fastp completes.
    """
    input:
        r1=_r1,
        r2=_r2,
    output:
        r1=temp("{outdir}/{sample}/qc/{sample}_R1.merged.fastq.gz"),
        r2=temp("{outdir}/{sample}/qc/{sample}_R2.merged.fastq.gz"),
    resources:
        mem_mb=512,
        runtime=180,
    shell:
        """
        zcat {input.r1} | gzip -1 > {output.r1}
        zcat {input.r2} | gzip -1 > {output.r2}
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
        adapter_fasta=(
            "--adapter_fasta " + config["fastp"]["adapter_fasta"]
            if config["fastp"].get("adapter_fasta") else ""
        ),
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
            --detect_adapter_for_pe \
            --thread {threads} \
            {params.adapter_fasta} \
            {params.extra} \
            2> {log}
        """
