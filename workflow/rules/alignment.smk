# =============================================================================
# Step 2 — Alignment with BWA-MEM2
# =============================================================================
# Three rules in order:
#   1. bwa_mem2_align   — align trimmed reads, pipe into samtools sort
#                         produces a temporary sorted BAM
#   2. samtools_markdup — mark PCR/optical duplicates
#   3. samtools_index   — index the final BAM for random access
#
# The sorted BAM from rule 1 is marked temp() and deleted automatically
# once markdup completes, saving disk space.
#
# Reference indexes (bwa_mem2_index, samtools_faidx) are defined in
# rules/reference.smk and triggered automatically as dependencies.
# =============================================================================


rule bwa_mem2_align:
    """Align trimmed paired-end reads to the reference and produce a sorted BAM."""
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


rule samtools_markdup:
    """Mark PCR and optical duplicates in the sorted BAM."""
    input:
        bam="{outdir}/{sample}/alignment/{sample}.sorted.bam",
    output:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        metrics="{outdir}/{sample}/alignment/{sample}.markdup_metrics.txt",
    log:
        "{outdir}/{sample}/logs/samtools_markdup.log",
    threads: 4
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        samtools markdup \
            -@ {threads} \
            -f {output.metrics} \
            {input.bam} \
            {output.bam} \
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
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools index {input.bam} 2> {log}"
