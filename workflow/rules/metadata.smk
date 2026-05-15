# =============================================================================
# Step 5 — Phase I metadata, manifests, and checksums
# =============================================================================
# These files document the clean Phase I handoff. They deliberately stop at
# alignment/QC/SNV/SV outputs; annotation, prioritization, candidate BEDs, and
# clinical reports belong to downstream VIPER or future phases.
# =============================================================================

from datetime import datetime as _datetime


def _sample_value(sample, *keys):
    data = config["samples"].get(sample, {})
    for key in keys:
        value = data.get(key)
        if value not in (None, ""):
            return str(value)
    return "NA"


def _phase1_paths(wc):
    base = f"{wc.outdir}/{wc.sample}"
    paths = {
        "bam": f"{base}/alignment/{wc.sample}.markdup.bam",
        "bai": f"{base}/alignment/{wc.sample}.markdup.bam.bai",
        "markdup_metrics": f"{base}/alignment/{wc.sample}.markdup_metrics.txt",
        "gvcf": f"{base}/snv_calls/{wc.sample}.g.vcf.gz",
        "gvcf_index": f"{base}/snv_calls/{wc.sample}.g.vcf.gz.tbi",
        "snv_pass_vcf": f"{base}/snv_calls/{wc.sample}.pass.vcf.gz",
        "snv_pass_vcf_index": f"{base}/snv_calls/{wc.sample}.pass.vcf.gz.tbi",
        "sv_manta_vcf": f"{base}/sv_calls/{wc.sample}.manta.vcf.gz",
        "sv_manta_vcf_index": f"{base}/sv_calls/{wc.sample}.manta.vcf.gz.tbi",
        "mosdepth_summary": f"{base}/qc/coverage/{wc.sample}.mosdepth.summary.txt",
        "multiqc_report": f"{base}/qc/{wc.sample}_multiqc_report.html",
        "multiqc_general_stats": f"{base}/qc/multiqc_data/multiqc_general_stats.txt",
        "multiqc_software_versions": f"{base}/qc/multiqc_data/multiqc_software_versions.txt",
        "multiqc_data_json": f"{base}/qc/multiqc_data/multiqc_data.json",
        "samplegender_tsv": f"{base}/ngsbits_samplegender/{wc.sample}_ngsbits_sex.tsv",
    }
    if config.get("coverage_regions_bed"):
        paths["mosdepth_regions"] = f"{base}/qc/coverage/{wc.sample}.regions.bed.gz"
        paths["mosdepth_regions_index"] = f"{base}/qc/coverage/{wc.sample}.regions.bed.gz.csi"
    if config.get("keep_per_base_coverage", False):
        paths["mosdepth_per_base"] = f"{base}/qc/coverage/{wc.sample}.per-base.bed.gz"
    return paths


rule phase1_metadata_yaml:
    """
    Write per-sample VariantPiper Phase I run metadata.
    """
    input:
        unpack(_phase1_paths),
    output:
        yaml="{outdir}/{sample}/metadata/{sample}.variantpiper_phase1.yaml",
    log:
        "{outdir}/{sample}/logs/phase1_metadata_yaml.log",
    run:
        paths = _phase1_paths(wildcards)
        main_outputs = [
            paths["bam"],
            paths["bai"],
            paths["snv_pass_vcf"],
            paths["snv_pass_vcf_index"],
            paths["gvcf"],
            paths["gvcf_index"],
            paths["sv_manta_vcf"],
            paths["sv_manta_vcf_index"],
            paths["mosdepth_summary"],
            paths["multiqc_report"],
            paths["samplegender_tsv"],
        ]
        with open(output.yaml, "w") as out:
            out.write(f"sample_id: {wildcards.sample}\n")
            out.write("pipeline_name: VariantPiper\n")
            out.write("pipeline_phase: phase1_variant_calling\n")
            out.write(f"reference: {config['reference']}\n")
            out.write("aligner: bwa-mem2\n")
            out.write("snv_caller: DeepVariant\n")
            out.write("sv_caller: Manta\n")
            out.write(f"date_generated: {_datetime.now().isoformat(timespec='seconds')}\n")
            out.write(f"output_directory: {wildcards.outdir}/{wildcards.sample}\n")
            out.write("main_outputs:\n")
            for path in main_outputs:
                out.write(f"  - {path}\n")
            out.write('notes: "Annotation and prioritization are handled by downstream VIPER."\n')
        with open(log[0], "w") as lg:
            lg.write(f"Wrote {output.yaml}\n")


rule phase1_outputs_manifest:
    """
    Write the Phase I output manifest with VIPER and Phase II requirements.
    """
    input:
        unpack(_phase1_paths),
    output:
        tsv="{outdir}/{sample}/metadata/{sample}.phase1_outputs.tsv",
    log:
        "{outdir}/{sample}/logs/phase1_outputs_manifest.log",
    run:
        paths = _phase1_paths(wildcards)
        rows = [
            ("markdup_bam", paths["bam"], "yes", "yes", "Duplicate-marked alignment BAM"),
            ("markdup_bai", paths["bai"], "yes", "yes", "BAM index"),
            ("markdup_metrics", paths["markdup_metrics"], "no", "no", "Picard duplicate marking metrics"),
            ("snv_pass_vcf", paths["snv_pass_vcf"], "yes", "no", "DeepVariant PASS SNV/indel VCF for VIPER"),
            ("snv_pass_vcf_index", paths["snv_pass_vcf_index"], "yes", "no", "Index for PASS SNV/indel VCF"),
            ("snv_gvcf", paths["gvcf"], "no", "yes", "DeepVariant gVCF for future cohort calling"),
            ("snv_gvcf_index", paths["gvcf_index"], "no", "yes", "Index for DeepVariant gVCF"),
            ("sv_manta_vcf", paths["sv_manta_vcf"], "yes", "no", "Manta structural variant VCF"),
            ("sv_manta_vcf_index", paths["sv_manta_vcf_index"], "yes", "no", "Index for Manta structural variant VCF"),
            ("mosdepth_summary", paths["mosdepth_summary"], "yes", "no", "mosdepth coverage summary"),
            ("multiqc_report", paths["multiqc_report"], "yes", "no", "MultiQC HTML report"),
            ("multiqc_general_stats", paths["multiqc_general_stats"], "yes", "no", "MultiQC general statistics table"),
            ("multiqc_software_versions", paths["multiqc_software_versions"], "yes", "no", "MultiQC software versions table"),
            ("multiqc_data_json", paths["multiqc_data_json"], "yes", "no", "MultiQC structured data JSON"),
            ("samplegender_tsv", paths["samplegender_tsv"], "yes", "no", "ngs-bits SampleGender sex inference TSV"),
        ]
        if "mosdepth_regions" in paths:
            rows.extend([
                ("mosdepth_regions", paths["mosdepth_regions"], "yes", "no", "mosdepth region-level coverage BED"),
                ("mosdepth_regions_index", paths["mosdepth_regions_index"], "yes", "no", "Index for mosdepth region-level coverage BED"),
            ])
        if "mosdepth_per_base" in paths:
            rows.append(("mosdepth_per_base", paths["mosdepth_per_base"], "no", "no", "Optional per-base mosdepth coverage BED"))
        with open(output.tsv, "w") as out:
            out.write("sample_id\toutput_type\tpath\trequired_for_viper\trequired_for_future_phase2\tdescription\n")
            for row in rows:
                out.write("\t".join([wildcards.sample, *row]) + "\n")
        with open(log[0], "w") as lg:
            lg.write(f"Wrote {output.tsv}\n")


rule cohort_inputs_manifest:
    """
    Write one-sample manifest rows that can be collected for future Phase II.
    """
    input:
        unpack(_phase1_paths),
    output:
        tsv="{outdir}/{sample}/metadata/{sample}.cohort_inputs.tsv",
    log:
        "{outdir}/{sample}/logs/cohort_inputs_manifest.log",
    run:
        paths = _phase1_paths(wildcards)
        row = {
            "sample_id": wildcards.sample,
            "family_id": _sample_value(wildcards.sample, "family_id", "case_id"),
            "role": _sample_value(wildcards.sample, "role", "phenotype"),
            "sex": _sample_value(wildcards.sample, "sex"),
            "bam": paths["bam"],
            "bai": paths["bai"],
            "gvcf": paths["gvcf"],
            "gvcf_index": paths["gvcf_index"],
            "snv_pass_vcf": paths["snv_pass_vcf"],
            "snv_pass_vcf_index": paths["snv_pass_vcf_index"],
            "sv_manta_vcf": paths["sv_manta_vcf"],
            "sv_manta_vcf_index": paths["sv_manta_vcf_index"],
            "mosdepth_summary": paths["mosdepth_summary"],
            "samplegender_tsv": paths["samplegender_tsv"],
        }
        columns = [
            "sample_id", "family_id", "role", "sex", "bam", "bai", "gvcf",
            "gvcf_index", "snv_pass_vcf", "snv_pass_vcf_index",
            "sv_manta_vcf", "sv_manta_vcf_index", "mosdepth_summary",
            "samplegender_tsv",
        ]
        with open(output.tsv, "w") as out:
            out.write("\t".join(columns) + "\n")
            out.write("\t".join(row[col] for col in columns) + "\n")
        with open(log[0], "w") as lg:
            lg.write(f"Wrote {output.tsv}\n")


rule phase1_checksums:
    """
    Generate sha256 checksums for important Phase I final files.
    """
    input:
        bam="{outdir}/{sample}/alignment/{sample}.markdup.bam",
        bai="{outdir}/{sample}/alignment/{sample}.markdup.bam.bai",
        snv_pass_vcf="{outdir}/{sample}/snv_calls/{sample}.pass.vcf.gz",
        snv_pass_vcf_index="{outdir}/{sample}/snv_calls/{sample}.pass.vcf.gz.tbi",
        gvcf="{outdir}/{sample}/snv_calls/{sample}.g.vcf.gz",
        gvcf_index="{outdir}/{sample}/snv_calls/{sample}.g.vcf.gz.tbi",
        sv_manta_vcf="{outdir}/{sample}/sv_calls/{sample}.manta.vcf.gz",
        sv_manta_vcf_index="{outdir}/{sample}/sv_calls/{sample}.manta.vcf.gz.tbi",
        multiqc_report="{outdir}/{sample}/qc/{sample}_multiqc_report.html",
        mosdepth_summary="{outdir}/{sample}/qc/coverage/{sample}.mosdepth.summary.txt",
        samplegender_tsv="{outdir}/{sample}/ngsbits_samplegender/{sample}_ngsbits_sex.tsv",
    output:
        txt="{outdir}/{sample}/metadata/{sample}.checksums.txt",
    log:
        "{outdir}/{sample}/logs/phase1_checksums.log",
    resources:
        mem_mb=1000,
        runtime=30,
    shell:
        """
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum {input} > {output.txt} 2> {log}
        else
            shasum -a 256 {input} > {output.txt} 2> {log}
        fi
        """
