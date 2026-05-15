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
# Phase I final outputs:
#   {sample}.pass.vcf.gz / .pass.vcf.gz.tbi — VIPER handoff SNV/indel calls
#   {sample}.g.vcf.gz / .g.vcf.gz.tbi       — kept for Phase II cohort calling
#
# Optional/debug output:
#   {sample}.vcf.gz / .vcf.gz.tbi — full DeepVariant VCF. Kept only when
#   keep_full_deepvariant_vcf: true; otherwise marked temp() because the main
#   Phase I deliverable is the PASS VCF and the gVCF is always retained.
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
        vcf=("{outdir}/{sample}/snv_calls/{sample}.vcf.gz"
             if KEEP_FULL_DEEPVARIANT_VCF else
             temp("{outdir}/{sample}/snv_calls/{sample}.vcf.gz")),
        vcf_tbi=("{outdir}/{sample}/snv_calls/{sample}.vcf.gz.tbi"
                 if KEEP_FULL_DEEPVARIANT_VCF else
                 temp("{outdir}/{sample}/snv_calls/{sample}.vcf.gz.tbi")),
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
        bind=config.get("singularity_bind", config["deepvariant"]["singularity_bind"]),
        extra=config["deepvariant"].get("extra", ""),
        # postprocess_variants spawns one Python worker per CPU; each worker
        # loads gVCF records into memory, so limiting this to 4 is enough to
        # prevent OOM on 30x WGS samples (~6M gVCF entries) without slowing
        # down the CPU-bound make_examples and call_variants stages.
        postprocess_cpus=config["deepvariant"].get("postprocess_cpus", 4),
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
                --postprocess_cpus={params.postprocess_cpus} \
                --intermediate_results_dir="$INTERMED" \
                {params.extra} \
                2> {log}
        """


rule filter_snv:
    """
    Filter DeepVariant VCF to PASS variants only.
    Produces the main Phase I SNV/indel deliverable for downstream VIPER.
    The gVCF is never filtered — it must retain all sites for cohort genotyping.
    """
    input:
        vcf="{outdir}/{sample}/snv_calls/{sample}.vcf.gz",
        tbi="{outdir}/{sample}/snv_calls/{sample}.vcf.gz.tbi",
    output:
        vcf="{outdir}/{sample}/snv_calls/{sample}.pass.vcf.gz",
        tbi="{outdir}/{sample}/snv_calls/{sample}.pass.vcf.gz.tbi",
    log:
        "{outdir}/{sample}/logs/filter_snv.log",
    resources:
        mem_mb=4000,
        runtime=30,
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        bcftools view -f PASS -O z -o {output.vcf} {input.vcf} 2> {log}
        bcftools index -t {output.vcf} 2>> {log}
        """
