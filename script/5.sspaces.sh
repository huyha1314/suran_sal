#!/bin/bash
#SBATCH --job-name=sspace_bac
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=60
#SBATCH --mem=240G
#SBATCH --output=log/sspace_bac_%j.out
#SBATCH --error=log/sspace_bac_%j.err

# --- CONFIGURATION ---
# UPDATED: Changed from wgs_pen to wgs_bac based on your ls output
BASE_DIR="/mnt/10T/huyha/precisiongene/suran_sal"
READ_DIR="$BASE_DIR/result/fastp"       
ASM_DIR="$BASE_DIR/result/megahit"      
OUT_DIR="$BASE_DIR/result/sspaces"      

mkdir -p "$OUT_DIR" log

# Loop through reads (Expecting format: trim.BAC1_1.fq.gz)
for i1 in ${READ_DIR}/*_1.fq.gz; do
    
    filename=$(basename "$i1")
    # 1. Extract clean Sample Name (BAC1) from filename (trim.BAC1_1.fq.gz)
    # Remove _1.fq.gz -> trim.BAC1
    temp_name="${filename%_1.fq.gz}"
    # Remove trim. prefix -> BAC1
    sample="${temp_name#trim.}"
    
    echo "=== Processing Sample: $sample ==="

    # 2. Define the Assembly Path (Using the 'trim.' prefix found in your ls)
    contigs_in="${ASM_DIR}/trim.${sample}_assembly/final.contigs.fa"

    # Verify assembly exists
    if [[ ! -f "$contigs_in" ]]; then
        echo "❌ Error: Assembly not found at $contigs_in"
        continue
    fi

    # Define Inputs
    r1_in="${READ_DIR}/${filename}"
    r2_in="${r1_in/_1.fq.gz/_2.fq.gz}"

    # Define Work Directory
    WORK_DIR="${OUT_DIR}/${sample}_scaffold"
    mkdir -p "$WORK_DIR"
    
    # Check if finished
    final_output="${WORK_DIR}/${sample}_sspace.final.scaffolds.fasta"
    if [[ -s "$final_output" ]]; then
        echo "Skipping $sample (Already done)"
        continue
    fi

    cd "$WORK_DIR" || exit

    # 3. Decompress reads locally
    echo "📦 Decompressing reads..."
    if [[ ! -f "reads_R1.fq" ]]; then
        gunzip -c "$r1_in" > "reads_R1.fq"
    fi
    if [[ ! -f "reads_R2.fq" ]]; then
        gunzip -c "$r2_in" > "reads_R2.fq"
    fi

    # 4. Prepare Contigs (Clean headers)
    echo "🧹 Cleaning headers..."
    cp "$contigs_in" "contigs.fa"
    sed -i 's/ .*//' "contigs.fa"

    # 5. Create Library File
    printf "Lib${sample}\t${WORK_DIR}/reads_R1.fq\t${WORK_DIR}/reads_R2.fq\t350\t0.5\tFR\n" > "library.txt"

    # 6. Run SSPACE
    echo "🧬 Running SSPACE..."
    micromamba run -n sspace_basic SSPACE_Basic.pl \
        -l "library.txt" \
        -s "contigs.fa" \
        -x 0 -m 32 -k 5 -a 0.7 \
        -b "${sample}_sspace" \
        -T $SLURM_CPUS_PER_TASK

    # 7. Finalize
    sspace_result="${sample}_sspace.final.scaffolds.fasta"

    if [[ -f "$sspace_result" ]]; then
        echo "✅ SSPACE finished."
        cp "$sspace_result" "$final_output"
        rm "reads_R1.fq" "reads_R2.fq"
    else
        echo "❌ Error: SSPACE failed."
        exit 1
    fi

    echo "=== Finished $sample ==="
done