# =============================================================================
# Step 4 — Structural Variant Calling
# =============================================================================
# Supports two SV callers, selected via config["sv_caller"]:
#   - manta  (default) — Illumina Manta v1.6.0
#   - delly            — EMBL-EBI Delly
#
# Caller-specific rules write to intermediate paths:
#   sv_calls/{sample}.manta.sv.vcf.gz
#   sv_calls/{sample}.delly.sv.vcf.gz
#
# The dispatcher rule (sv_collect) copies the active caller's output to the
# canonical path consumed by rule all and downstream steps:
#   sv_calls/{sample}.sv.vcf.gz  +  .tbi
#
# To switch callers, change sv_caller in your config file — no Snakefile
# edits needed.
# =============================================================================

SV_CALLER = config.get("sv_caller", "manta")


# -----------------------------------------------------------------------------
# Dispatcher — copies the active caller's VCF to the canonical output path
# -----------------------------------------------------------------------------

def _sv_vcf(wc):
    return f"{wc.outdir}/{wc.sample}/sv_calls/{wc.sample}.{SV_CALLER}.sv.vcf.gz"

def _sv_tbi(wc):
    return f"{wc.outdir}/{wc.sample}/sv_calls/{wc.sample}.{SV_CALLER}.sv.vcf.gz.tbi"


rule sv_collect:
    """
    Dispatcher: copies the active SV caller's output to the canonical path.
    Change sv_caller in config to switch between manta and delly.
    """
    input:
        vcf=_sv_vcf,
        tbi=_sv_tbi,
    output:
        vcf="{outdir}/{sample}/sv_calls/{sample}.sv.vcf.gz",
        tbi="{outdir}/{sample}/sv_calls/{sample}.sv.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/sv_collect.log",
    resources:
        mem_mb=1000,
        runtime=10,
    shell:
        """
        cp {input.vcf} {output.vcf} 2> {log}
        cp {input.tbi} {output.tbi} 2>> {log}
        """


# =============================================================================
# Manta rules
# =============================================================================


rule manta_call:
    """
    Call structural variants with Manta v1.6.0.

    Two internal steps:
      1. configManta.py  — initialises a run directory with workflow scripts
      2. runWorkflow.py  — SV discovery from the BAM

    For germline single-sample WGS, diploidSV.vcf.gz holds the final calls
    (DEL, INS, INV, DUP, BND). The Manta run directory is cleaned up after
    results are extracted to reclaim scratch space.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
        ref=config["reference"],
        fai=config["reference"] + ".fai",
    output:
        vcf="{outdir}/{sample}/sv_calls/{sample}.manta.sv.vcf.gz",
        tbi="{outdir}/{sample}/sv_calls/{sample}.manta.sv.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/manta.log",
    threads: 16
    resources:
        mem_mb=16000,
        runtime=480,
    conda:
        "../envs/manta.yaml"
    params:
        rundir=lambda wc: f"{wc.outdir}/{wc.sample}/sv_calls/manta_run",
        extra=config.get("manta", {}).get("extra", ""),
        filter="-f PASS" if config.get("filter_pass", True) else "",
    shell:
        """
        # Remove any previous failed run directory so configManta starts clean
        rm -rf {params.rundir}

        # Step 1: configure the Manta run
        configManta.py \
            --bam {input.bam} \
            --referenceFasta {input.ref} \
            {params.extra} \
            --runDir {params.rundir} \
            2> {log}

        # Step 2: run the Manta workflow (call with python explicitly to bypass shebang issues)
        python {params.rundir}/runWorkflow.py \
            -m local \
            -j {threads} \
            2>> {log}

        # Apply PASS filter if configured, then write the final VCF
        bcftools view \
            {params.filter} \
            -O z \
            -o {output.vcf} \
            {params.rundir}/results/variants/diploidSV.vcf.gz \
            2>> {log}

        bcftools index -t {output.vcf} 2>> {log}

        # Remove the Manta run directory (large intermediate graph files)
        rm -rf {params.rundir}
        """


# =============================================================================
# Delly rules
# =============================================================================


rule delly_call:
    """
    Discover structural variants from the duplicate-marked BAM.
    Produces a raw BCF with all SV types (DEL, INS, DUP, INV, BND).
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
        ref=config["reference"],
        fai=config["reference"] + ".fai",
    output:
        bcf=temp("{outdir}/{sample}/sv_calls/{sample}.sv.bcf"),
        csi=temp("{outdir}/{sample}/sv_calls/{sample}.sv.bcf.csi"),
    log:
        "{outdir}/{sample}/logs/delly_call.log",
    resources:
        mem_mb=16000,
        runtime=480,
    conda:
        "../envs/delly.yaml"
    params:
        extra=config.get("delly", {}).get("extra", ""),
    shell:
        """
        delly call \
            -g {input.ref} \
            {params.extra} \
            -o {output.bcf} \
            {input.bam} \
            2> {log}
        # delly >= 1.2 creates the .csi index automatically alongside the BCF
        """


rule delly_filter:
    """
    Export the raw Delly BCF as VCF.gz + TBI.

    Note: delly filter -f germline is designed for population cohorts (>=20 samples)
    and removes essentially all calls in single-sample analysis. We rely instead on
    Delly's built-in per-variant PASS/LowQual filter applied during delly call,
    and optionally subset to PASS here via bcftools.
    """
    input:
        bcf="{outdir}/{sample}/sv_calls/{sample}.sv.bcf",
        csi="{outdir}/{sample}/sv_calls/{sample}.sv.bcf.csi",
    output:
        vcf="{outdir}/{sample}/sv_calls/{sample}.delly.sv.vcf.gz",
        tbi="{outdir}/{sample}/sv_calls/{sample}.delly.sv.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/delly_filter.log",
    resources:
        mem_mb=8000,
        runtime=60,
    params:
        filter="-f PASS" if config.get("filter_pass", True) else "",
    conda:
        "../envs/delly.yaml"
    shell:
        """
        bcftools view \
            {params.filter} \
            -O z \
            -o {output.vcf} \
            {input.bcf} \
            2> {log}

        bcftools index -t {output.vcf} 2>> {log}
        """
