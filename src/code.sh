#!/bin/bash

# prefixes all lines of commands written to stdout with datetime
PS4='\000[$(date)]\011'
export TZ=Europe/London

# fail on any error
set -exo pipefail

# set frequency of instance usage in logs to 10 seconds
kill $(ps aux | grep pcp-dstat | head -n1 | awk '{print $2}')
/usr/bin/dx-dstat 10

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/out/arriba_full \
    /home/dnanexus/out/arriba_discarded \
    /home/dnanexus/genome_lib

# samtools in htslib doesn't work as its missing a library, so
# will install the missing libraries from the downloaded deb files
# (so as to not use internet)
sudo dpkg -i libtinfo5_6.2-0ubuntu2_amd64.deb
sudo dpkg -i libncurses5_6.2-0ubuntu2_amd64.deb

# Unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

# Load arriba docker
docker load -i $arriba_tar_path
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^uhrigs/arriba" | cut -d' ' -f2)

# Find statements
arriba_version=$(docker run --rm -v /home/dnanexus:/data $DOCKER_IMAGE_ID /bin/bash -c 'ls / | grep arriba_v')
cytobands_file=$(docker run --rm -v /home/dnanexus:/data $DOCKER_IMAGE_ID /bin/bash -c 'ls /arriba_v*/database | grep cytobands_hg38')
protein_domains_file=$(docker run --rm -v /home/dnanexus:/data $DOCKER_IMAGE_ID /bin/bash -c 'ls /arriba_v*/database | grep protein_domains_hg38')
blacklist_file=$(docker run --rm -v /home/dnanexus:/data $DOCKER_IMAGE_ID /bin/bash -c 'ls /arriba_v*/database  | grep blacklist_hg38_GRCh38_v')
known_fusions=$(docker run --rm -v /home/dnanexus:/data $DOCKER_IMAGE_ID /bin/bash -c 'ls /arriba_v*/database  | grep known_fusions_hg38_GRCh38_v')

#Extract sample name from input_bam
sample_name=$(echo $bam_prefix | cut -d '.' -f 1)

# Run arriba
docker_cmd="${arriba_version}/arriba -x /data/in/bam/$bam_name \
    -o /data/out/arriba_full/${sample_name}_fusions.tsv \
    -O /data/out/arriba_discarded/${sample_name}_fusions.discarded.tsv \
    -g /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
    -a /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa  \
    -b /${arriba_version}/database/${blacklist_file}\
    -k /${arriba_version}/database/${known_fusions} \
    -t /${arriba_version}/database/${known_fusions} \
    -p /${arriba_version}/database/${protein_domains_file}"

time docker run --rm \
    -v /home/dnanexus:/data \
    $DOCKER_IMAGE_ID /bin/bash -c "eval $docker_cmd"

# Run the visualisation if requested by user
if [[ "${arriba_visual_script,,}" == "true" ]] ; then
    mkdir -p /home/dnanexus/out/arriba_visualisations/

    samtools index -b in/bam/${bam_name}

    docker_cmd_visualisation="${arriba_version}/draw_fusions.R \
        --fusions=/data/out/arriba_full/${sample_name}_fusions.tsv \
        --alignments=/data/in/bam/${bam_name} \
        --output=/data/out/arriba_visualisations/${sample_name}_fusions.pdf \
        --annotation=/data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
        --cytobands=/${arriba_version}/database/${cytobands_file} \
        --proteinDomains=/${arriba_version}/database/${protein_domains_file}"

    time docker run --rm \
        -v /home/dnanexus:/data \
        $DOCKER_IMAGE_ID /bin/bash -c "eval $docker_cmd_visualisation"
else
    echo "No visualisation requested by user, therefore no pdf plots of fusions is outputted"
fi


dx-upload-all-outputs