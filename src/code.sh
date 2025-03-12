#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/out/arriba_full \
    /home/dnanexus/out/arriba_discarded \
    /home/dnanexus/genome_lib

# Unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

# Load arriba docker
docker load -i $arriba_tar_path
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^uhrigs/arriba" | cut -d' ' -f2)

#Extract sample name from input_bam
sample_name=$(echo $bam_prefix | cut -d '.' -f 1)

# Run arriba

docker_cmd="arriba_v*/arriba -x /data/in/bam/$bam_name \
    -o /data/out/arriba_full/${sample_name}_fusions.tsv \
    -O /data/out/arriba_discarded/${sample_name}_fusions.discarded.tsv \
    -g /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
    -a /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa  \
    -b /arriba_v*/database/blacklist_hg38_GRCh38_v*.tsv.gz \
    -k /arriba_v*/database/known_fusions_hg38_GRCh38_v*.tsv.gz \
    -t /arriba_v*/database/known_fusions_hg38_GRCh38_v*.tsv.gz \
    -p /arriba_v*/database/protein_domains_hg38_GRCh38_v*.gff3"

time docker run --rm \
    -v /home/dnanexus:/data \
    $DOCKER_IMAGE_ID /bin/bash -c "eval $docker_cmd"

docker_cmd_visualisation="arriba_v*/draw_fusions.R \
    -f /data/out/arriba_full/${sample_name}_fusions.tsv \
    -a /data/in/bam/$bam_name \
    -o /data/out/arriba_visualisations/${sample_name}_fusions.pdf \
    -a /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf
    -c /arriba_v*/database/cytobands_hg19_hs37d5_GRCh37_v2.4.0.tsv
    -p /arriba_v*/database/protein_domains_hg19_hs37d5_GRCh37_v2.4.0.gff3"

time docker run --rm \
    -v /home/dnanexus:/data \
    $DOCKER_IMAGE_ID /bin/bash -c "eval $docker_cmd_visualisation"

if [ -f *fusions.pdf ]; then
    echo "fusions.pdf  exists."
    mkdir -p /data/out/arriba_visualisations/
    mv *fusions.pdf /data/out/arriba_visualisations/
else
    echo "fusions.pdf does not exist"
fi

dx-upload-all-outputs
