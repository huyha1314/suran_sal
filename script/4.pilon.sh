#!/bin/bash
#SBATCH --job-name=bwa_pilon
#SBATCH --output=./log/bwa_pilon_%j.out
#SBATCH --error=./log/bwa_pilon_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=180G
#SBATCH --cpus-per-task=48


# Create necessary directories
mkdir -p log result/bwa_pilon

# Paths
READ_DIR="result/k2"           # location of clean reads
ASM_DIR="result/megahit"     # UPDATED: Matches your previous script output folder
OUT_DIR="result/bwa_pilon"     # output folder
PILON_JAR="/home/huyha/micromamba/envs/pilon/share/pilon-1.24-0/pilon.jar" # Verify this path exists!

# Loop through all assemblies
# Matches pattern: result/megahit_2/SAMPLE_assembly/final.contigs.fa
for asm in ${ASM_DIR}/*_assembly/final.contigs.fa; do
    # Extract sample name (removes path and _assembly suffix)
    sample=$(basename $(dirname "$asm") | sed 's/_assembly//')
    
    echo "=== Processing sample: $sample ==="

    fq1="${READ_DIR}/clean.${sample}_1.fq.gz"
    fq2="${READ_DIR}/clean.${sample}_2.fq.gz"
    workdir="${OUT_DIR}/${sample}"
    
    mkdir -p "$workdir"

    # --- Check for Final Output ---
    final_fasta="${workdir}/${sample}_pilon.fasta"
    if [[ -s "$final_fasta" ]]; then
        echo "--- Final Pilon file already exists, skipping $sample ---"
        continue
    fi

    # --- Check Inputs ---
    if [[ ! -f "$fq1" || ! -f "$fq2" ]]; then
        echo "Error: Reads for $sample not found in $READ_DIR. Skipping."
        continue
    fi

    # --- Step 1 & 2: Index and Align ---
    if [[ ! -s "${workdir}/${sample}.sorted.bam" ]]; then
        
        # 1. Indexing (BWA + Samtools FAI)
        # Only run if indices are missing
        if [[ ! -f "${asm}.bwt" || ! -f "${asm}.fai" ]]; then
            echo "--- Indexing Assembly for $sample ---"
            micromamba run -n bwa bwa index "$asm"
            micromamba run -n bwa samtools faidx "$asm"
        fi

        # 2. Alignment
        echo "--- Aligning reads for $sample ---"
        # OPTIMIZATION: 
        # You have 48 CPUs. 
        # bwa mem: 36 threads + samtools sort: 10 threads = 46 threads (leaves 2 for system overhead)
        # Added -m 4G to samtools sort to utilize RAM and reduce disk writing
        micromamba run -n bwa bwa mem -t 36 "$asm" "$fq1" "$fq2" | \
            micromamba run -n bwa samtools sort -@ 10 -m 4G -o "${workdir}/${sample}.sorted.bam" -

        # 3. Index BAM
        echo "--- Indexing BAM for $sample ---"
        micromamba run -n bwa samtools index "${workdir}/${sample}.sorted.bam"

    else
        echo "--- Found existing BAM for $sample ---"
    fi

    # --- Step 3: Pilon Polishing ---
    echo "--- Running Pilon for $sample ---"
     # 3. Index BAM
        echo "--- Indexing BAM for $sample ---"
        micromamba run -n bwa samtools index "${workdir}/${sample}.sorted.bam"
        
    # JAVA_OPTS logic:
    # -Xmx160G: You have 180G total. 160G for Java heap leaves 20G for OS overhead.
    micromamba run -n pilon java -Xmx160G -jar "$PILON_JAR" \
        --genome "$asm" \
        --frags "${workdir}/${sample}.sorted.bam" \
        --output "${sample}_pilon" \
        --outdir "$workdir" \
        --vcf \
        --changes \
        --fix all \
        --threads 48

    echo "=== Finished Pilon for sample: $sample ==="
done

echo "=== All samples processed ==="