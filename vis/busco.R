#!/usr/bin/env Rscript

# ==========================================
# 0. Setup & Command-Line Arguments
# ==========================================

# Auto-install and load optparse for CLI arguments
if (!require("optparse", quietly = TRUE)) {
  install.packages("optparse", repos = "http://cran.us.r-project.org")
}
suppressPackageStartupMessages(library(optparse))

# Define the arguments with detailed help text
option_list <- list(
  make_option(c("-i", "--input"), type = "character", default = NULL,
              help = "Path to the input JSON file (Required). \n\t\tImportant: This must be the specific JSON output from BUSCO \n\t\t(e.g., short_summary.specific.eurotiales_odb12.my_assembly.json).", 
              metavar = "FILE"),
              
  make_option(c("-o", "--output"), type = "character", default = "BUSCO_Summary",
              help = "Output file prefix or path without the file extension. \n\t\tIf a folder is specified and does not exist, it will be created. \n\t\t[default: %default]", 
              metavar = "PREFIX"),
              
  make_option(c("-f", "--format"), type = "character", default = "html",
              help = "Desired output format(s). Options are 'html', 'pdf', or 'html,pdf'. \n\t\thtml: Interactive Plotly graph. \n\t\tpdf: Static, high-resolution vector graphic. \n\t\t[default: %default]", 
              metavar = "FORMAT")
)

opt_parser <- OptionParser(
  usage = "Usage: %prog [options]\n\nDescription:\n  This script parses a BUSCO short summary JSON file and generates \n  a stacked bar plot of the completeness metrics.",
  option_list = option_list
)

opt <- parse_args(opt_parser)

# Check for required input
if (is.null(opt$input)) {
  print_help(opt_parser)
  stop("Error: --input argument is required.\n", call. = FALSE)
}

# Auto-install and load required packages quietly
required_packages <- c("jsonlite", "tidyverse", "plotly", "htmlwidgets")
for (pkg in required_packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    message(paste0("Installing '", pkg, "'..."))
    install.packages(pkg, repos = "http://cran.us.r-project.org")
    suppressPackageStartupMessages(library(pkg, character.only = TRUE))
  }
}

# ==========================================
# 1. Load Data
# ==========================================

if(!file.exists(opt$input)) {
  stop(paste("Error: Input file not found at:", opt$input))
}

message("Reading JSON file...")
data <- fromJSON(opt$input)
res <- data$results

# ==========================================
# 2. Prepare Data
# ==========================================

plot_data <- data.frame(
  Category = factor(c("Single-Copy", "Duplicated", "Fragmented", "Missing"),
                    levels = c("Missing", "Fragmented", "Duplicated", "Single-Copy")), # Stack order
  Count = c(res$`Single copy BUSCOs`, res$`Multi copy BUSCOs`, res$`Fragmented BUSCOs`, res$`Missing BUSCOs`),
  Percentage = c(res$`Single copy percentage`, res$`Multi copy percentage`, res$`Fragmented percentage`, res$`Missing percentage`)
)

# Official BUSCO Colors
busco_colors <- c(
  "Single-Copy" = "#56B4E9",  
  "Duplicated"  = "#0072B2",  
  "Fragmented"  = "#F0E442",  
  "Missing"     = "#D55E00"   
)

# ==========================================
# 3. Create Stacked Bar Plot
# ==========================================

p <- ggplot(plot_data, aes(x = "Assembly", y = Percentage, fill = Category)) +
  geom_bar(stat = "identity", width = 0.6) + 
  coord_flip() +
  scale_fill_manual(values = busco_colors) +
  theme_minimal() +
  labs(title = paste("BUSCO Assessment Results (n =", res$n_markers, ")"),
       subtitle = paste("Completeness:", res$`Complete percentage`, "%"),
       x = "", y = "% BUSCOs") +
  theme(
    legend.position = "bottom",
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    panel.grid.major.y = element_blank(),
    plot.title = element_text(face = "bold", size = 14)
  ) +
  geom_text(aes(label = ifelse(Percentage > 3, paste0(Percentage, "% (", Count, ")"), "")), 
            position = position_stack(vjust = 0.5), 
            size = 4, fontface = "bold", color = "black")

# ==========================================
# 4. Export Outputs
# ==========================================

# Ensure output directory exists if a path is included in the prefix
out_dir <- dirname(opt$output)
if (out_dir != "." && !dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE)
}

# Parse requested formats (handles spaces and capitals securely)
formats <- trimws(unlist(strsplit(tolower(opt$format), ",")))
message(paste("Exporting files with prefix:", opt$output))

if ("html" %in% formats) {
  html_path <- paste0(opt$output, ".html")
  p_interactive <- ggplotly(p, tooltip = c("y", "fill", "label")) %>%
    layout(legend = list(orientation = "h", x = 0.1, y = -0.1))
  saveWidget(p_interactive, file = html_path)
  message("  Saved HTML: ", html_path)
}

if ("pdf" %in% formats) {
  pdf_path <- paste0(opt$output, ".pdf")
  ggsave(pdf_path, plot = p, width = 10, height = 5, bg = "white")
  message("  Saved PDF:  ", pdf_path)
}

if (!("html" %in% formats) && !("pdf" %in% formats)) {
  warning("No valid format specified. Please use 'html', 'pdf', or 'html,pdf'.")
} else {
  message("Done!")
}