#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/genomeDir \
    /home/dnanexus/out/output_fusions_files \
    /home/dnanexus/out/output_discarded_fusions \
    /home/dnanexus/out/logs

#unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

# Move bam files to input_bam directory
find ~/in/input_bams -type f -name "*" -print0 | xargs -0 -I {} mv {} ~/input_bams

# download all inputs, untar plug-n-play resources, and set PATH to arriba directory
# mark-section "Download inputs and set up initial directories and values"
if ! tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib; then
    echo "Error: Failed to extract genome library"
    exit 1
fi
cd arriba_v2.4.0 && make
cd ..
export PATH=$PATH:/home/dnanexus/arriba_v2.4.0

bams=($(ls /home/dnanexus/input_bams/*.bam))

#Extract sample name from input_bam
sample_name=$(echo ${bams[0]} | cut -d '_' -f 1)

# Run arriba
arriba \
    -x /home/dnanexus/input_bams \
    -o /home/dnanexus/out/${sample_name}_fusions.tsv -O /home/dnanexus/out/${sample_name}_fusions.discarded.tsv \
    -a /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa -g /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
    -b /home/dnanexus/arriba_v2.4.0/database/blacklist_hg38_GRCh38_v2.4.0.tsv.gz -k /home/dnanexus/arriba_v2.4.0/database/known_fusions_hg38_GRCh38_v2.4.0.tsv.gz -t /home/dnanexus/arriba_v2.4.0/database/known_fusions_hg38_GRCh38_v2.4.0.tsv.gz -p /home/dnanexus/arriba_v2.4.0/database/protein_domains_hg38_GRCh38_v2.4.0.gff3

# Move output files to /out directory to be uploaded
mv /home/dnanexus/out/${sample_name}_fusions.tsv /home/dnanexus/out/output_fusions_files
mv /home/dnanexus/out/${sample_name}_fusions.discarded.tsv /home/dnanexus/out/output_discarded_fusions

for f in Log*; do mv "$f" "${sample_name}.$f"; done
mv /home/dnanexus/${sample_name}.Log* /home/dnanexus/out/logs

dx-upload-all-outputs
