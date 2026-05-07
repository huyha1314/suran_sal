#!/bin/bash
#SBATCH --job-name=megahit
#SBATCH --output=./log/megahit_%j.out
#SBATCH --error=./log/megahit_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=48

# Create necessary directories
mkdir -p log result/megahit

# Check if inputs exist before starting
# (This loop matches your previous upstream logic)
for i1 in result/fastp/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    
    # Define inputs (From the Clean Step)
    in1="result/k2/clean.${sample}_1.fq.gz"
    in2="result/k2/clean.${sample}_2.fq.gz"
    outdir="result/megahit/${sample}_assembly"

    # --- SAFETY CHECK 1: Ensure Input Files Exist ---
    # If the previous job failed for this sample, skip it to avoid crashing
    if [[ ! -f "$in1" || ! -f "$in2" ]]; then
        echo "Warning: Input files for $sample not found in result/k2/. Skipping."
        continue
    fi

    # --- SAFETY CHECK 2: Skip if Assembly Already Finished ---
    if [[ -f "$outdir/final.contigs.fa" ]]; then
        echo "Skipping $sample (Assembly already exists)"
        continue
    fi

    # --- SAFETY CHECK 3: Clean Partial Runs ---
    # MEGAHIT crashes if the output dir exists but isn't finished. 
    # If we are here, the assembly isn't finished, so we delete the partial folder.
    if [[ -d "$outdir" ]]; then
        echo "Removing partial run for $sample"
        rm -rf "$outdir"
    fi

    echo "Running MEGAHIT for sample: $sample"

    # Note: --memory is in bytes. 164G RAM ~ 1.7e11 bytes. 
    # Using 0.95 fraction of available RAM is safer than hardcoding bytes if you switch nodes.
    # Fixed: Moved &> to the very end.
    micromamba run -n megahit megahit \
        -1 "$in1" \
        -2 "$in2" \
        -o "$outdir" \
        --num-cpu-threads 48 \
        --memory 0.95 \
        --min-contig-len 500 \
        --k-list 21,33,55,77,99,127 &> result/megahit/${sample}.megahit.log

    echo "Finished sample: $sample"
done