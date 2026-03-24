# crchum-citadel/ampliseq-cbioportal

## Introduction

**crchum-citadel/ampliseq-cbioportal** formats ampliseq genomic data (VCFs + structural variant TSVs) into cBioPortal-compatible files: mutations (MAF), copy number alterations, structural variants, and clinical data.

Requires Nextflow >= 25.04.0.

## Usage

### 1. Prepare input files

**Samplesheet** (`samplesheet.csv`):
```csv
group,subject_id,sample_id,folder_location
cohort_A,PATIENT_001,SAMPLE_001,path/to/samples/SAMPLE_001
```

You can generate a samplesheet using a Python script (tested with version 3.12):
```bash
python3.12 bin/generate_samplesheet.py /data/folder/ --output samplesheet.csv
```

Each sample folder must contain, at minimum:
- `analysis_*_export.tsv` — structural variant / CNA export
- `*-basespace-pisces.final.vcf.gz` — compressed VCF

**Linking file** (`linking_file.txt`, tab-separated) — maps anonymized → real IDs:
```
sample_id	deanon_sample_id
SAMPLE_001	PATIENT_001
```

**Patient file** (tab-separated): `patient_id`, `age`, `sex`, `os_status`, `os_months`, `smoking_history`

**Sample file** (tab-separated): `sample_id`, `patient_id`, `cancer_type`, `cancer_type_detailed`, `sample_type`, `tumor_site`, `tumor_purity`

### 2 (option a): Run the pipeline

```bash
nextflow run main.nf \
  -profile apptainer \
  --input samplesheet.csv \
  --outdir results/ \
  --patient_file patient_file.txt \
  --sample_file sample_file.txt \
  --linking_file linking_file.txt \
  --vcf2maf_container community.wave.seqera.io/library/vcf2maf_ensembl-vep:... \
  --vep_data /path/to/vep_data/ \
  --study_id my_study
```

Skip VCF → MAF conversion if MAFs already exist:
```bash
nextflow run main.nf ... --skip_vcf2maf true
```

Pass all mutations through without TSV-coordinate filtering:
```bash
nextflow run main.nf ... --filter_tsv_variants false
```

### 2 (option b). Change nextflow.config and change the pipeline
nextflow run main.nf -profile apptainer

Resume a previous run:
```bash
nextflow run main.nf ... -resume
```
