# =============================================================================
# Step 1 — Quality Control with fastp and FastQC
# =============================================================================
# Three rules:
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
#   fastqc       — read-level QC on the merged (single-file) input.
#
#   fastp        — adapter trimming and QC on the merged (single-file) input.
#                  Receives a regular single-stream gzip file on disk.
#
# cleanup_trimmed: when true in config, fastp trimmed outputs are also marked
# temp() and deleted after alignment completes, saving ~30-50 GB per sample.
# =============================================================================

_CLEANUP_TRIMMED = config.get("cleanup_trimmed", False)
_SAMPLEGENDER = config.get("samplegender", {})


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
        r1=temp("{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged.fastq.gz"),
        r2=temp("{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged.fastq.gz"),
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
        r1="{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged.fastq.gz",
        r2="{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged.fastq.gz",
    output:
        r1=(temp("{outdir}/{sample}/qc/fast_qc/{sample}_R1.trimmed.fastq.gz")
            if _CLEANUP_TRIMMED else
            "{outdir}/{sample}/qc/fast_qc/{sample}_R1.trimmed.fastq.gz"),
        r2=(temp("{outdir}/{sample}/qc/fast_qc/{sample}_R2.trimmed.fastq.gz")
            if _CLEANUP_TRIMMED else
            "{outdir}/{sample}/qc/fast_qc/{sample}_R2.trimmed.fastq.gz"),
        html="{outdir}/{sample}/qc/fast_qc/{sample}_fastp.html",
        json="{outdir}/{sample}/qc/fast_qc/{sample}_fastp.json",
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


rule fastqc:
    """
    Run FastQC on the merged input FASTQs.
    """
    input:
        r1="{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged.fastq.gz",
        r2="{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged.fastq.gz",
    output:
        r1_html="{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged_fastqc.html",
        r1_zip="{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged_fastqc.zip",
        r2_html="{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged_fastqc.html",
        r2_zip="{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged_fastqc.zip",
    log:
        "{outdir}/{sample}/logs/fastqc.log",
    threads: 2
    resources:
        mem_mb=4000,
        runtime=60,
    conda:
        "../envs/fastqc.yaml"
    params:
        outdir="{outdir}/{sample}/qc/fast_qc",
    shell:
        """
        fastqc \
            --threads {threads} \
            --outdir {params.outdir} \
            {input.r1} {input.r2} \
            > {log} 2>&1
        """


rule ngsbits_samplegender:
    """
    Predict sample sex from the duplicate-marked BAM with ngs-bits SampleGender.

    The output filename matches MultiQC's ngs-bits SampleGender search pattern:
    *_ngsbits_sex.tsv.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
    output:
        tsv="{outdir}/{sample}/ngsbits_samplegender/{sample}_ngsbits_sex.tsv",
    log:
        "{outdir}/{sample}/logs/ngsbits_samplegender.log",
    resources:
        mem_mb=4000,
        runtime=60,
    conda:
        "../envs/ngs-bits.yaml"
    params:
        method=_SAMPLEGENDER.get("method", "xy"),
        extra=_SAMPLEGENDER.get("extra", ""),
    shell:
        """
        SampleGender \
            -in {input.bam} \
            -method {params.method} \
            -out {output.tsv} \
            {params.extra} \
            2> {log}
        """


rule multiqc:
    """
    Aggregate per-sample QC outputs with MultiQC.
    """
    input:
        fastp_html="{outdir}/{sample}/qc/fast_qc/{sample}_fastp.html",
        fastp_json="{outdir}/{sample}/qc/fast_qc/{sample}_fastp.json",
        fastqc_r1_zip="{outdir}/{sample}/qc/fast_qc/{sample}_R1.merged_fastqc.zip",
        fastqc_r2_zip="{outdir}/{sample}/qc/fast_qc/{sample}_R2.merged_fastqc.zip",
        samplegender="{outdir}/{sample}/ngsbits_samplegender/{sample}_ngsbits_sex.tsv",
    output:
        html="{outdir}/{sample}/qc/{sample}_multiqc_report.html",
        data_dir=directory("{outdir}/{sample}/qc/multiqc_data"),
    log:
        "{outdir}/{sample}/logs/multiqc.log",
    resources:
        mem_mb=4000,
        runtime=60,
    conda:
        "../envs/multiqc.yaml"
    params:
        qc_dir="{outdir}/{sample}/qc",
        samplegender_dir="{outdir}/{sample}/ngsbits_samplegender",
        report_name="{sample}_multiqc_report.html",
        data_dir_name="multiqc_data",
    shell:
        """
        multiqc {params.qc_dir} {params.samplegender_dir} \
            --outdir {params.qc_dir} \
            --filename {params.report_name} \
            --cl-config "data_dir_name: {params.data_dir_name}" \
            --force \
            2> {log}
        """
