process FORMAT_CNA_VCF {
    tag "${meta.sample_id}"
    label 'python'

    input:
    tuple val(meta), path(sample_folder)

    output:
    path("${meta.sample_id}_cna.txt")

    script:
    """
    CNV_VCF=\$(find -L "${sample_folder}" -maxdepth 1 -name '*-basespace-cnv.final.vcf' | head -1)
    [ -n "\$CNV_VCF" ] || { echo "ERROR: No *-basespace-cnv.final.vcf found in ${sample_folder}" >&2; exit 1; }

    format_cna_vcf.py "\$CNV_VCF" "${meta.sample_id}"
    mv data_cna.txt "${meta.sample_id}_cna.txt"
    """
}
