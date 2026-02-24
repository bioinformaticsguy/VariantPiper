#!/usr/bin/env bash


fastp -i /data/humangen_kircherlab/Users/hassan/repos/VariantPiper/input/GS487/GS487_MKDL250006671-1A_22VTKMLT4_L5_1.fq.gz \
     -I /data/humangen_kircherlab/Users/hassan/repos/VariantPiper/input/GS487/GS487_MKDL250006671-1A_22VTKMLT4_L5_2.fq.gz  \
     -h /data/humangen_kircherlab/Users/hassan/repos/VariantPiper/output/fastp/fastp_report.html \
     -j /data/humangen_kircherlab/Users/hassan/repos/VariantPiper/output/fastp/fastp_report.json 
