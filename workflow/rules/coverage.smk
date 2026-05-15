# =============================================================================
# Step 2b — Coverage QC with mosdepth
# =============================================================================
# The mosdepth summary is a Phase I final deliverable and is required by
# downstream VIPER. Region-level coverage is generated when coverage_regions_bed
# is configured, which lets VIPER or later DSD workflows summarize clinically
# relevant gene/target coverage without rerunning alignment.
#
# Optional/debug output:
#   keep_per_base_coverage: true keeps {sample}.per-base.bed.gz.
#   When false, mosdepth runs with --no-per-base to avoid writing the large file.
# =============================================================================

_COVERAGE_REGIONS_BED = config.get("coverage_regions_bed")
_KEEP_PER_BASE_COVERAGE = config.get("keep_per_base_coverage", False)


rule mosdepth_coverage:
    """
    Generate whole-genome and optional region-level coverage metrics.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
        regions=(_COVERAGE_REGIONS_BED if _COVERAGE_REGIONS_BED else []),
    output:
        summary="{outdir}/{sample}/qc/coverage/{sample}.mosdepth.summary.txt",
        per_base=("{outdir}/{sample}/qc/coverage/{sample}.per-base.bed.gz"
                  if _KEEP_PER_BASE_COVERAGE else []),
        regions=("{outdir}/{sample}/qc/coverage/{sample}.regions.bed.gz"
                 if _COVERAGE_REGIONS_BED else []),
        regions_index=("{outdir}/{sample}/qc/coverage/{sample}.regions.bed.gz.csi"
                       if _COVERAGE_REGIONS_BED else []),
    log:
        "{outdir}/{sample}/logs/mosdepth.log",
    threads: 4
    resources:
        mem_mb=8000,
        runtime=120,
    conda:
        "../envs/mosdepth.yaml"
    params:
        prefix="{outdir}/{sample}/qc/coverage/{sample}",
        no_per_base=("" if _KEEP_PER_BASE_COVERAGE else "--no-per-base"),
        by=(f"--by {_COVERAGE_REGIONS_BED}" if _COVERAGE_REGIONS_BED else ""),
        extra=config.get("mosdepth", {}).get("extra", ""),
    shell:
        """
        mosdepth \
            --threads {threads} \
            {params.no_per_base} \
            {params.by} \
            {params.extra} \
            {params.prefix} \
            {input.bam} \
            > {log} 2>&1

        if [ -n "{params.by}" ] && [ ! -s "{params.prefix}.regions.bed.gz.csi" ]; then
            tabix -f -C -p bed "{params.prefix}.regions.bed.gz" 2>> {log}
        fi
        """
