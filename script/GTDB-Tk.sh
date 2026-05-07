#!/bin/bash
#SBATCH --job-name=gtdbtk_class
#SBATCH --output=./log/gtdb_%j.out
#SBATCH --error=./log/gtdb_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=300G 

# --- CONFIG ---
BASE_DIR="/mnt/10T2/huyha/precisiongene/wgs_bac/result"
BINNING_DIR="${BASE_DIR}/binning"
GTDB_OUT_DIR="${BASE_DIR}/gtdbtk"
GOOD_BINS_DIR="${BASE_DIR}/good_bins_collection"

# Set GTDB-Tk Data Path (Update this!)
export GTDBTK_DATA_PATH="/mnt/12T/huyha/db/gtdbtk_r220_data/release226"

mkdir -p "$GTDB_OUT_DIR" "$GOOD_BINS_DIR"

# --- Step 1: Gather and Filter High-Quality Bins ---
# We use a simple criteria: CheckM output usually needs parsing, 
# but for now, let's copy ALL bins and GTDB-Tk will filter them if they are too fragmented.
# (If you want strict filtering: Completeness > 50%, Contamination < 10%)

echo "Gathering bins from all samples..."

for sample_dir in ${BINNING_DIR}/*; do
    sample=$(basename "$sample_dir")
    
    # Check if bins directory exists
    if [[ -d "${sample_dir}/bins" ]]; then
        # Copy bins to the collection folder
        # We rename them to ensure uniqueness: sample_bin.1.fa
        for bin in ${sample_dir}/bins/*.fa; do
            bin_name=$(basename "$bin")
            cp "$bin" "${GOOD_BINS_DIR}/${sample}_${bin_name}"
        done
    fi
done

echo "Total bins collected: $(ls $GOOD_BINS_DIR | wc -l)"

# --- Step 2: Run GTDB-Tk ---
echo "Running GTDB-Tk Classify Workflow..."

# Note: --scratch_dir is useful if your temp directory is small
micromamba run -n gtdbtk gtdbtk classify_wf \
    --genome_dir "$GOOD_BINS_DIR" \
    --out_dir "$GTDB_OUT_DIR" \
    --extension fa \
    --cpus 40 \
    --skip_ani_screen \
    --min_perc_aa 10

echo "GTDB-Tk Finished."