#!/usr/bin/env python3
"""
Split the single-lane test FASTQs into 4 lane files to exercise the
merge_lanes rule.

Input:  test_data/test_R1.fastq.gz  (10 000 reads)
        test_data/test_R2.fastq.gz

Output: test_data/multilane/test_L00{1-4}_R1.fastq.gz  (2 500 reads each)
        test_data/multilane/test_L00{1-4}_R2.fastq.gz
        samplesheets/test_multilane.tsv

Usage:
    python scripts/generate_test_multilane.py
    # then run the pipeline with:
    snakemake --configfile config/config.yaml \
              --config samplesheet=samplesheets/test_multilane.tsv \
              --use-conda --cores 4
"""

import gzip
import itertools
import os

READS_PER_LANE = 2500
N_LANES = 4
OUTDIR = "test_data/multilane"
SAMPLESHEET = "samplesheets/test_multilane.tsv"
SAMPLE_ID = "test"

INPUTS = {
    "R1": "test_data/singlelane/test_R1.fastq.gz",
    "R2": "test_data/singlelane/test_R2.fastq.gz",
}


def read_fastq_records(path):
    """Yield one FASTQ record as a tuple of 4 byte strings."""
    with gzip.open(path, "rb") as fh:
        while True:
            lines = list(itertools.islice(fh, 4))
            if not lines:
                break
            if len(lines) != 4:
                raise ValueError(f"Truncated FASTQ record in {path}")
            yield tuple(lines)


def write_records(records, path):
    with gzip.open(path, "wb") as fh:
        for rec in records:
            fh.writelines(rec)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    os.makedirs(os.path.dirname(SAMPLESHEET), exist_ok=True)

    lane_paths = {end: [] for end in ("R1", "R2")}

    for end, src in INPUTS.items():
        print(f"Reading {src} …")
        all_records = list(read_fastq_records(src))
        n = len(all_records)
        print(f"  {n} reads total → {N_LANES} lanes × {READS_PER_LANE} reads")

        for lane_idx in range(N_LANES):
            start = lane_idx * READS_PER_LANE
            chunk = all_records[start : start + READS_PER_LANE]
            out = os.path.join(OUTDIR, f"{SAMPLE_ID}_L00{lane_idx + 1}_{end}.fastq.gz")
            write_records(chunk, out)
            print(f"  wrote {out} ({len(chunk)} reads)")
            lane_paths[end].append(out)

    header = ["sample", "lane", "fastq_1", "fastq_2",
              "sex", "phenotype", "paternal_id", "maternal_id", "case_id"]
    with open(SAMPLESHEET, "w") as fh:
        fh.write("\t".join(header) + "\n")
        for i in range(N_LANES):
            row = [SAMPLE_ID, str(i + 1), lane_paths["R1"][i], lane_paths["R2"][i],
                   "0", "0", "", "", ""]
            fh.write("\t".join(row) + "\n")

    print(f"\nSamplesheet: {SAMPLESHEET}")
    print("Run the pipeline with:")
    print(f"  snakemake --snakefile workflow/Snakefile \\")
    print(f"            --configfile config/config.yaml \\")
    print(f"            --config samplesheet={SAMPLESHEET} \\")
    print(f"            --use-conda --cores 4")


if __name__ == "__main__":
    main()
