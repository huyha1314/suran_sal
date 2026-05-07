mkdir -p result/tree 
micromamba run -n base python /mnt/10T/huyha/precisiongene/suran_sal/script/python.find_tax.py \
  -i result/gtdbtk_assembly/classify/gtdbtk.bac120.classify.tree.1.tree \
  -t sam1 \
  -o result/tree/selected_taxa_sam1.txt \
  -n 20