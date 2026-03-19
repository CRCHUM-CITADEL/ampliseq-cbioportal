# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Nextflow pipeline (`crchum-citadel/ampliseq-cbioportal`) that formats ampliseq genomic data into cBioPortal-compatible format. It is built from nf-core/tools template v3.5.1 but is currently in early development — the Nextflow workflow itself is a stub; the core logic lives in standalone scripts in `bin/`.

## Running the Pipeline

```bash
# Run with required parameters
nextflow run main.nf --input samplesheet.csv --outdir results/

# Run with a specific profile (e.g., docker, singularity, conda)
nextflow run main.nf --input samplesheet.csv --outdir results/ -profile docker

# Resume a previous run
nextflow run main.nf --input samplesheet.csv --outdir results/ -resume
```

Requires Nextflow >= 25.04.0.

## Running the Standalone Transformation Scripts

Until the Nextflow workflow is fully built out, data transformation is done via `bin/run_pipeline.sh`, which orchestrates the Python scripts:

```bash
# Run the full transformation pipeline
bash bin/run_pipeline.sh

# Individual Python scripts (all use pandas)
python bin/format_tsv.py          # Extract SVs from analysis TSV
python bin/format_cna.py          # Process copy number alterations
python bin/clinical_patients_format.py   # Format patient clinical data
python bin/clinical_sample_format.py     # Format sample clinical data
python bin/format_mutations.py    # Deanonymize mutation data
python bin/format_sv.py           # Deanonymize SV data
python bin/format_cna_deanon.py   # Deanonymize CNA data
```

## Input Format

The samplesheet (`--input`) must be a CSV with columns:
- `sample` (required): Sample name, no spaces
- `fastq_1` (required): Path to R1 FASTQ file (`.fastq.gz` or `.fq.gz`)
- `fastq_2` (optional): Path to R2 FASTQ for paired-end reads

See `assets/samplesheet.csv` for an example and `assets/schema_input.json` for the full schema.

## Architecture

```
main.nf                          # Entry point; reads --input, calls workflow
workflows/ampliseq-cbioportal.nf # Main workflow (currently a stub)
bin/                             # Standalone transformation scripts
  run_pipeline.sh                # Orchestrates full data transformation
  format_tsv.py                  # SV extraction (FUSION subtype rows)
  format_cna.py                  # CNA processing (copy number → cBioPortal values)
  format_mutations.py            # Mutation deanonymization
  format_sv.py                   # SV deanonymization
  format_cna_deanon.py           # CNA deanonymization
  clinical_patients_format.py    # Patient metadata formatting
  clinical_sample_format.py      # Sample metadata formatting
assets/
  schema_input.json              # JSON schema for samplesheet validation
  samplesheet.csv                # Example samplesheet
nextflow.config                  # Pipeline config; process defaults, profiles
nextflow_schema.json             # Parameter schema for --help and validation
```

## Data Flow

The transformation pipeline converts ampliseq data to cBioPortal format:

1. Input: Sample directories with TSV exports and VCF files
2. VCF → MAF conversion via `vcf2maf.pl` inside an Apptainer container (VEP v113, GRCh37/hg19)
3. TSV processing for SVs and CNAs
4. Deanonymization using a linking file (anonymized ID → real patient ID)
5. Output files in cBioPortal format:
   - `data_mutations.txt` — somatic mutations (MAF format)
   - `data_sv.txt` — structural variants
   - `data_cna.txt` — copy number alterations (values: -2, -1, 0, 1, 2)
   - `data_clinical_patient.txt` — patient metadata
   - `data_clinical_sample.txt` — sample metadata
   - `case_lists/` — cBioPortal case list definitions

## Key Configuration Details

- **Default process resources:** 1 CPU, 6 GB memory, 4-hour walltime
- **Retry logic:** Automatic retry on exit codes 130–145, 104, 175 (OOM/signal errors)
- **Container registries:** quay.io (Docker, Singularity, Apptainer, Podman, Charliecloud)
- **Profiles available:** `docker`, `singularity`, `apptainer`, `conda`, `mamba`, `podman`, `shifter`, `charliecloud`, `wave`, `arm`, `gpu`
- **Plugin:** `nf-schema@2.5.1` for parameter validation

## Development Status

The Nextflow workflow (`workflows/ampliseq-cbioportal.nf`) is currently empty — the pipeline DAG has not been built yet. The `bin/` scripts are production-ready and are designed to eventually become Nextflow processes. GitHub CI/CD, test configuration (nf-test), modules, MultiQC, and documentation were intentionally skipped in the nf-core template.
