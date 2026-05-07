#!/bin/bash
#SBATCH --job-name=custom_tree
#SBATCH --output=log/tree_%j.out
#SBATCH --error=log/tree_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G

export GTDBTK_DATA_PATH="/mnt/12T/huyha/db/gtdbtk_r220_data/release226"

INPUT_LIST=result/tree/selected_taxa_sam1.txt
SAM1_FASTA=result/final_polished/sam1/sam1_final_polished.fasta
WORK_DIR="$PWD/result/tree"
THREADS=48

echo "=== 1. Preparing Working Directory ==="
# Removed rm -rf here so we don't delete previous successful steps!
mkdir -p $WORK_DIR/genomes
mkdir -p $WORK_DIR/gtdbtk_out

# Always ensure the local assembly is copied
cp $SAM1_FASTA $WORK_DIR/genomes/sam1.fasta

echo "=== 2. Cleaning NCBI Accessions ==="
if [ -s "$WORK_DIR/clean_accessions.txt" ]; then
    echo " -> Skipping: clean_accessions.txt already exists."
else
    # Remove 'sam1' and strip 'RS_' and 'GB_' prefixes
    grep -v "^sam1" $INPUT_LIST | sed -e 's/^RS_//' -e 's/^GB_//' > $WORK_DIR/clean_accessions.txt
fi

echo "=== 3. Downloading Reference Genomes ==="
if unzip -tq $WORK_DIR/ncbi_dataset.zip &> /dev/null; then
    echo " -> Skipping: Valid ncbi_dataset.zip already exists."
else
    MAX_RETRIES=5
    count=0
    download_success=false

    while [ $count -lt $MAX_RETRIES ]; do
        echo "Download attempt $((count+1)) of $MAX_RETRIES..."
        
        micromamba run -n base datasets download genome accession \
            --inputfile $WORK_DIR/clean_accessions.txt \
            --include genome \
            --filename $WORK_DIR/ncbi_dataset.zip
        
        if unzip -tq $WORK_DIR/ncbi_dataset.zip &> /dev/null; then
            echo "Download successful and zip archive is valid!"
            download_success=true
            break
        else
            echo "WARNING: Download failed or zip is corrupted. Retrying in 10 seconds..."
            rm -f $WORK_DIR/ncbi_dataset.zip
            sleep 10
            count=$((count+1))
        fi
    done

    if [ "$download_success" = false ]; then
        echo "FATAL ERROR: Failed to download valid genomes from NCBI after $MAX_RETRIES attempts."
        exit 1
    fi
fi

echo "=== 4. Extracting and Standardizing Genomes ==="
# Check if we already have reference genomes extracted (counting files starting with myref_)
if [ $(ls -1 $WORK_DIR/genomes/myref_*.fasta 2>/dev/null | wc -l) -gt 0 ]; then
    echo " -> Skipping: Reference genomes are already extracted in genomes/ folder."
else
    unzip -q $WORK_DIR/ncbi_dataset.zip -d $WORK_DIR/extracted
    while read acc; do
        fna_file=$(find $WORK_DIR/extracted/ncbi_dataset/data/$acc -name "*.fna" | head -n 1)
        if [[ ! -z "$fna_file" ]]; then
            cp "$fna_file" "$WORK_DIR/genomes/myref_${acc}.fasta"
        fi
    done < $WORK_DIR/clean_accessions.txt
fi

echo "=== 5. Extracting Marker Genes (GTDB-Tk) ==="
if [ -d "$WORK_DIR/gtdbtk_out/identify" ]; then
    echo " -> Skipping: GTDB-Tk identify directory already exists."
else
    micromamba run -n gtdbtk gtdbtk identify \
        --genome_dir $WORK_DIR/genomes \
        --out_dir $WORK_DIR/gtdbtk_out \
        --extension fasta \
        --force \
        --cpus $THREADS
fi

echo "=== 6. Aligning Marker Genes (GTDB-Tk) ==="
if [ -d "$WORK_DIR/gtdbtk_out/align" ]; then
    echo " -> Skipping: GTDB-Tk align directory already exists."
else
    micromamba run -n gtdbtk gtdbtk align \
        --identify_dir $WORK_DIR/gtdbtk_out \
        --out_dir $WORK_DIR/gtdbtk_out \
        --cpus $THREADS
fi

echo "=== 7. Building Tree (IQ-TREE) ==="
if [ -f "$WORK_DIR/sam1_custom_tree.treefile" ]; then
    echo " -> Skipping: IQ-TREE output already exists."
else
    micromamba run -n fungal_taxonomy iqtree \
        -s $WORK_DIR/gtdbtk_out/align/gtdbtk.bac120.user_msa.fasta.gz \
        -m TEST \
        -B 1000 \
        -T AUTO \
        --prefix $WORK_DIR/sam1_custom_tree
fi

echo "=== 8. Adding Species Names to the Tree ==="
if [ -f "$WORK_DIR/sam1_annotated_tree.treefile" ]; then
    echo " -> Skipping: Annotated tree already exists."
else
WORK_DIR="$PWD/result/tree"

echo "=== 8. Adding Species Names to the Tree ==="
if [ -f "$WORK_DIR/sam1_annotated_tree.treefile" ]; then
    echo " -> Skipping: Annotated tree already exists."
else
    # Save the raw JSON output directly, ignoring the broken dataformat tool
    micromamba run -n base datasets summary genome accession \
        --inputfile $WORK_DIR/clean_accessions.txt > $WORK_DIR/taxonomy_summary.json

    # Use Python to safely parse the JSON and rename the tree branches
    micromamba run -n base python3 -c '
import sys
import json

tree_path = sys.argv[1]
json_path = sys.argv[2]
out_path = sys.argv[3]

mapping = {}
try:
    with open(json_path, "r") as f:
        data = json.load(f)
        
        for report in data.get("reports", []):
            acc = report.get("accession")
            if not acc:
                continue
            
            # Catch both naming conventions NCBI uses just to be safe
            org_info = report.get("organism", {})
            org_name = org_info.get("organism_name") or org_info.get("organismName") or "Unknown_Species"
            
            # Clean up the organism name for Newick format
            clean_name = org_name.replace(" ", "_").replace("(", "").replace(")", "").replace(":", "").replace("/", "_")
            mapping[acc] = f"{clean_name}_{acc}"
            
except json.JSONDecodeError:
    print("WARNING: Could not parse NCBI JSON. Tree will remain unannotated.")
    sys.exit(0)

with open(tree_path, "r") as f:
    tree_text = f.read()

# Replace the plain accessions (including the myref_ tag) with the new descriptive names
for acc, new_name in mapping.items():
    tree_text = tree_text.replace(f"myref_{acc}", new_name)

with open(out_path, "w") as f:
    f.write(tree_text)
' $WORK_DIR/sam1_custom_tree.treefile $WORK_DIR/taxonomy_summary.json $WORK_DIR/sam1_annotated_tree.treefile
fi

echo "=== Pipeline Complete! ==="
echo "Your fully annotated tree is here: $WORK_DIR/sam1_annotated_tree.treefile"