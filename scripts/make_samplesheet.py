#!/usr/bin/env python3
"""
Generate a VariantPiper TSV samplesheet for a batch of samples.

Scans the raw FASTQ directory, discovers all R1/R2 files for each sample
(across all lanes), and writes one row per lane.  Multi-lane samples appear
as multiple rows with the same sample ID — the pipeline groups them
automatically.

Usage:
    # Explicit sample list:
    python scripts/make_samplesheet.py \\
        --raw-dir /data/humangen_sfb1665_seqdata/short_read/raw \\
        --samples A4842_DNA_25 A4842_DNA_28 A5020_DNA_51_D22-619 \\
        --output samplesheets/run_batch1.tsv

    # Auto-discover all samples under --raw-dir:
    python scripts/make_samplesheet.py \\
        --raw-dir /data/humangen_sfb1665_seqdata/short_read/raw \\
        --auto-discover \\
        --output samplesheets/run_all.tsv

Directory layout assumed:
    <raw-dir>/<family>/<sample_id>/<sample_id>_*_R{1,2}_*.fastq.gz

where <family> is the first '_'-delimited token of the sample ID
(e.g. A4842 for A4842_DNA_25, A5020 for A5020_DNA_51_D22-619).

Columns written:
    sample  lane  fastq_1  fastq_2  sex  phenotype  paternal_id  maternal_id  case_id

sex:        1=male  2=female  0=unknown
phenotype:  1=unaffected  2=affected  0=unknown
"""

import argparse
import glob
import os
import sys

HEADER = ["sample", "lane", "fastq_1", "fastq_2", "sex", "phenotype",
          "paternal_id", "maternal_id", "case_id"]


def find_sample_dir(raw_dir, sample_id):
    family = sample_id.split("_")[0]
    candidate = os.path.join(raw_dir, family, sample_id)
    if os.path.isdir(candidate):
        return candidate
    for entry in os.scandir(raw_dir):
        if entry.is_dir():
            sub = os.path.join(entry.path, sample_id)
            if os.path.isdir(sub):
                return sub
    raise FileNotFoundError(
        f"No directory found for '{sample_id}' under {raw_dir}"
    )


def find_fastq_pairs(sample_dir):
    """Return sorted list of (r1_path, r2_path) tuples for all lanes."""
    r1_files = sorted(
        f for f in glob.glob(os.path.join(sample_dir, "*.fastq.gz"))
        if "_R1_" in os.path.basename(f) or "_R1." in os.path.basename(f)
    )
    r2_files = sorted(
        f for f in glob.glob(os.path.join(sample_dir, "*.fastq.gz"))
        if "_R2_" in os.path.basename(f) or "_R2." in os.path.basename(f)
    )
    if not r1_files:
        raise FileNotFoundError(f"No R1 FASTQ files in {sample_dir}")
    if len(r1_files) != len(r2_files):
        raise ValueError(
            f"R1/R2 count mismatch in {sample_dir}: "
            f"{len(r1_files)} R1 vs {len(r2_files)} R2"
        )
    return list(zip(r1_files, r2_files))


def discover_samples(raw_dir):
    samples = []
    for family_entry in sorted(os.scandir(raw_dir), key=lambda e: e.name):
        if not family_entry.is_dir() or family_entry.name.startswith("_"):
            continue
        for sample_entry in sorted(os.scandir(family_entry.path), key=lambda e: e.name):
            if sample_entry.is_dir():
                samples.append(sample_entry.name)
    return samples


def main():
    parser = argparse.ArgumentParser(
        description="Generate a VariantPiper TSV samplesheet."
    )
    parser.add_argument(
        "--raw-dir",
        default="/data/humangen_sfb1665_seqdata/short_read/raw",
        help="Root directory containing raw FASTQ files (default: %(default)s)",
    )
    parser.add_argument(
        "--samples",
        nargs="+",
        metavar="SAMPLE_ID",
        help="Sample IDs to include (mutually exclusive with --auto-discover)",
    )
    parser.add_argument(
        "--auto-discover",
        action="store_true",
        help="Include all samples found under --raw-dir",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path for the output TSV samplesheet",
    )
    args = parser.parse_args()

    if args.auto_discover and args.samples:
        parser.error("--samples and --auto-discover are mutually exclusive")
    if not args.auto_discover and not args.samples:
        parser.error("Provide --samples <IDs> or --auto-discover")

    sample_ids = args.samples if args.samples else discover_samples(args.raw_dir)

    rows = []
    errors = []
    for sid in sample_ids:
        try:
            sample_dir = find_sample_dir(args.raw_dir, sid)
            pairs = find_fastq_pairs(sample_dir)
            for lane_num, (r1, r2) in enumerate(pairs, start=1):
                rows.append({
                    "sample": sid,
                    "lane": lane_num,
                    "fastq_1": r1,
                    "fastq_2": r2,
                    "sex": 0,
                    "phenotype": 0,
                    "paternal_id": "",
                    "maternal_id": "",
                    "case_id": "",
                })
            print(f"  {sid}: {len(pairs)} lane(s)")
        except (FileNotFoundError, ValueError) as exc:
            print(f"  ERROR {sid}: {exc}", file=sys.stderr)
            errors.append(sid)

    if errors:
        print(f"\n{len(errors)} sample(s) failed — fix errors before running.",
              file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as fh:
        fh.write("\t".join(HEADER) + "\n")
        for row in rows:
            fh.write("\t".join(str(row[col]) for col in HEADER) + "\n")

    print(f"\nSamplesheet written to {args.output} ({len(rows)} rows, {len(sample_ids)} samples)")


if __name__ == "__main__":
    main()
