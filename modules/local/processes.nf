/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    LOCAL PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// ---------------------------------------------------------------------------
// Per-sample: extract SV/FUSION rows from analysis TSV → {sample_id}_sv.txt
// ---------------------------------------------------------------------------
process FORMAT_SV {
    tag "${meta.sample_id}"
    label 'python'

    input:
    tuple val(meta), path(tsv)

    output:
    path("${meta.sample_id}_sv.txt")

    script:
    """
    format_tsv.py "${tsv}" "${meta.sample_id}"
    mv data_sv.txt "${meta.sample_id}_sv.txt"
    """
}

// ---------------------------------------------------------------------------
// Per-sample: extract DUPLICATION/DELETION rows → {sample_id}_cna.txt
// ---------------------------------------------------------------------------
process FORMAT_CNA {
    tag "${meta.sample_id}"
    label 'python'

    input:
    tuple val(meta), path(tsv)

    output:
    path("${meta.sample_id}_cna.txt")

    script:
    """
    format_cna.py "${tsv}" "${meta.sample_id}"
    mv data_cna.txt "${meta.sample_id}_cna.txt"
    """
}

// ---------------------------------------------------------------------------
// Per-sample: stub MAF (no vcf2maf) — writes header-only MAF for testing
// ---------------------------------------------------------------------------
process STUB_MAF {
    tag "${meta.sample_id}"
    
    input:
    tuple val(meta), path(sample_folder)

    output:
    tuple val(meta), path("${meta.sample_id}.maf")

    script:
    """
    printf '#version 2.4\\n' > "${meta.sample_id}.maf"
    printf 'Hugo_Symbol\\tEntrez_Gene_Id\\tCenter\\tNCBI_Build\\tChromosome\\tStart_Position\\tEnd_Position\\tStrand\\tVariant_Classification\\tVariant_Type\\tReference_Allele\\tTumor_Seq_Allele1\\tTumor_Seq_Allele2\\tdbSNP_RS\\tdbSNP_Val_Status\\tTumor_Sample_Barcode\\n' >> "${meta.sample_id}.maf"
    """
}

// ---------------------------------------------------------------------------
// Per-sample: decompress VCF and run vcf2maf via Apptainer
// ---------------------------------------------------------------------------
process VCF_TO_MAF {
    tag "${meta.sample_id}"
    label "vcf2maf"

    input:
    tuple val(meta), path(sample_folder)
    path(vep_data)
    path(ref_fasta)

    output:
    tuple val(meta), path("${meta.sample_id}.maf")

    script:
    """
    VCF_GZ=\$(find -L "${sample_folder}" -maxdepth 1 -name '*-basespace-pisces.final.vcf.gz' | head -1)
    [ -n "\$VCF_GZ" ] || { echo "ERROR: No VCF found in ${sample_folder}" >&2; exit 1; }

    gzip -dc "\$VCF_GZ" > "${meta.sample_id}.final.vcf"

    MAF_OUT="${meta.sample_id}-basespace-pisces.final.maf"

    vcf2maf.pl \\
        --tumor-id "${meta.sample_id}" --cache-version 113 \\
        --ncbi-build GRCh37 --vep-path /opt/conda/bin \\
        --vep-data ${vep_data} --ref-fasta ${ref_fasta} \\
        --input-vcf "${meta.sample_id}.final.vcf" \\
        --output-maf "\$MAF_OUT"

    # Strip vcf2maf version comment (first line); keep column header as line 1
    sed '1d' "\$MAF_OUT" > "${meta.sample_id}.maf"
    """
}

// ---------------------------------------------------------------------------
// Per-sample: filter MAF rows to regions present in TSV → {sample_id}_mutations.txt
// ---------------------------------------------------------------------------
process FILTER_MUTATIONS {
    tag "${meta.sample_id}"

    input:
    tuple val(meta), path(maf), path(tsv)

    output:
    path("${meta.sample_id}_mutations.txt")

    script:
    """
    # Strip version comment from MAF so line 1 is the column header
    sed '1d' "${maf}" > maf_stripped.txt

    # Build region set from TSV (Chr col has no chr prefix; MAF Chromosome col has chr prefix)
    # TSV: \$1=Chr \$2=Start \$3=End  |  MAF: \$5=Chromosome \$6=Start_Position \$7=End_Position
    awk '
        NR==FNR { regions["chr" \$1 ":" \$2 "-" \$3] = 1; next }
        FNR==1  { print; next }
        \$5 ":" \$6 "-" \$7 in regions
    ' "${tsv}" maf_stripped.txt > "${meta.sample_id}_mutations.txt"
    """
}

// ---------------------------------------------------------------------------
// Collect: merge per-sample SV files into data_sv.txt
// ---------------------------------------------------------------------------
process MERGE_SV {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(sv_files)

    output:
    path("data_sv.txt")

    script:
    """
    files=( *_sv.txt )
    head -1 "\${files[0]}" > data_sv.txt
    for f in "\${files[@]}"; do
        tail -n +2 "\$f" >> data_sv.txt
    done
    """
}

// ---------------------------------------------------------------------------
// Collect: merge per-sample CNA files into data_cna.txt
// ---------------------------------------------------------------------------
process MERGE_CNA {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(cna_files)

    output:
    path("data_cna.txt")

    script:
    """
    files=( *_cna.txt )
    head -1 "\${files[0]}" > data_cna.txt
    for f in "\${files[@]}"; do
        tail -n +2 "\$f" >> data_cna.txt
    done
    """
}

// ---------------------------------------------------------------------------
// Collect: merge per-sample mutation files into data_mutations.txt
// ---------------------------------------------------------------------------
process MERGE_MUTATIONS {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(mutation_files)

    output:
    path("data_mutations.txt")

    script:
    """
    files=( *_mutations.txt )
    head -1 "\${files[0]}" > data_mutations.txt
    for f in "\${files[@]}"; do
        tail -n +2 "\$f" >> data_mutations.txt
    done
    """
}

// ---------------------------------------------------------------------------
// Once: format patient clinical file → data_clinical_patient.txt
// ---------------------------------------------------------------------------
process CLINICAL_PATIENTS {
    label 'python'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(patient_file)

    output:
    path("data_clinical_patient.txt")

    script:
    """
    clinical_patients_format.py ${patient_file}
    """
}

// ---------------------------------------------------------------------------
// Once: format sample clinical file → data_clinical_sample.txt
// ---------------------------------------------------------------------------
process CLINICAL_SAMPLES {
    label 'python'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(sample_file)

    output:
    path("data_clinical_sample.txt")

    script:
    """
    clinical_sample_format.py ${sample_file}
    """
}

// ---------------------------------------------------------------------------
// Once: deanonymise Tumor_Sample_Barcode in mutations file
// ---------------------------------------------------------------------------
process DEANON_MUTATIONS {
    label 'python'
    stageInMode 'copy'
    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
    path(mutations_file)
    path(linking_file)

    output:
    path("data_mutations.txt")

    script:
    """
    format_mutations.py ${mutations_file} ${linking_file}
    """
}

// ---------------------------------------------------------------------------
// Once: deanonymise Sample_Id in SV file
// ---------------------------------------------------------------------------
process DEANON_SV {
    label 'python'
    stageInMode 'copy'
    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
    path(sv_file)
    path(linking_file)

    output:
    path("data_sv.txt")

    script:
    """
    format_sv.py ${sv_file} ${linking_file}
    """
}

// ---------------------------------------------------------------------------
// Once: deanonymise Sample_Id in CNA file
// ---------------------------------------------------------------------------
process DEANON_CNA {
    label 'python'
    stageInMode 'copy'
    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
    path(cna_file)
    path(linking_file)

    output:
    path("data_cna.txt")

    script:
    """
    format_cna_deanon.py ${cna_file} ${linking_file}
    """
}

// ---------------------------------------------------------------------------
// Once: write cBioPortal meta files for all data types
// ---------------------------------------------------------------------------
process WRITE_META {
    label 'python'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    val(study_id)

    output:
    path("meta_*.txt")

    script:
    """
    format_meta.py "${study_id}"
    """
}

// ---------------------------------------------------------------------------
// Once: write cBioPortal case list files using deanonymised IDs
// ---------------------------------------------------------------------------
process WRITE_CASE_LISTS {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path(linking_file)
    val(study_id)

    output:
    path("case_lists")

    script:
    """
    mkdir -p case_lists

    IDS_TAB=\$(awk 'NR>1 {printf "%s\\t", \$2}' ${linking_file} | sed 's/\\t\$//')

    {
        echo "cancer_study_identifier: ${study_id}"
        echo "stable_id: ${study_id}_sequenced"
        echo "case_list_name: all mutations"
        echo "case_list_description: all mutations of ${study_id}"
        echo "case_list_ids: \${IDS_TAB}"
    } > case_lists/cases_sequenced.txt

    {
        echo "cancer_study_identifier: ${study_id}"
        echo "stable_id: ${study_id}_sv"
        echo "case_list_name: all sv"
        echo "case_list_description: all sv of ${study_id}"
        echo "case_list_ids: \${IDS_TAB}"
    } > case_lists/cases_sv.txt

    {
        echo "cancer_study_identifier: ${study_id}"
        echo "stable_id: ${study_id}_cna"
        echo "case_list_name: all cna"
        echo "case_list_description: all cna of ${study_id}"
        echo "case_list_ids: \${IDS_TAB}"
    } > case_lists/cases_cna.txt
    """
}
