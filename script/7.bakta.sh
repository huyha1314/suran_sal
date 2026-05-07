#!/bin/bash
#SBATCH --job-name=bakta_annotation
#SBATCH --output=log/bakta_%j.out
#SBATCH --error=log/bakta_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G

# --- CONFIGURATION ---
BASE_DIR="/mnt/10T/huyha/precisiongene/wgs_bac/result"
IN_DIR="result/final_polished"  # Output from Pilon Round 2
OUT_DIR="result/annotation"
# In your SLURM script:
DB_PATH="/mnt/12T/huyha/db/bakta_db/db"

mkdir -p "$OUT_DIR" log

# Loop through Pilon polished assemblies
# Pattern matches output from your Pilon script: result/final_polished/SAMPLE/SAMPLE_final_polished.fasta
for assembly in ${IN_DIR}/*/*_final_polished.fasta; do

    # Extract sample name
    filename=$(basename "$assembly")
    sample=$(echo "$filename" | sed 's/_final_polished.fasta//')
    
    echo "=== Annotating Sample: $sample ==="

    # Define output folder for this sample
    sample_out="${OUT_DIR}/${sample}"
    
    # Check if already done (Bakta produces a .gbff file)
    if [[ -f "${sample_out}/${sample}.gbff" ]]; then
        echo "Annotation exists for $sample. Skipping."
        continue
    fi

    # Run Bakta
    # --force: overwrites output folder if it exists (but is empty/failed)
    # --locus-tag: creates unique IDs (e.g., SAMPLE_0001)
    # --genus/--species: Optional, helps if you know the taxonomy (from Kraken2 step)
    
    micromamba run -n bakta bakta \
        --db "$DB_PATH" \
        --output "$sample_out" \
        --prefix "$sample" \
        --locus-tag "$sample" \
        --threads 32 \
        --force \
        "$assembly"

    echo "=== Finished $sample ==="
done