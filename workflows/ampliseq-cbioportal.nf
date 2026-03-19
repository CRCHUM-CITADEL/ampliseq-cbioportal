/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FORMAT_SV         } from '../modules/local/processes'
include { FORMAT_CNA        } from '../modules/local/processes'
include { STUB_MAF          } from '../modules/local/processes'
include { VCF_TO_MAF        } from '../modules/local/processes'
include { FILTER_MUTATIONS  } from '../modules/local/processes'
include { MERGE_SV          } from '../modules/local/processes'
include { MERGE_CNA         } from '../modules/local/processes'
include { MERGE_MUTATIONS   } from '../modules/local/processes'
include { CLINICAL_PATIENTS } from '../modules/local/processes'
include { CLINICAL_SAMPLES  } from '../modules/local/processes'
include { DEANON_MUTATIONS  } from '../modules/local/processes'
include { DEANON_SV         } from '../modules/local/processes'
include { DEANON_CNA        } from '../modules/local/processes'
include { WRITE_CASE_LISTS  } from '../modules/local/processes'
include { WRITE_META        } from '../modules/local/processes'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow AMPLISEQ_CBIOPORTAL {

    take:
    ch_samplesheet // channel: rows from samplesheet CSV

    main:

    // -------------------------------------------------------------------------
    // Build per-sample channel: tuple(meta, sample_folder)
    // -------------------------------------------------------------------------
    ch_samples = ch_samplesheet
        .map { row ->
            def meta = [
                group     : row.group,
                subject_id: row.subject_id,
                sample_id : row.sample_id,
            ]
            def folder = file(row.folder_location)
            if (!folder.exists()) {
                error "folder_location does not exist: ${folder}"
            }
            def tsvList = file("${row.folder_location}/analysis_*_export.tsv", glob: true)
            if (!tsvList) {
                error "No analysis_*_export.tsv found in: ${folder}"
            }
            def tsv = tsvList[0]
            tuple(meta, tsv, folder)
        }

    ch_tsv        = ch_samples.map { meta, tsv, folder -> tuple(meta, tsv) }
    ch_vcf_input  = ch_samples.map { meta, tsv, folder -> tuple(meta, folder) }

    // -------------------------------------------------------------------------
    // Per-sample: SV and CNA formatting (TSV-only steps)
    // -------------------------------------------------------------------------
    FORMAT_SV(ch_tsv)
    FORMAT_CNA(ch_tsv)

    // -------------------------------------------------------------------------
    // Per-sample: VCF → MAF (or stub for testing without Apptainer)
    // -------------------------------------------------------------------------
    if (params.skip_vcf2maf) {
        STUB_MAF(ch_vcf_input)
        ch_maf = STUB_MAF.out
    } else {
        if (!params.vcf2maf_sif) {
            error "params.vcf2maf_sif must be set when skip_vcf2maf is false"
        }
        if (!params.vep_data) {
            error "params.vep_data must be set when skip_vcf2maf is false"
        }
        ch_sif     = Channel.value(file(params.vcf2maf_sif))
        ch_vep     = Channel.value(file(params.vep_data))
        VCF_TO_MAF(ch_vcf_input, ch_sif, ch_vep)
        ch_maf = VCF_TO_MAF.out
    }

    // -------------------------------------------------------------------------
    // Per-sample: filter MAF rows to ampliseq regions
    // ch_maf = tuple(meta, maf)  +  ch_tsv = tuple(meta, tsv)
    // join on meta to produce tuple(meta, maf, tsv)
    // -------------------------------------------------------------------------
    FILTER_MUTATIONS(ch_maf.join(ch_tsv))

    // -------------------------------------------------------------------------
    // Collect: merge all per-sample outputs
    // -------------------------------------------------------------------------
    MERGE_SV(FORMAT_SV.out.collect())
    MERGE_CNA(FORMAT_CNA.out.collect())
    MERGE_MUTATIONS(FILTER_MUTATIONS.out.collect())

    // -------------------------------------------------------------------------
    // Once: clinical file formatting
    // -------------------------------------------------------------------------
    CLINICAL_PATIENTS(Channel.fromPath(params.patient_file))
    CLINICAL_SAMPLES(Channel.fromPath(params.sample_file))

    // -------------------------------------------------------------------------
    // Once: deanonymisation
    // -------------------------------------------------------------------------
    ch_linking = Channel.value(file(params.linking_file))

    DEANON_MUTATIONS(MERGE_MUTATIONS.out, ch_linking)
    DEANON_SV(MERGE_SV.out, ch_linking)
    DEANON_CNA(MERGE_CNA.out, ch_linking)

    // -------------------------------------------------------------------------
    // Once: write cBioPortal case lists and meta files
    // -------------------------------------------------------------------------
    WRITE_CASE_LISTS(ch_linking, params.study_id)
    WRITE_META(params.study_id)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
