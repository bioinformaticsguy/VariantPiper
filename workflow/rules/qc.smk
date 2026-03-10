# =============================================================================
# Step 1 — Quality Control with fastp
# =============================================================================
# Trims adapters, filters low-quality bases/reads, and produces an HTML+JSON
# QC report per sample.  Trimmed reads are passed to Step 2 (alignment).
# =============================================================================


rule fastp:
    input:
        r1=lambda wc: config["samples"][wc.sample]["R1"],
        r2=lambda wc: config["samples"][wc.sample]["R2"],
    output:
        r1="{outdir}/{sample}/qc/{sample}_R1.trimmed.fastq.gz",
        r2="{outdir}/{sample}/qc/{sample}_R2.trimmed.fastq.gz",
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
