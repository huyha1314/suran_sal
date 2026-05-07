#!/bin/bash

# ==============================================================================
# Master Script: Genomic Visualization Pipeline
# Purpose: Runs BUSCO, EggNOG/KEGG, Bakta, Assembly Taxonomy, and Phylogeny.
#          Archives all input data into the report folder.
# ==============================================================================

# --- 1. GLOBAL CONFIGURATION (FILL IN YOUR PATHS) ---

# 1. BUSCO Inputs
BUSCO_JSON="/mnt/10T/huyha/precisiongene/suran_sal/result/busco_results/sam1_busco/short_summary.specific.enterobacteriaceae_odb12.sam1_busco.json"

# 2. EggNOG Inputs
EGGNOG_ANNOT="/mnt/10T/huyha/precisiongene/suran_sal/result/eggnog/sam1.emapper.annotations"

# 3. Bakta Inputs
BAKTA_TSV="/mnt/10T/huyha/precisiongene/suran_sal/result/annotation/sam1/sam1.tsv"
BAKTA_TXT="/mnt/10T/huyha/precisiongene/suran_sal/result/annotation/sam1/sam1.txt"

# 4. Assembly Taxonomy Inputs
CHECKM_TSV="/mnt/10T/huyha/precisiongene/suran_sal/result/checkm_assembly/checkm_summary.txt"
GTDB_TSV="/mnt/10T/huyha/precisiongene/suran_sal/result/gtdbtk_assembly/gtdbtk.bac120.summary.tsv"
GTDB_TREE="/mnt/10T/huyha/precisiongene/suran_sal/result/gtdbtk_assembly/classify/gtdbtk.bac120.classify.tree.1.tree"

# 5. Phylogeny Inputs
ANNOTATED_TREE="/mnt/10T/huyha/precisiongene/suran_sal/result/tree/sam1_annotated_tree.treefile"

# --- 2. DIRECTORY SETUP ---
SCRIPT_DIR="/mnt/10T/huyha/precisiongene/suran_sal/vis"
BASE_OUTDIR="/mnt/10T/huyha/precisiongene/suran_sal/rp"
DATA_OUTDIR="$BASE_OUTDIR/data"
QC="/mnt/10T/huyha/precisiongene/suran_sal/result/multiqc/sam1.report.html"
# Clean previous run (optional, uncomment to use)
# rm -rf "$BASE_OUTDIR"

# Create specific output directories
mkdir -p "$BASE_OUTDIR/00_QC"
mkdir -p "$BASE_OUTDIR/01_BUSCO"
mkdir -p "$BASE_OUTDIR/02_Functional"
mkdir -p "$BASE_OUTDIR/03_Bakta"
mkdir -p "$BASE_OUTDIR/04_Taxonomy"
mkdir -p "$BASE_OUTDIR/05_Phylogeny"
mkdir -p "$DATA_OUTDIR" 
echo "======================================================="
echo "Starting Visualization Pipeline..."
echo "Output Directory: $BASE_OUTDIR"
echo "======================================================="

# --- 3. COPY DATA FOR ARCHIVE ---
echo "Copying input data to $DATA_OUTDIR for archiving..."

cp -p "$BUSCO_JSON" "$DATA_OUTDIR/"
cp -p "$EGGNOG_ANNOT" "$DATA_OUTDIR/"
cp -p "$BAKTA_TSV" "$DATA_OUTDIR/"
cp -p "$BAKTA_TXT" "$DATA_OUTDIR/"
cp -p "$CHECKM_TSV" "$DATA_OUTDIR/"
cp -p "$GTDB_TSV" "$DATA_OUTDIR/"
cp -p "$GTDB_TREE" "$DATA_OUTDIR/"
cp -p "$ANNOTATED_TREE" "$DATA_OUTDIR/"
cp -p "$QC" "$BASE_OUTDIR/00_QC"
echo "[SUCCESS] Data copied."
echo "-------------------------------------------------------"

# Function to check if a command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo "[SUCCESS] $1 finished."
        echo "-------------------------------------------------------"
    else
        echo "[ERROR] $1 failed. Pipeline stopped."
        exit 1
    fi
}

# --- 4. EXECUTION ---

# A. Run BUSCO Plot
echo "Running BUSCO visualization..."
micromamba run -n rp Rscript "$SCRIPT_DIR/busco.R" \
    --input "$BUSCO_JSON" \
    --output "$BASE_OUTDIR/01_BUSCO/BUSCO_Report" \
    --format "html,pdf"
check_status "BUSCO Plot"

# B. Run EggNOG & KEGG Report
echo "Running EggNOG/KEGG visualization..."
micromamba run -n rp Rscript "$SCRIPT_DIR/eggnog.R" \
    --eggnog "$EGGNOG_ANNOT" \
    --outdir "$BASE_OUTDIR/02_Functional"
check_status "EggNOG/KEGG Report"

# C. Run Bakta Report
echo "Running Bakta visualization..."
micromamba run -n rp Rscript "$SCRIPT_DIR/batka.R" \
    --input "$BAKTA_TSV" \
    --summary "$BAKTA_TXT" \
    --output "$BASE_OUTDIR/03_Bakta/bakta_report.html"
check_status "Bakta Plot"

# D. Run Assembly Taxonomy Report
echo "Running Assembly Taxonomy visualization..."
micromamba run -n rp Rscript "$SCRIPT_DIR/assembly_tax.R" \
    --checkm "$CHECKM_TSV" \
    --gtdbtk "$GTDB_TSV" \
    --out "$BASE_OUTDIR/04_Taxonomy/taxonomy_report"
check_status "Taxonomy Plot"

# E. Run Phylogenetic Tree Visualization
echo "Running Phylogenetic Tree visualization..."
micromamba run -n rp Rscript "$SCRIPT_DIR/tree.R" \
    -i "$ANNOTATED_TREE" \
    -o "$BASE_OUTDIR/05_Phylogeny/sam1_final_publication_tree"
check_status "Phylogenetic Tree Plot"


echo "======================================================="
echo "Pipeline Complete! All results and raw data are in $BASE_OUTDIR"
echo "======================================================="