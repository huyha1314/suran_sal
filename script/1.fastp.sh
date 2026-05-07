#!/bin/bash
#SBATCH --job-name=fastp
#SBATCH --output=./log/fastp.%j.out
#SBATCH --error=./log/fastp.%j.err
#SBATCH --ntasks=1           
#SBATCH --mem=124G           
#SBATCH --cpus-per-task=48   

# --- Configuration ---
# 48 CPUs Total / 16 threads per fastp = 3 parallel jobs
PARALLEL_JOBS=3
THREADS_PER_JOB=16
CMD_FILE="fastp.txt"

# Create directories (Added multiqc to ensure report generation works)
mkdir -p log result/fastp result/multiqc

# Clear the command file
> "$CMD_FILE"

echo "Preparing commands..."

# Loop over forward reads
for R1 in data/*_1.fq.gz; do
    # Define reverse pair
    R2="${R1/_1.fq.gz/_2.fq.gz}"

    # Check if pair exists
    if [[ ! -f "$R2" ]]; then
        echo "WARNING: Pair not found for $R1. Skipping."
        continue
    fi

    # Extract sample name (splitting by hyphen as requested)
    filename=$(basename "$R1")
    sample=$(echo "$filename" | cut -d "_" -f1)

    # Define Output Filenames
    OUT_R1="result/fastp/trim.${sample}_1.fq.gz"
    OUT_R2="result/fastp/trim.${sample}_2.fq.gz"
    REPORT_HTML="result/multiqc/${sample}.report.html"
    REPORT_JSON="result/multiqc/${sample}.report.json"

    # --- CHECK: If output exists and is not empty, skip ---
    if [[ -s "$OUT_R1" && -s "$OUT_R2" ]]; then
        echo "SKIPPING: $sample (Files already exist)"
    else
        # Add command to file
        # Note: Added -w to threads to avoid worker overload if hyperthreading
        echo "micromamba run -n quantify fastp \
            -i \"$R1\" -I \"$R2\" \
            -o \"$OUT_R1\" -O \"$OUT_R2\" \
            --trim_front1 8 --trim_front2 8 \
            --length_required 50 \
            --qualified_quality_phred 25 \
            --thread $THREADS_PER_JOB \
            --html \"$REPORT_HTML\" \
            --json \"$REPORT_JSON\"" >> "$CMD_FILE"
    fi
done

# Run commands if the file is not empty
if [[ -s "$CMD_FILE" ]]; then
    # count lines to show how many jobs are running
    job_count=$(wc -l < "$CMD_FILE")
    echo "Running $job_count jobs with $PARALLEL_JOBS parallel processes..."
    
    cat "$CMD_FILE" | parallel -j "$PARALLEL_JOBS"
else
    echo "All files already processed. No jobs to run."
fi