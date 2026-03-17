# =============================================================================
# Step 4 — Structural Variant Calling with Delly
# =============================================================================
# Calls deletions, inversions, duplications, insertions and translocations
# using Delly.
#
# Two rules in order:
#   1. delly_call   — discover SVs from the BAM → raw BCF (temp)
#   2. delly_filter — apply germline filter → final VCF.gz + TBI
#
# The raw BCF from rule 1 is marked temp() and deleted automatically once
# filtering completes.
#
# Tip: Delly provides an exclusion list for hg38 that masks problematic
# regions (centromeres, telomeres). Download it from:
#   https://github.com/dellytools/delly/blob/main/excludeTemplates/human.hg38.excl.tsv
# Then pass it via config: delly.extra: "-x resources/human.hg38.excl.tsv"
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
        extra=config["delly"].get("extra", ""),
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
    Export the raw Delly BCF as VCF.gz + TBI, keeping only PASS variants.

    Note: delly filter -f germline is designed for population cohorts (>=20 samples)
    and removes essentially all calls in single-sample analysis. For single-sample
    germline SV discovery, we rely on Delly's built-in per-variant quality filter
    (PASS vs LowQual) applied during delly call.
    """
    input:
        bcf="{outdir}/{sample}/sv_calls/{sample}.sv.bcf",
        csi="{outdir}/{sample}/sv_calls/{sample}.sv.bcf.csi",
    output:
        vcf="{outdir}/{sample}/sv_calls/{sample}.sv.vcf.gz",
        tbi="{outdir}/{sample}/sv_calls/{sample}.sv.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/delly_filter.log",
    resources:
        mem_mb=8000,
        runtime=60,
    params:
        filter="-f PASS" if config.get("filter_pass", True) else "-f 'PASS,.'",
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
