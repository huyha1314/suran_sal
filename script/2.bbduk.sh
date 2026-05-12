#!/bin/bash
#SBATCH --job-name=bbduk_pipeline
#SBATCH --output=./log/bbduk_%j.out
#SBATCH --error=./log/bbduk_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=256G
#SBATCH --cpus-per-task=64

# Ensure log directories exist
mkdir -p log result/bbduk result/bowtie2 result/k2

# Loop through all _1.fq.gz files
for i1 in result/fastp/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    i2=${i1/_1.fq.gz/_2.fq.gz}

    # Define the final expected output files
    final_out1="result/k2/clean.${sample}_1.fq.gz"
    final_out2="result/k2/clean.${sample}_2.fq.gz"

    # --- CHECK: Skip if result already exists ---
    if [[ -f "$final_out1" && -f "$final_out2" ]]; then
        echo "Skipping sample: $sample (Result already exists)"
        continue
    fi

    echo "Processing sample: $sample"

    # --- Step 1: BBDuk quality filtering ---
    if [[ ! -f "result/bbduk/${sample}_1.fq.gz" ]]; then
        micromamba run -n bbduk bbduk.sh \
            in1=$i1 \
            in2=$i2 \
            out1=result/bbduk/${sample}_1.fq.gz \
            out2=result/bbduk/${sample}_2.fq.gz \
            outm1=result/bbduk/removed_${sample}_1.fq.gz \
            outm2=result/bbduk/removed_${sample}_2.fq.gz \
            entropy=0.6 \
            entropywindow=50 \
            entropyk=5 \
            threads=64
    fi

    # --- Define Correct Bowtie2 Outputs ---
    # Based on your file: nohuman.trim.BAC1.fq.1.gz
    # The pattern is: nohuman.${sample}.fq.1.gz
    bt2_out1="result/bowtie2/nohuman.${sample}.fq.1.gz"
    bt2_out2="result/bowtie2/nohuman.${sample}.fq.2.gz"

    # --- Step 2: Remove human reads with Bowtie2 ---
    # Check if bowtie2 output exists using the CORRECT variable
    if [[ ! -f "$bt2_out1" ]]; then
        micromamba run -n bowtie2 bowtie2 \
            --threads 64 \
            -x /mnt/10T/huyha/db/bowtie2_db/hg38_index \
            -1 result/bbduk/${sample}_1.fq.gz \
            -2 result/bbduk/${sample}_2.fq.gz \
            --un-conc-gz result/bowtie2/nohuman.${sample}.fq.gz \
            -S result/bowtie2/nohuman.${sample}.sam &> result/bowtie2/${sample}_bowtie2.log
    fi

    # --- Step 3: Taxonomic classification with Kraken2 ---
    if [[ ! -f "result/k2/${sample}.kraken.txt" ]]; then
        micromamba run -n bracken kraken2 \
            --db /mnt/10T/sepsis/database/k2_index_pluspf \
            --paired "$bt2_out1" "$bt2_out2" \
            --threads 64 \
            --report result/k2/${sample}.report.txt \
            --output result/k2/${sample}.kraken.txt \
            --minimum-base-quality 20 \
            --gzip-compressed \
            --confidence 0.1
    fi



    echo "Finished sample: $sample"
done


process_sample() {
    input_file="$1"
    
    # Extract sample name
    sample=$(basename "$input_file" | cut -d "_" -f1)
    
    # Define Input/Output names
    final_out1="result/k2/clean.${sample}_1.fq"
    final_out2="result/k2/clean.${sample}_2.fq"
    
    # Inputs (Uncompressed Bowtie2 output)
    bt2_out1="result/bowtie2/nohuman.${sample}.fq.1.gz"
    bt2_out2="result/bowtie2/nohuman.${sample}.fq.2.gz"
    
    # Report (Needed for --include-parents)
    report_file="result/k2/${sample}.report.txt"
    kraken_file="result/k2/${sample}.kraken.txt"

    # --- CHECK: Skip if result already exists ---
    if [[ -f "$final_out1.gz" && -f "$final_out2.gz" ]]; then
        echo "[$sample] Skipping - Output already exists."
        return
    fi

    # --- CHECK: Ensure inputs exist ---
    if [[ ! -f "$bt2_out1" || ! -f "$bt2_out2" ]]; then
        echo "[$sample] Error: Uncompressed Bowtie2 input not found. (Is it already gzipped?)"
        return
    fi

    echo "[$sample] Extracting reads..."

    # --- Step 4: Extract reads of interest ---
    micromamba run -n bracken extract_kraken_reads.py \
        -k "$kraken_file" \
        -r "$report_file" \
        -s "$bt2_out1" \
        -s2 "$bt2_out2" \
        -o "$final_out1" \
        -o2 "$final_out2" \
        -t 9606 --include-parents --exclude

    # --- Compress the large intermediate files ---
    # Using 8 threads per job. 5 jobs * 8 threads = 40 CPUs.
    echo "[$sample] Compressing intermediate files..."
    pigz -p 8 -f "$final_out1"
    pigz -p 8 -f "$final_out2"
    
    echo "[$sample] Finished."
}

# Export the function so 'parallel' can see it
export -f process_sample

# 2. Run in Parallel
# -j 5: Run 5 jobs simultaneously
echo "Starting Parallel Jobs..."
ls result/fastp/*_1.fq.gz | micromamba run -n base parallel -j 5 process_sample {}

echo "All jobs completed."