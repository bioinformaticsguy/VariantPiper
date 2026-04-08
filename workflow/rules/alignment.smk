# =============================================================================
# Step 2 — Alignment with BWA-MEM2
# =============================================================================
# Three rules in order:
#   1. bwa_mem2_align         — align + coordinate sort → temp sorted BAM
#   2. picard_markduplicates  — mark PCR/optical duplicates
#   3. samtools_index         — index the final BAM for random access
#
# Picard MarkDuplicates is used instead of samtools markdup because it does
# not require a preceding samtools fixmate step, and is the standard tool
# used in clinical germline pipelines (GATK best practices, nf-core/raredisease).
#
# The sorted BAM from rule 1 is marked temp() and deleted automatically
# once markdup completes, saving disk space.
#
# Reference indexes (bwa_mem2_index, samtools_faidx) are defined in
# rules/reference.smk and triggered automatically as dependencies.
# =============================================================================


rule bwa_mem2_align:
    """
    Align trimmed paired-end reads to the reference and produce a
    coordinate-sorted BAM.

    -K 100000000 processes a fixed number of bases per batch, ensuring
    deterministic output regardless of the number of threads used.
    """
    input:
        r1="{outdir}/{sample}/qc/{sample}_R1.trimmed.fastq.gz",
        r2="{outdir}/{sample}/qc/{sample}_R2.trimmed.fastq.gz",
        ref=config["reference"],
        idx=multiext(
            config["reference"],
            ".0123", ".amb", ".ann", ".bwt.2bit.64", ".pac",
        ),
    output:
        bam=temp("{outdir}/{sample}/alignment/{sample}.sorted.bam"),
    log:
        "{outdir}/{sample}/logs/bwa_mem2_align.log",
    threads: 16
    resources:
        mem_mb=32000,
        runtime=240,
    conda:
        "../envs/bwa-mem2.yaml"
    params:
        rg=lambda wc: (
            f"@RG\\tID:{wc.sample}\\tSM:{wc.sample}"
            f"\\tPL:ILLUMINA\\tLB:{wc.sample}"
        ),
        extra=config["bwa_mem2"].get("extra", ""),
    shell:
        """
        bwa-mem2 mem \
            -t {threads} \
            -K 100000000 \
            -R '{params.rg}' \
            {params.extra} \
            {input.ref} \
            {input.r1} {input.r2} \
            2> {log} \
        | samtools sort \
            -@ {threads} \
            -o {output.bam} \
            -
        """


rule picard_markduplicates:
    """
    Mark PCR and optical duplicates with Picard MarkDuplicates.
    Picard works directly on a coordinate-sorted BAM and does not require
    a prior samtools fixmate step.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.sorted.bam",
    output:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        metrics="{outdir}/{sample}/alignment/{sample}.markdup_metrics.txt",
    log:
        "{outdir}/{sample}/logs/picard_markduplicates.log",
    resources:
        mem_mb=16000,
        runtime=240,
    conda:
        "../envs/picard.yaml"
    shell:
        """
        picard MarkDuplicates \
            --java-options "-Xmx14g" \
            -I {input.bam} \
            -O {output.bam} \
            -M {output.metrics} \
            --TMP_DIR . \
            2> {log}
        """


rule samtools_index:
    """Index the duplicate-marked BAM for random access."""
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
    output:
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
    log:
        "{outdir}/{sample}/logs/samtools_index.log",
    resources:
        mem_mb=4000,
        runtime=30,
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools index {input.bam} 2> {log}"
