#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/out/output_fusions_files \
    /home/dnanexus/out/output_discarded_fusions \
    /home/dnanexus/out/logs \
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
    -o /data/out/output_fusions_files/${sample_name}_fusions.tsv -O /data/out/output_discarded_fusions/${sample_name}_fusions.discarded.tsv \
    -g /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf -a /data/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa  \
    -b /arriba_v*/database/blacklist_hg38_GRCh38_v*.tsv.gz \
    -k /arriba_v*/database/known_fusions_hg38_GRCh38_v*.tsv.gz \
    -t /arriba_v*/database/known_fusions_hg38_GRCh38_v*.tsv.gz \
    -p /arriba_v*/database/protein_domains_hg38_GRCh38_v*.gff3"

time docker run -v /home/dnanexus:/data $DOCKER_IMAGE_ID  /bin/bash -c "eval $docker_cmd"

for f in Log*; do
    mv "$f" "${sample_name}.$f";
done
mv /home/dnanexus/${sample_name}.Log* /home/dnanexus/out/logs

dx-upload-all-outputs
