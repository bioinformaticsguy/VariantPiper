# =============================================================================
# Reference genome indexing rules
# =============================================================================
# These rules run automatically the first time the pipeline needs the indexes.
# They do NOT need to be listed in rule all — Snakemake resolves them as
# dependencies of the alignment rules.
#
# Indexes are written alongside the reference FASTA in resources/reference/.
# =============================================================================


rule samtools_faidx:
    """Create samtools FASTA index (.fai) for the reference genome."""
    input:
        config["reference"],
    output:
        config["reference"] + ".fai",
    log:
        "logs/reference/samtools_faidx.log",
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools faidx {input} 2> {log}"


rule bwa_mem2_index:
    """
    Create BWA-MEM2 index for the reference genome.
    Requires ~60 GB RAM — ensure sufficient memory is allocated on the cluster.
    """
    input:
        config["reference"],
    output:
        multiext(config["reference"], ".0123", ".amb", ".ann", ".bwt.2bit.64", ".pac"),
    log:
        "logs/reference/bwa_mem2_index.log",
    resources:
        mem_mb=65000,
    conda:
        "../envs/bwa-mem2.yaml"
    shell:
        "bwa-mem2 index {input} 2> {log}"
