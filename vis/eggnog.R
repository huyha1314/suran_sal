#!/usr/bin/env Rscript

# ==========================================
# 0. Setup & Command-Line Arguments
# ==========================================

suppressPackageStartupMessages({
  library(optparse)
  library(tidyverse)
  library(plotly)
  library(htmlwidgets)
  library(svglite)
  library(viridis)
  library(KEGGREST)
  library(DT)
})

# Define the CLI arguments
option_list <- list(
  make_option(c("-e", "--eggnog"), type = "character", default = NULL,
              help = "Path to the eggnog .annotations file (Required)", metavar = "FILE"),
  make_option(c("-o", "--outdir"), type = "character", default = "EggNOG_Genomic_Report",
              help = "Output directory for the generated plots and tables [default: %default]", metavar = "DIR")
)

opt_parser <- OptionParser(
  usage = "Usage: %prog -e <eggnog_file> [options]\n\nDescription:\n  Parses eggnog.emapper.annotations to generate COG and KEGG pathway reports.",
  option_list = option_list
)

opt <- parse_args(opt_parser)

# Validation Check
if (is.null(opt$eggnog)) {
  print_help(opt_parser)
  stop("Error: The --eggnog input file is required.\n", call. = FALSE)
}

if (!dir.exists(opt$outdir)) {
  message("Creating output directory: ", opt$outdir)
  dir.create(opt$outdir, recursive = TRUE)
}

# ==========================================
# 1. Fetch Complete KEGG Database
# ==========================================
message("Fetching latest Pathway definitions from KEGG...")

tryCatch({
  kegg_list <- keggList("pathway") 
  kegg_db <- data.frame(ID = names(kegg_list), Description = unname(kegg_list)) %>%
    mutate(ID = str_remove(ID, "path:"))
  message(paste("Successfully fetched", nrow(kegg_db), "pathways."))
}, error = function(e) {
  message("WARNING: Could not connect to KEGG. Using raw KEGG IDs only.")
  kegg_db <- data.frame(ID = character(), Description = character())
})

# ==========================================
# 2. DEFINITIONS (Dictionaries)
# ==========================================

cog_map <- tibble(
  Code = c("J", "A", "K", "L", "B", "D", "Y", "V", "T", "M", "N", "Z", "W", "U", "O", "C", "G", "E", "F", "H", "I", "P", "Q", "R", "S"),
  Function = c("Translation", "RNA processing", "Transcription", "Replication", "Chromatin",
               "Cell cycle", "Nuclear structure", "Defense", "Signal transduction", "Cell wall/membrane",
               "Cell motility", "Cytoskeleton", "Extracellular", "Intracellular trafficking", "Posttranslational mod",
               "Energy production", "Carbohydrate metabolism", "Amino acid", "Nucleotide", "Coenzyme",
               "Lipid", "Inorganic ion", "Secondary metabolites", "General prediction", "Unknown"),
  Class = c(rep("Information Storage", 5), rep("Cellular Processes", 10), rep("Metabolism", 8), rep("Poorly Characterized", 2))
)

# ==========================================
# 3. Data Loading & Processing
# ==========================================

if(!file.exists(opt$eggnog)) stop("Error: EggNOG file not found at ", opt$eggnog)

message("Processing EggNOG annotations...")
df_eggnog <- read.delim(opt$eggnog, sep = "\t", comment.char = "#", header = FALSE, stringsAsFactors = FALSE)
colnames(df_eggnog) <- c("query", "seed", "evalue", "score", "ogs", "max_annot", "COG_cat", "Desc", "Name", "GOs", "EC", "KEGG_ko", "KEGG_Pathway", "Module", "Reaction", "rclass", "BRITE", "TC", "CAZy", "BiGG", "PFAMs")

# --- Process COG ---
cog_stats <- df_eggnog %>%
  select(query, COG_cat) %>%
  filter(COG_cat != "" & !is.na(COG_cat)) %>%
  mutate(Code = str_split(COG_cat, "")) %>%
  unnest(Code) %>%
  inner_join(cog_map, by = "Code") %>%
  count(Class, Function, sort = TRUE)

# --- Process KEGG ---
all_kegg <- df_eggnog %>%
  select(query, KEGG_Pathway) %>%
  filter(!is.na(KEGG_Pathway) & KEGG_Pathway != "" & KEGG_Pathway != "-") %>%
  separate_rows(KEGG_Pathway, sep = ",") %>%
  mutate(Clean_ID = str_replace(str_trim(KEGG_Pathway), "ko", "map")) %>%
  left_join(kegg_db, by = c("Clean_ID" = "ID")) %>%
  mutate(Final_Name = ifelse(is.na(Description), Clean_ID, Description)) %>%
  count(Final_Name, Clean_ID, sort = TRUE) %>%
  rename(Count = n, Pathway_Name = Final_Name, Pathway_ID = Clean_ID)

# ==========================================
# 4. Plotting & Export
# ==========================================

message("Generating reports and visualizations...")

# --- A. Export KEGG Tables ---
write.csv(all_kegg, file.path(opt$outdir, "All_KEGG_Pathways.csv"), row.names = FALSE)
saveWidget(datatable(all_kegg), file = file.path(opt$outdir, "All_KEGG_Table.html"))

# --- B. COG Visualization ---
p_cog <- ggplot(cog_stats, aes(x = reorder(Function, n), y = n, fill = Class)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = n), hjust = -0.1, size = 3) +
  coord_flip() +
  facet_grid(Class ~ ., scales = "free_y", space = "free") +
  scale_fill_viridis(discrete = TRUE, option = "D") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.2))) +
  theme_bw() +
  labs(title = "COG Categories", x = "", y = "Count") +
  theme(legend.position = "none", strip.text = element_text(face="bold"))

ggsave(file.path(opt$outdir, "01_COG_Grouped.png"), p_cog, width = 12, height = 8, dpi = 300, bg="white")
ggsave(file.path(opt$outdir, "01_COG_Grouped.pdf"), p_cog, width = 12, height = 8, bg="white")
tryCatch({
  saveWidget(ggplotly(p_cog, tooltip = c("y", "fill", "label")), file = file.path(opt$outdir, "01_COG_Grouped.html"))
}, error = function(e) { message("  [Skipping HTML] for COG plot") })


# --- C. KEGG Top 50 Visualization ---
top_50 <- all_kegg %>% slice_max(Count, n = 50)
top_50$Label <- as.character(top_50$Count)

# Static Plot (with manual shadow trick)
p_kegg_static <- ggplot(top_50, aes(x = reorder(Pathway_Name, Count), y = Count, fill = Count)) +
  geom_bar(stat = "identity") +
  coord_flip() +
  scale_fill_viridis(option = "turbo") +
  theme_minimal() +
  labs(title = "Top 50 KEGG Pathways", x = "", y = "Gene Count") +
  theme(legend.position = "none", axis.text.y = element_text(size = 8)) +
  geom_text(aes(label = Label), position = position_stack(vjust = 0.5), color = "black", fontface = "bold", size = 3.5) +
  geom_text(aes(label = Label), position = position_stack(vjust = 0.5), color = "white", fontface = "bold", size = 3.5, alpha = 0.9)

ggsave(file.path(opt$outdir, "02_Top50_KEGG_Plot.pdf"), p_kegg_static, width = 10, height = 12, bg="white")
ggsave(file.path(opt$outdir, "02_Top50_KEGG_Plot.png"), p_kegg_static, width = 10, height = 12, dpi=300, bg="white")

# Interactive Plot (Clean text for Plotly)
p_kegg_int <- ggplot(top_50, aes(x = reorder(Pathway_Name, Count), y = Count, fill = Count,
                                 text = paste("Pathway:", Pathway_Name, "\nCount:", Count))) +
  geom_bar(stat = "identity") +
  coord_flip() +
  scale_fill_viridis(option = "turbo") +
  theme_minimal() +
  labs(title = "Top 50 KEGG Pathways", x = "", y = "Gene Count") +
  theme(legend.position = "none", axis.text.y = element_text(size = 8)) +
  geom_text(aes(label = Label), position = position_stack(vjust = 0.5), color = "white", size = 3)

tryCatch({
  interactive_plot <- ggplotly(p_kegg_int, tooltip = "text") %>% layout(height = 1200)
  saveWidget(interactive_plot, file = file.path(opt$outdir, "02_Top50_KEGG_Plot_Interactive.html"))
}, error = function(e) { message("  [Skipping HTML] for KEGG plot") })

message(paste("\nDone! All reports successfully saved to:", opt$outdir))