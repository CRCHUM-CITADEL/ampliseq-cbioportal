process STUB_SV {
    tag "${meta.sample_id}"

    input:
    tuple val(meta), path(tsv)

    output:
    path("${meta.sample_id}_sv.txt")

    script:
    """
    printf 'Sample_Id\\tSV_Status\\tSite1_Hugo_Symbol\\tSite1_Chromosome\\tSite1_Region\\tSite2_Hugo_Symbol\\tClass\\tTumor_Variant_Count\\tSV_Length\\n' > "${meta.sample_id}_sv.txt"
    """
}
