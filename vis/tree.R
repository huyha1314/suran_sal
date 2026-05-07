#!/usr/bin/env Rscript

# Load required libraries silently
suppressPackageStartupMessages({
  library(optparse)
  library(ape)
  library(phytools)
  library(ggtree)
  library(ggplot2)
})

# Setup command-line arguments
option_list = list(
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="Input Newick tree file", metavar="FILE"),
  make_option(c("-o", "--output"), type="character", default="final_tree_plot",
              help="Output file prefix (without extension)", metavar="STRING"),
  make_option(c("-r", "--root"), type="character", default=NULL,
              help="Exact name of the outgroup tip to root the tree.", metavar="STRING")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$input)){
  print_help(opt_parser)
  stop("FATAL ERROR: Input tree file must be supplied (-i).", call.=FALSE)
}

cat("=== 1. Loading Tree ===\n")
tree <- read.tree(opt$input)

cat("=== 2. Rooting Tree ===\n")
if (!is.null(opt$root)) {
    if (opt$root %in% tree$tip.label) {
        cat("Rooting tree using outgroup:", opt$root, "\n")
        tree <- root(tree, outgroup = opt$root, resolve.root = TRUE)
    } else {
        stop(paste("FATAL ERROR: Outgroup '", opt$root, "' not found! Check spelling.", sep=""))
    }
} else {
    cat("No outgroup provided. Performing midpoint rooting...\n")
    tree <- midpoint.root(tree)
}

cat("=== 3. Generating Plot ===\n")
# Calculate max distance to dynamically extend x-axis
max_dist <- max(node.depth.edgelength(tree))

# Build the beautiful static tree
p <- ggtree(tree, size=0.8) +
  geom_tiplab(size=4, align=TRUE, linesize=0.5, offset=0.005) +
  geom_nodelab(size=3.5, hjust=-0.2, vjust=-0.5, color="navyblue") +
  theme_tree2() + 
  # INCREASED MULTIPLIER: Changed from 1.5 to 3.5 to fit long NCBI names
  xlim(0, max_dist * 3.5) 

# Highlight 'sam1' in red
if ("sam1" %in% tree$tip.label) {
    cat("Target 'sam1' detected! Highlighting branch in red...\n")
    sam_node <- which(tree$tip.label == "sam1")
    p <- p + geom_tippoint(aes(subset=(node == sam_node)), size=5, color="red")
}

cat("=== 4. Saving Outputs ===\n")

# Save as Publication-Ready PDF
pdf_out <- paste0(opt$output, ".pdf")
# INCREASED WIDTH: Changed width from 12 to 16 for a wider landscape canvas
ggsave(pdf_out, plot = p, width = 16, height = 8, units = "in", dpi = 300)
cat(" -> Saved PDF:", pdf_out, "\n")

# Save as High-Res PNG 
png_out <- paste0(opt$output, ".png")
# INCREASED WIDTH: Match the PDF width here too
ggsave(png_out, plot = p, width = 16, height = 8, units = "in", dpi = 300, bg = "white")
cat(" -> Saved PNG:", png_out, "\n")