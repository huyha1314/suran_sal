#!/bin/bash
#SBATCH --job-name=eggnog_func
#SBATCH --output=log/eggnog_%j.out
#SBATCH --error=log/eggnog_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=120G

# --- CONFIG ---
BASE_DIR="result"
ANNOTATION_DIR="${BASE_DIR}/annotation" 
OUT_DIR="${BASE_DIR}/eggnog"
DB_DIR="/mnt/10T/huyha/db/eggnog_db"   

mkdir -p "$OUT_DIR"

# Explicitly override the faulty environment variable
export EGGNOG_DATA_DIR="$DB_DIR"

# Loop through Bakta outputs
for faa_file in `ls ${ANNOTATION_DIR}/*/*.faa`; do
    
    # Get Sample Name
    sample=$(basename "$faa_file" .faa)
    
    echo "=== Running eggNOG-mapper on $sample ==="
    
    # Check if done
    if [[ -f "${OUT_DIR}/${sample}.emapper.annotations" ]]; then
        echo "Skipping $sample (Already done)"
        continue
    fi

    # Run Mapper
    micromamba run -n eggnog emapper.py \
        -i "$faa_file" \
        --output "$sample" \
        --output_dir "$OUT_DIR" \
        --data_dir "$DB_DIR" \
        -m diamond \
        --cpu 40 \
        --sensmode more-sensitive

    echo "=== Finished $sample ==="
done