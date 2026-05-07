#!/usr/bin/env Rscript

# Load required libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(DT)
  library(plotly)
  library(htmlwidgets)
})

# Define base directory (assuming you run this inside the result folder)
base_dir <- "/mnt/10T/huyha/precisiongene/suran_sal/result"
setwd(base_dir)

# Create output directories for the HTML files
dir.create("Table_Reports", showWarnings = FALSE)
dir.create("BUSCO_Results_scaffold", showWarnings = FALSE)
dir.create("Annotated_Genomic_Report", showWarnings = FALSE)

cat("Starting R visualizations...\n")

# ==========================================
# 1. CheckM Assembly Stats (Interactive Table)
# ==========================================
if(file.exists("checkm_assembly/checkm_summary.tsv")) {
  checkm_data <- read_tsv("checkm_assembly/checkm_summary.tsv", show_col_types = FALSE)
  
  checkm_tbl <- datatable(checkm_data, 
                          options = list(pageLength = 10, scrollX = TRUE),
                          class = 'cell-border stripe',
                          rownames = FALSE)
  
  saveWidget(checkm_tbl, file = "Table_Reports/Assembly_Stats.html", selfcontained = TRUE)
  cat("Generated CheckM table.\n")
}

# ==========================================
# 2. GTDB-Tk Taxonomy (Interactive Table)
# ==========================================
if(file.exists("gtdbtk_assembly/gtdbtk.summary.tsv")) {
  gtdb_data <- read_tsv("gtdbtk_assembly/gtdbtk.summary.tsv", show_col_types = FALSE) %>%
    select(user_genome, classification, fastani_ani, closest_placement_reference)
  
  gtdb_tbl <- datatable(gtdb_data, options = list(scrollX = TRUE), rownames = FALSE)
  saveWidget(gtdb_tbl, file = "Table_Reports/Taxonomy_Stats.html", selfcontained = TRUE)
  cat("Generated GTDB-Tk table.\n")
}

# ==========================================
# 3. BUSCO Results (Plotly Bar Chart)
# ==========================================
# (Replace the counts below with the actual numbers from your short_summary.txt)
busco_df <- data.frame(
  Category = factor(c("Complete (Single)", "Complete (Duplicated)", "Fragmented", "Missing"),
                    levels = c("Missing", "Fragmented", "Complete (Duplicated)", "Complete (Single)")),
  Count = c(4200, 50, 15, 100) 
)

busco_plot <- plot_ly(busco_df, x = ~Count, y = ~"BUSCO", type = 'bar', 
                      color = ~Category, orientation = 'h',
                      colors = c("#e74c3c", "#e67e22", "#f1c40f", "#3498db")) %>%
  layout(barmode = 'stack', 
         title = "BUSCO Assembly Completeness",
         xaxis = list(title = "Number of BUSCOs"),
         yaxis = list(title = ""))

saveWidget(busco_plot, file = "BUSCO_Results_scaffold/BUSCO_Summary.html", selfcontained = TRUE)
cat("Generated BUSCO plot.\n")

# ==========================================
# 4. EggNOG COG Plot & Table (Plotly & DT)
# ==========================================
eggnog_file <- list.files("eggnog", pattern = "emapper.annotations$", full.names = TRUE)[1]

if(!is.na(eggnog_file) && file.exists(eggnog_file)) {
  # Read EggNOG, skipping the ## comment lines
# Read EggNOG, skipping the ## comment lines, and rename the first column
  eggnog_data <- read_tsv(eggnog_file, comment = "##", show_col_types = FALSE) %>%
    rename(query = `#query`)  
  # A. COG Bar Chart
  cog_counts <- eggnog_data %>%
    filter(!is.na(COG_category)) %>%
    separate_rows(COG_category, sep = "") %>%
    filter(COG_category != "") %>%
    count(COG_category, name = "Count") %>%
    arrange(desc(Count))
  
  cog_plot <- plot_ly(cog_counts, x = ~reorder(COG_category, -Count), y = ~Count, 
                      type = 'bar', marker = list(color = '#2ecc71')) %>%
    layout(title = "COG Category Distribution",
           xaxis = list(title = "COG Category"),
           yaxis = list(title = "Number of Genes"))
  
  saveWidget(cog_plot, file = "Annotated_Genomic_Report/02_COG_Grouped.html", selfcontained = TRUE)
  
  # B. Full Interactive Table
  eggnog_tbl <- datatable(eggnog_data %>% select(query, seed_ortholog, evalue, Preferred_name, Description), 
                          filter = 'top', options = list(pageLength = 10, scrollX = TRUE),
                          rownames = FALSE)
  
  saveWidget(eggnog_tbl, file = "Annotated_Genomic_Report/00_Overview.html", selfcontained = TRUE)
  cat("Generated EggNOG plots and tables.\n")
}

cat("All visualizations successfully saved as HTML files!\n")