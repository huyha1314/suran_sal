#!/usr/bin/env Rscript

# Load optparse first to handle arguments cleanly
if (!requireNamespace("optparse", quietly = TRUE)) install.packages("optparse", repos = "http://cran.us.r-project.org")
library(optparse)

# Define command-line arguments (Tree removed)
option_list = list(
  make_option(c("-c", "--checkm"), type="character", default=NULL, 
              help="Path to CheckM statistics file", metavar="FILE"),
  make_option(c("-g", "--gtdbtk"), type="character", default=NULL, 
              help="Path to GTDB-Tk classification summary file (tab-separated)", metavar="FILE"),
  make_option(c("-o", "--out"), type="character", default="assembly_report", 
              help="Prefix for output files (PDF and HTML) [default: %default]", metavar="PREFIX")
)

# Parse arguments
opt_parser = OptionParser(usage = "Usage: %prog -c checkm.txt -g gtdbtk.tsv -o my_report", 
                          option_list=option_list)
opt = parse_args(opt_parser)

# Check for required arguments
if (is.null(opt$checkm) | is.null(opt$gtdbtk)){
  print_help(opt_parser)
  stop("Error: You must provide the CheckM file (-c) and GTDB-Tk file (-g).", call.=FALSE)
}

# Ensure required plotting packages are installed
required_pkgs <- c("ggplot2", "ggpubr", "DT", "htmlwidgets")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, repos = "http://cran.us.r-project.org")
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggpubr)
  library(DT)
  library(htmlwidgets)
})

cat("Loading and cleaning data...\n")

# --- FIX: Custom CheckM Terminal Output Parser ---
checkm_raw <- readLines(opt$checkm)

# 1. Remove log lines (starts with [)
checkm_clean <- checkm_raw[!grepl("^\\[", checkm_raw)]
# 2. Remove dashed lines
checkm_clean <- checkm_clean[!grepl("^-+$", trimws(checkm_clean))]
# 3. Trim whitespace and drop empty lines
checkm_clean <- trimws(checkm_clean)
checkm_clean <- checkm_clean[checkm_clean != ""]

# 4. Convert 2 or more spaces into a proper Tab (\t)
# This preserves single spaces in headers like "Marker lineage" but splits the columns correctly!
checkm_clean <- gsub(" {2,}", "\t", checkm_clean)

# Read the newly formatted string as a dataframe
checkm_df <- read.delim(text = paste(checkm_clean, collapse="\n"), sep="\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)

# Read GTDB-Tk normally (it is already a standard TSV)
gtdbtk_df <- read.delim(opt$gtdbtk, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)

# Set output filenames based on prefix
out_pdf <- paste0(opt$out, ".pdf")
out_checkm_html <- paste0(opt$out, "_checkm.html")
out_gtdbtk_html <- paste0(opt$out, "_gtdbtk.html")

cat("Generating PDF report:", out_pdf, "...\n")
# Reduced height since the tree plot is removed
pdf(out_pdf, width = 14, height = 8)

# Create ggpubr tables
checkm_plot <- ggtexttable(checkm_df, rows = NULL, 
                           theme = ttheme("mBlue", base_size = 8, padding = unit(c(4, 4), "mm"))) %>%
  tab_add_title(text = "CheckM Assembly Statistics", face = "bold", size = 14)

gtdbtk_plot <- ggtexttable(gtdbtk_df, rows = NULL, 
                           theme = ttheme("mOrange", base_size = 8, padding = unit(c(4, 4), "mm"))) %>%
  tab_add_title(text = "GTDB-Tk Taxonomic Identification", face = "bold", size = 14)

# Arrange tables
print(ggarrange(checkm_plot, gtdbtk_plot, ncol = 1, nrow = 2, heights = c(1, 1)))
dev.off()

cat("Generating Interactive HTML tables...\n")
html_checkm <- datatable(checkm_df, options = list(pageLength = 15, scrollX = TRUE), 
                         caption = htmltools::tags$caption(style = 'font-weight: bold; font-size: 1.5em;', 'CheckM Statistics'))
html_gtdbtk <- datatable(gtdbtk_df, options = list(pageLength = 10, scrollX = TRUE), 
                         caption = htmltools::tags$caption(style = 'font-weight: bold; font-size: 1.5em;', 'GTDB-Tk Identity'))

saveWidget(html_checkm, out_checkm_html, selfcontained = TRUE)
saveWidget(html_gtdbtk, out_gtdbtk_html, selfcontained = TRUE)

cat("Success! All files saved with prefix:", opt$out, "\n")