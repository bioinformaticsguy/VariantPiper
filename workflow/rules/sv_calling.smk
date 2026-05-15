# =============================================================================
# Step 4 — Structural Variant Calling with Manta
# =============================================================================
# VariantPiper Phase I currently exposes Manta as the SV caller.
#
# Final Phase I SV deliverable for downstream VIPER:
#   sv_calls/{sample}.manta.vcf.gz
#   sv_calls/{sample}.manta.vcf.gz.tbi
#
# No generic {sample}.sv.vcf.gz is created in Phase I because there is not yet
# a true merged/standardized SV file from multiple SV callers.
# =============================================================================


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
        vcf="{outdir}/{sample}/sv_calls/{sample}.manta.vcf.gz",
        tbi="{outdir}/{sample}/sv_calls/{sample}.manta.vcf.gz.tbi",
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
