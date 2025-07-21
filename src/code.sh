#!/bin/bash

# prefixes all lines of commands written to stdout with datetime
PS4='\000[$(date)]\011'
export TZ=Europe/London

# fail on any error
set -exo pipefail

# set frequency of instance usage in logs to 10 seconds
kill $(ps aux | grep pcp-dstat | head -n1 | awk '{print $2}')
/usr/bin/dx-dstat 10


_get_peak_usage() {
    : '''
    Reports the peak memory and storage usage from dstat, to be called at end of app
    '''
    dx watch $DX_JOB_ID --no-follow --quiet > job.log

    peak_mem=$(grep 'INFO CPU' job.log | cut -d':' -f5 | cut -d'/' -f1 | sort -n | tail -n1)
    total_mem="$(($(grep MemTotal /proc/meminfo | grep --only-matching '[0-9]*')/1024))"

    peak_storage=$(grep 'INFO CPU' job.log | cut -d':' -f6 | cut -d'/' -f1 | sort -n | tail -n1)
    total_storage=$(df -Pk / | awk 'NR == 2' | awk '{printf("%.0f", $2/1024/1024)}')

    echo "Memory usage peaked at ${peak_mem}/${total_mem}MB"
    echo "Storage usage peaked at ${peak_storage}/${total_storage}GB"
}

_set_env() {
    : '''
    Set up required environment variables, export to be available to child processes
    '''
    export docker_image_id \
        lib_dir \
        arriba_version \
        cytobands_file \
        protein_domains_file \
        blacklist_file \
        known_fusions \
        sample_name \
        star_fusion_bam

    # Extract CTAT library filename
    lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

    # Extract sample name from input_bam
    sample_name=$(echo $bam_prefix | cut -d '.' -f 1)
    star_fusion_bam="$bam_name"

    docker_image_id=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^uhrigs/arriba" | cut -d' ' -f2)

    arriba_version=$(docker run --rm -v /home/dnanexus:/data $docker_image_id /bin/bash -c 'ls / | grep arriba_v')
    cytobands_file=$(docker run --rm -v /home/dnanexus:/data $docker_image_id /bin/bash -c 'ls /arriba_v*/database | grep cytobands_hg38')
    protein_domains_file=$(docker run --rm -v /home/dnanexus:/data $docker_image_id /bin/bash -c 'ls /arriba_v*/database | grep protein_domains_hg38')
    blacklist_file=$(docker run --rm -v /home/dnanexus:/data $docker_image_id /bin/bash -c 'ls /arriba_v*/database  | grep blacklist_hg38_GRCh38_v')
    known_fusions=$(docker run --rm -v /home/dnanexus:/data $docker_image_id /bin/bash -c 'ls /arriba_v*/database  | grep known_fusions_hg38_GRCh38_v')
}

_download_and_setup() {
    : '''
    Downloads input files, unpacks and other setup steps
    '''
    mkdir -p /home/dnanexus/out/arriba_full \
        /home/dnanexus/out/arriba_discarded \
        /home/dnanexus/genome_lib \
        /home/dnanexus/input

    time dx-download-all-inputs --parallel

    dpkg -i sysstat_12.2.0-2ubuntu0.3_amd64.deb
    dpkg -i parallel_20161222-1.1_all.deb
    dpkg -i libqpdf26_9.1.1-1ubuntu0.1_amd64.deb
    dpkg -i qpdf_9.1.1-1ubuntu0.1_amd64.deb

    docker load -i "$arriba_tar_path"

    find ~/in -type f -name "*.bam*" -print0 | xargs -0 -I {} mv {} ~/input
    touch -c input/*.bai  # suppress warning of index being older from samtools

    # Unpack CTAT bundle file
    /usr/bin/pigz -dc /home/dnanexus/in/genome_lib/*.tar.gz | tar xf - -C /home/dnanexus/genome_lib
}

_call_arriba() {
    : '''
    Run Arriba to generate fusion calls
    '''
    docker run --rm \
        -v /home/dnanexus:/data \
        $docker_image_id /bin/bash -c "${arriba_version}/arriba \
            -x /data/input/$bam_name \
            -o /data/out/arriba_full/${sample_name}_fusions.tsv \
            -O /data/out/arriba_discarded/${sample_name}_fusions.discarded.tsv \
            -g /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
            -a /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa  \
            -b /${arriba_version}/database/${blacklist_file} \
            -k /${arriba_version}/database/${known_fusions} \
            -t /${arriba_version}/database/${known_fusions} \
            -p /${arriba_version}/database/${protein_domains_file}"
}

_annotate_fusions() {
    : '''
    Annotate fusions with exon numbers.

    The script requires at least the header and one fusion line to run.
    If there are fusions, it will run the annotation script and replace
    the original fusions file with the annotated one.
    '''
    local fusions_file="out/arriba_full/${sample_name}_fusions.tsv"
    local annotated_fusions_file="out/arriba_full/${sample_name}_fusions.annotated.tsv"
    local gtf_file="/data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf"
    local annotation_script="/${arriba_version}/scripts/annotate_exon_numbers.sh"

    if [[ $(wc -l < "$fusions_file") -ge 2 ]]; then
        echo "Annotating fusions with exon numbers"

        docker run --rm -v /home/dnanexus:/data "$docker_image_id" /bin/bash -c \
            "${annotation_script} /data/${fusions_file} ${gtf_file} /data/${annotated_fusions_file}"

        mv "$annotated_fusions_file" "$fusions_file"
    else
        echo "No fusions found, skipping annotation."
    fi
}

_setup_arriba_visualisation() {
    : '''
    Setup for calling Arriba visualisation.

    Splits out fusion calls to equal length files for number of CPU cores available with
    original header for calling visualisation script in parallel.
    '''
    mkdir -p /home/dnanexus/out/arriba_visualisations/ \
            /home/dnanexus/split_fusions \
            /home/dnanexus/split_pdfs \
            /home/dnanexus/visualisation_logs

    local fusions_file="out/arriba_full/${sample_name}_fusions.tsv"
    local header

    header=$(head -n1 "$fusions_file")

    sed -i '1d' "$fusions_file"
    split -n l/$(nproc --all) -e "$fusions_file" split_fusions/
    find split_fusions/ -type f -exec sed -i "1 i $header" {} \;

    echo "$(wc -l < "$fusions_file") fusions to generate plots for, splitting across $(nproc --all) processes"

    sed -i "1 i $header" "$fusions_file"
}

_call_arriba_visualisation() {
    : '''
    Calls command to generate PDF of given gene fusion pairs. To be called in parallel.

    Inputs
    ------
    file : tsv file of fusion pairs

    Outputs
    -------
    file : PDF of fusion pairs visualisation
    '''
    local file=$1
    local output_suffix
    local command

    output_suffix=$(basename $file)

    command="${arriba_version}/draw_fusions.R \
            --fusions=/data/${file} \
            --alignments=/data/input/${star_fusion_bam} \
            --output=/data/split_pdfs/${output_suffix}_fusions.pdf \
            --annotation=/data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
            --cytobands=/${arriba_version}/database/${cytobands_file} \
            --proteinDomains=/${arriba_version}/database/${protein_domains_file}"

    echo "Running Arriba visualisation with inputs: ${command}" 1>>dx_stdout

    docker run --rm -v /home/dnanexus:/data \
        $docker_image_id /bin/bash -c "${command}" 1>>dx_stdout 2>>dx_stderr
}

main() {

    _download_and_setup
    _set_env
    _call_arriba
    _annotate_fusions

    # Run the visualisation if requested by user
    if [[ "${arriba_visual_script,,}" == "true" ]]; then
        if [[ $(wc -l < out/arriba_full/${sample_name}_fusions.tsv) -ge 2 ]]; then
            _setup_arriba_visualisation

            # run Arriba to generate visualisations in parallel
            SECONDS=0
            export -f _call_arriba_visualisation
            find split_fusions/ -type f -print0 | parallel --null "_call_arriba_visualisation {}"

            duration=$SECONDS
            echo "Generated fusion visualisations in $(($duration / 60))m$(($duration % 60))s"

            # join PDFs to single output
            qpdf --empty --pages split_pdfs/* -- out/arriba_visualisations/${sample_name}_fusions.pdf

        else
            echo "WARNING: visualisation specified but no fusions have been called, skipping..."
        fi
    else
        echo "No visualisation requested by user, therefore no pdf plots of fusions to be output"
    fi

    dx-upload-all-outputs --parallel

    _get_peak_usage
}
