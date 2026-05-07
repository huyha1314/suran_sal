#!/bin/bash
#SBATCH --job-name=k2_pipeline
#SBATCH --output=./log/k2_%j.out
#SBATCH --error=./log/k2_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=20
mkdir -p result/k2_as
for i1 in result/fastp/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    i2=${i1/_1.fq.gz/_2.fq.gz}
    echo "Processing sample: $sample"
    # Run Kraken2
     micromamba run -n bracken kraken2 \
        --db /mnt/10T2/sepsis/database/k2_index_pluspf \
        --threads 20 \
        --report "result/k2_as/${sample}.report.txt" \
        --output "result/k2_as/${sample}.kraken.txt" \
        --minimum-base-quality 20 \
        --confidence 0.1 \
        result/megahit_2/${sample}_assembly/final.contigs.fa
    echo "Finished sample: $sample"
done
