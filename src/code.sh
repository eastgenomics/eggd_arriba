#!/bin/bash

# fail on any error
set -exo pipefail

# Download all inputs from dx json
dx-download-all-inputs

mkdir /home/dnanexus/genomeDir
mkdir /home/dnanexus/genome_lib
mkdir /home/dnanexus/reference_genome
mkdir /home/dnanexus/input_bams
mkdir /home/dnanexus/arriba_tar
mkdir /home/dnanexus/out/output_fusions_files
mkdir /home/dnananexus/out/output_discarded_fusions
mkdir /home/dnanexus/out/logs

#unpack CTAT bundle file
tar xvzf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/genome_lib

# Extract CTAT library filename
lib_dir=$(find /home/dnanexus/genome_lib -type d -name "*" -mindepth 1 -maxdepth 1 | rev | cut -d'/' -f-1 | rev)

# Move genome indices and reference genome to specific folders
mv /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa.star.idx/* /home/dnanexus/genomeDir/
mv /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa /home/dnanexus/reference_genome
mv /home/dnanexus/genome_lib/${lib_dir}/ctat_genome_lib_build_dir/ref_genome.fa.fai /home/dnanexus/reference_genome

# Move bam files to input_bam directory
find ~/in/input_bams -type f -name "*" -print0 | xargs -0 -I {} mv {} ~/input_bams

# download all inputs, untar plug-n-play resources, and set PATH to arriba directory
# mark-section "Download inputs and set up initial directories and values"
tar -xzf /home/dnanexus/in/arriba_tar/*.tar.gz -C /home/dnanexus/
cd arriba_v2.4.0 && make
cd ..
export PATH=$PATH:/home/dnanexus/arriba_v2.4.0

bams=($(ls /home/dnanexus/input_bams*.bam))

#Extract sample name from input_bam
sample_name=$(echo $bams[0] | cut -d '_' -f 1)

# Run arriba
arriba \
    -x /home/dnanexus/input_bams \
    -o /home/dnanexus/out/${sample_name}_fusions.tsv -O /home/dnanexus/out/${sample_name}_fusions.discarded.tsv \
    -a GRCh38.fa -g GENCODE38.gtf \
    -b database/blacklist_hg38_GRCh38_v2.4.0.tsv.gz -k database/known_fusions_hg38_GRCh38_v2.4.0.tsv.gz -t database/known_fusions_hg38_GRCh38_v2.4.0.tsv.gz -p database/protein_domains_hg38_GRCh38_v2.4.0.gff3

# Move output files to /out directory to be uploaded
mv /home/dnanexus/out/${sample_name}_fusions.tsv /home/dnanexus/out/output_fusions_files
mv /home/dnanexus/out/${sample_name}_fusions.discarded.tsv /home/dnanexus/out/output_discarded_fusions

for f in Log*; do mv "$f" "${sample_name}.$f"; done
mv /home/dnanexus/${sample_name}.Log* /home/dnanexus/out/logs

dx-upload-all-outputs