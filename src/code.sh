#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir -p /home/dnanexus/out/output_fusions_files \
    /home/dnanexus/genome_lib \
    /home/dnanexus/out/output_discarded_fusions \
    /home/dnanexus/out/logs

#unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

if ! tar -xzf /home/dnanexus/in/arriba_tar/*.tar.gz -C /home/dnanexus/ --one-top-level=arriba --strip-components=1; then
    echo "Error: Failed to extract arriba library"
    exit 1
fi
ls

cd /home/dnanexus/arriba/
make
cd ..
export PATH=$PATH:/home/dnanexus/arriba

#Extract sample name from input_bam
sample_name=$(echo $bam_prefix | cut -d '_' -f 1)

# Run arriba
arriba \
    -x $bam_path \
    -o /home/dnanexus/out/output_fusions_files/${sample_name}_fusions.tsv -O /home/dnanexus/out/output_discarded_fusions/${sample_name}_fusions.discarded.tsv \
    -a /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa -g /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_annot.gtf \
    -b /home/dnanexus/arriba/database/blacklist_hg38_GRCh38_v*.tsv.gz -k /home/dnanexus/arriba/database/known_fusions_hg38_GRCh38_v*.tsv.gz -t /home/dnanexus/arriba/database/known_fusions_hg38_GRCh38_v*.tsv.gz -p /home/dnanexus/arriba/database/protein_domains_hg38_GRCh38_v*.gff3

for f in Log*; do
    mv "$f" "${sample_name}.$f";
done
mv /home/dnanexus/${sample_name}.Log* /home/dnanexus/out/logs

dx-upload-all-outputs
