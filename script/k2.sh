#!/bin/bash
#SBATCH --job-name=k2_pipeline
#SBATCH --output=./log/k2_%j.out
#SBATCH --error=./log/k2_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=20
mkdir -p result/k2
for i1 in result/fastp/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    i2=${i1/_1.fq.gz/_2.fq.gz}
    if [[ -s result/k2/${sample}.report.txt ]]; then 
        echo "Skipping ${sample}"
        continue
        fi
    echo "Processing sample: $sample"
if false; then
    # Run Kraken2
     micromamba run -n bracken kraken2 \
        --db /mnt/10T2/sepsis/database/k2_index_pluspf \
        --paired "result/bowtie2/nohuman.${sample}.fq.1.gz" "result/bowtie2/nohuman.${sample}.fq.2.gz"  \
        --threads 20 \
        --report "result/k2/${sample}.report.txt" \
        --output "result/k2/${sample}.kraken.txt" \
        --minimum-base-quality 20 \
        --gzip-compressed \
        --confidence 0.1 \
        --unclassified-out "result/k2/uncl.clean.${sample}#.fq"
fi

    # --- Step 4: Extract reads of interest from Kraken2 report ---
    micromamba run -n bracken python /mnt/10T2/huyha/KrakenTools/extract_kraken_reads.py \
        -r "result/k2/${sample}.report.txt" \
        -k  "result/k2/${sample}.kraken.txt" \
        -s "result/bowtie2/nohuman.${sample}.fq.1.gz" \
       -s2 "result/bowtie2/nohuman.${sample}.fq.2.gz" \
        -o result/k2/extract_${sample}_1.fq \
        -o2 result/k2/extract_${sample}_2.fq \
        -t 5073 --include-children --fastq-output 

cat result/k2/uncl.clean.${sample}_1.fq > result/k2/clean.${sample}_1.fq 
cat result/k2/uncl.clean.${sample}_2.fq > result/k2/clean.${sample}_2.fq
cat result/k2/extract_${sample}_1.fq >> result/k2/clean.${sample}_1.fq 
cat result/k2/extract_${sample}_2.fq >> result/k2/clean.${sample}_2.fq

    pigz -p 20 result/k2/clean.${sample}_1.fq 
    pigz -p 20 result/k2/clean.${sample}_2.fq

    echo "Finished sample: $sample"
done
