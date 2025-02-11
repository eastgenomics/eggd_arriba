#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/out/output_fusions_files \
    /home/dnanexus/out/output_discarded_fusions \
    /home/dnanexus/out/logs

#unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

# Direct to bam file
bam_file="/home/dnanexus/in/bam_file/*.bam"

# download all inputs, untar plug-n-play resources, and set PATH to arriba directory
# mark-section "Download inputs and set up initial directories and values"
if ! tar -xzf /home/dnanexus/in/arriba_tar/*.tar.gz -C /home/dnanexus/ --one-top-level=arriba; then
    echo "Error: Failed to extract arriba library"
    exit 1
fi

cd arriba && make
cd ..
export PATH=$PATH:/home/dnanexus/arriba

#Extract sample name from input_bam
sample_name=$(echo $bam_file | cut -d '_' -f 1)

# Run arriba
arriba \
    -x /home/dnanexus/in/bam/ \
    -o /home/dnanexus/out/${sample_name}_fusions.tsv -O /home/dnanexus/out/${sample_name}_fusions.discarded.tsv \
    -a /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa -g /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
    -b //home/dnanexus/arriba/database/blacklist_hg38_GRCh38_v*.tsv.gz -k /home/dnanexus/arriba/database/known_fusions_hg38_GRCh38_v*.tsv.gz -t /home/dnanexus/arriba/database/known_fusions_hg38_GRCh38_v*.tsv.gz -p /home/dnanexus/arriba/database/protein_domains_hg38_GRCh38_v*.gff3

# Move output files with error handling
for file in "${sample_name}_fusions.tsv" "${sample_name}_fusions.discarded.tsv"; do
    if [ ! -f "/home/dnanexus/out/$file" ]; then
        echo "Error: Expected output file not found: $file"
        exit 1
    fi
done

if ! mv /home/dnanexus/out/${sample_name}_fusions.tsv /home/dnanexus/out/output_fusions_files || \
   ! mv /home/dnanexus/out/${sample_name}_fusions.discarded.tsv /home/dnanexus/out/output_discarded_fusions; then
    echo "Error: Failed to move output files"
    exit 1

for f in Log*; do mv "$f" "${sample_name}.$f"; done
mv /home/dnanexus/${sample_name}.Log* /home/dnanexus/out/logs

dx-upload-all-outputs
