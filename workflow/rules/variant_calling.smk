# =============================================================================
# Step 3 — Variant Calling with DeepVariant
# =============================================================================
# Calls SNVs and indels using the DeepVariant Singularity container.
#
# run_deepvariant runs three stages internally:
#   1. make_examples      — pileup images from BAM + reference (parallelised
#                           across --num_shards = threads)
#   2. call_snv_calls      — neural network inference
#   3. postprocess_snv_calls — converts output to VCF + gVCF
#
# Outputs (all produced and indexed by DeepVariant itself):
#   {sample}.vcf.gz / .vcf.gz.tbi   — SNV + indel calls
#   {sample}.g.vcf.gz / .g.vcf.gz.tbi — gVCF for future cohort genotyping
#
# Prerequisites:
#   - Singularity must be in PATH (load before submitting via the submit script)
#   - DeepVariant SIF downloaded by install.sh (see config: deepvariant.sif)
# =============================================================================


rule deepvariant:
    """
    Call SNVs and indels with DeepVariant (WGS model).
    Runs entirely inside the DeepVariant Singularity container.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
        ref=config["reference"],
        fai=config["reference"] + ".fai",
    output:
        vcf="{outdir}/{sample}/snv_calls/{sample}.vcf.gz",
        vcf_tbi="{outdir}/{sample}/snv_calls/{sample}.vcf.gz.tbi",
        gvcf="{outdir}/{sample}/snv_calls/{sample}.g.vcf.gz",
        gvcf_tbi="{outdir}/{sample}/snv_calls/{sample}.g.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/deepvariant.log",
    threads: 16
    resources:
        mem_mb=32000,
        runtime=480,
    params:
        sif=config["deepvariant"]["sif"],
        model_type=config["deepvariant"]["model_type"],
        bind=config["deepvariant"]["singularity_bind"],
        extra=config["deepvariant"].get("extra", ""),
    shell:
        """
        # Temporary directory for make_examples intermediate files (~10-30 GB).
        # Cleaned up automatically when the rule exits (success or failure).
        INTERMED=$(mktemp -d)
        trap "rm -rf '$INTERMED'" EXIT

        singularity exec \
            --bind {params.bind} \
            --bind "$INTERMED" \
            {params.sif} \
            /opt/deepvariant/bin/run_deepvariant \
                --model_type={params.model_type} \
                --ref={input.ref} \
                --reads={input.bam} \
                --output_vcf={output.vcf} \
                --output_gvcf={output.gvcf} \
                --num_shards={threads} \
                --intermediate_results_dir="$INTERMED" \
                {params.extra} \
                2> {log}
        """
