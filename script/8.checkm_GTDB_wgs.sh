#!/bin/bash
#SBATCH --job-name=bac_tax_flow
#SBATCH --output=log/tax_%j.out
#SBATCH --error=log/tax_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=350G 

# --- CONFIGURATION ---
BASE_DIR="result/final_polished"
COLLECTED_DIR="result/collected_assemblies"
CHECKM_OUT_DIR="result/checkm_assembly"
GTDB_OUT_DIR="result/gtdbtk_assembly"
SCRATCH_DIR="${BASE_DIR}/gtdbtk_scratch"
# Set Database Path (Update if needed)
export GTDBTK_DATA_PATH="/mnt/12T/huyha/db/gtdbtk_r220_data/release226"

# Create output directories
mkdir -p "$COLLECTED_DIR" "$CHECKM_OUT_DIR" "$GTDB_OUT_DIR"

# --- STEP 1: Collect Assembly Files ---
echo "Starting Collection of Assemblies..."
echo "--------------------------------"

# Loop through your specific samples
# Note: Add all your sample names here if you have more than 4
for SAMPLE in sam1; do
    
    # Construct input path based on your Pilon output structure
    INPUT_FILE="${BASE_DIR}/${SAMPLE}/${SAMPLE}_final_polished.fasta"
    
    # Verify file exists before copying
    if [[ -f "$INPUT_FILE" ]]; then
        echo "Copying $SAMPLE..."
        cp "$INPUT_FILE" "${COLLECTED_DIR}/${SAMPLE}.fasta"
    else
        echo "WARNING: File not found for $SAMPLE: $INPUT_FILE"
    fi
done

echo "Collection complete. Total genomes: $(ls $COLLECTED_DIR | wc -l)"
echo "--------------------------------"


# --- STEP 2: Run CheckM (Quality) ---
echo "Starting CheckM Lineage Workflow..."

# # -x fasta: tells CheckM to look for .fasta extension (matches the cp command above)
micromamba run -n binning checkm lineage_wf \
    -t 40 \
    -x fasta \
    --pplacer_threads 40 \
    "$COLLECTED_DIR" \
    "$CHECKM_OUT_DIR"

# Generate a readable summary table
micromamba run -n binning checkm qa \
    "${CHECKM_OUT_DIR}/lineage.ms" \
    "${CHECKM_OUT_DIR}" \
    -o 2 > "${CHECKM_OUT_DIR}/checkm_summary.txt"

echo "CheckM Finished. See: ${CHECKM_OUT_DIR}/checkm_summary.txt"


# --- STEP 3: Run GTDB-Tk (Taxonomy) ---
echo "Starting GTDB-Tk Classify Workflow..."

micromamba run -n gtdbtk gtdbtk classify_wf \
    --genome_dir "result/collected_assemblies" \
    --out_dir "$GTDB_OUT_DIR" \
    --extension fasta \
    --cpus 30 \
    --pplacer_cpus 10 \
    --skip_ani_screen \
    --min_perc_aa 10

echo "GTDB-Tk Finished."