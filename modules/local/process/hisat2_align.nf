// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

process HISAT2_ALIGN {
    tag "$meta.id"
    label 'process_high'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:options, publish_dir:getSoftwareName(task.process), publish_id:meta.id) }

    container "quay.io/biocontainers/mulled-v2-a97e90b3b802d1da3d6958e0867610c718cb5eb1:2880dd9d8ad0a7b221d4eacda9a818e92983128d-0"
    //container "https://depot.galaxyproject.org/singularity/mulled-v2-a97e90b3b802d1da3d6958e0867610c718cb5eb1:2880dd9d8ad0a7b221d4eacda9a818e92983128d-0"

    conda (params.conda ? "bioconda::hisat2=2.2.0 bioconda::samtools=1.10" : null)

    input:
    tuple val(meta), path(reads)
    path index
    path splicesites
    val options

    output:
    tuple val(meta), path("*.bam"), emit: bam
    tuple val(meta), path("*.log"), emit: log
    tuple val(meta), path("*fastq.gz"), optional:true, emit: fastq
    path "*.version.txt", emit: version
    // path "${prefix}.bam" into hisat2_bam
    // path "${prefix}.hisat2_summary.txt" into alignment_logs
    // path "unmapped.hisat2*" optional true

    script:
    def software = getSoftwareName(task.process)
    def ioptions = initOptions(options)
    def prefix   = ioptions.suffix ? "${meta.id}${ioptions.suffix}" : "${meta.id}"

    // Figure out strandedness from pipeline parameters
    def unstranded       = params.unstranded
    def forward_stranded = params.forward_stranded
    def reverse_stranded = params.reverse_stranded
    if (params.pico) {
        unstranded       = false
        forward_stranded = true
        reverse_stranded = false
    }
    def rnastrandness = ''
    if (forward_stranded && !unstranded) {
        rnastrandness = meta.single_end ? '--rna-strandness F' : '--rna-strandness FR'
    } else if (reverse_stranded && !unstranded) {
        rnastrandness = meta.single_end ? '--rna-strandness R' : '--rna-strandness RF'
    }

    def seq_center = params.seq_center ? "--rg-id ${prefix} --rg CN:${params.seq_center.replaceAll('\\s','_')} SM:$prefix" : "--rg-id ${prefix} --rg SM:$prefix"
    if (meta.single_end) {
        def unaligned = params.save_unaligned ? "--un-gz unmapped.hisat2.gz" : ''
        """
        INDEX=`find -L ./ -name "*.1.ht2" | sed 's/.1.ht2//'`
        hisat2 \\
            -x \$INDEX \\
            -U $reads \\
            $rnastrandness \\
            --known-splicesite-infile $splicesites \\
            --summary-file ${prefix}.summary.log \\
            --threads $task.cpus \\
            $seq_center \\
            $unaligned \\
            $ioptions.args \\
            | samtools view -bS -F 4 -F 256 - > ${prefix}.bam

        echo \$(hisat2 --version 2>&1) | sed 's/^.*version //; s/64.*\$//' > ${software}.version.txt
        """
    } else {
        def unaligned = params.save_unaligned ? "--un-conc-gz unmapped.hisat2.gz" : ''
        """
        INDEX=`find -L ./ -name "*.1.ht2" | sed 's/.1.ht2//'`
        hisat2 \\
            -x \$INDEX \\
            -1 ${reads[0]} \\
            -2 ${reads[1]} \\
            $rnastrandness \\
            --known-splicesite-infile $splicesites \\
            --summary-file ${prefix}.summary.log \\
            --threads $task.cpus \\
            $seq_center \\
            $unaligned \\
            --no-mixed \\
            --no-discordant \\
            $ioptions.args \\
            | samtools view -bS -F 4 -F 8 -F 256 - > ${prefix}.bam

        echo \$(hisat2 --version 2>&1) | sed 's/^.*version //; s/64.*\$//' > ${software}.version.txt
        """
    }
}
