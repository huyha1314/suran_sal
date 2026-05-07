#!/usr/bin/env Rscript

# 1. Check for required packages and install/load
packages <- c("optparse", "ggplot2", "plotly", "dplyr", "readr", "htmlwidgets", "viridis", "DT", "htmltools")
invisible(lapply(packages, function(pkg) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    stop(paste("Package", pkg, "is required. Please install it in R: install.packages('", pkg, "')"))
  }
}))

# 2. DEFINE TOOL INTERFACE (Arguments)
option_list <- list(
  make_option(c("-i", "--input"), type="character", default=NULL, 
              help="Path to Bakta annotation .tsv file", metavar="FILE"),
  make_option(c("-s", "--summary"), type="character", default=NULL, 
              help="Path to Bakta summary .txt file", metavar="FILE"),
  make_option(c("-o", "--output"), type="character", default="bakta_report.html", 
              help="Output HTML file name [default= %default]", metavar="FILE"),
  make_option(c("-c", "--contig"), type="character", default=NULL, 
              help="Filter for a specific contig ID to process only that contig", metavar="STR")
)

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

if (is.null(opt$input)) {
  print_help(opt_parser)
  stop("Input TSV file is required (-i).", call.=FALSE)
}

# 3. FORMAT FUNCTION: Process Bakta TSV Data
process_bakta_tsv <- function(file_path) {
  message("Reading TSV annotation data...")
  data <- read_delim(
    file_path, delim = "\t", comment = "#",
    col_names = c("Seq_Id", "Type", "Start", "Stop", "Strand", "Locus", "Gene", "Product", "DbXrefs"),
    show_col_types = FALSE
  )
  
  data <- data %>%
    filter(Type == "cds") %>%
    mutate(
      Gene = ifelse(is.na(Gene) | Gene == "", "hypothetical", Gene),
      Direction = ifelse(Strand == "+", 1, -1),
      Midpoint = (Start + Stop) / 2,
      Tooltip = paste0(
        "<b>Gene:</b> ", Gene, "<br>",
        "<b>Product:</b> ", Product, "<br>",
        "<b>Locus:</b> ", Locus, "<br>",
        "<b>Range:</b> ", Start, "-", Stop, " (", Strand, ")"
      )
    )
  return(data)
}

# 4. FORMAT FUNCTION: Process Bakta Summary TXT Data
process_bakta_summary <- function(file_path) {
  message("Reading summary TXT data...")
  lines <- readLines(file_path)
  lines <- lines[trimws(lines) != ""] 
  
  category <- "General"
  results <- data.frame(Category=character(), Feature=character(), Value=character(), stringsAsFactors=FALSE)
  
  for (line in lines) {
    if (grepl(":$", trimws(line))) {
      category <- gsub(":$", "", trimws(line))
    } else if (grepl(":", line)) {
      parts <- strsplit(line, ":")[[1]]
      feature <- trimws(parts[1])
      value <- trimws(paste(parts[-1], collapse=":"))
      results <- rbind(results, data.frame(Category=category, Feature=feature, Value=value, stringsAsFactors=FALSE))
    }
  }
  return(results)
}

# 5. VISUALIZE FUNCTION: Create UI with Dropdown and Individual Contig Maps
create_map_ui <- function(df, contig_name) {
  
  # If user provided a specific contig via the CLI -c flag, just render that one.
  if (!is.null(contig_name)) {
    df <- df %>% filter(Seq_Id == contig_name)
    if (nrow(df) == 0) stop("Contig ID not found in data.")
    contigs <- unique(df$Seq_Id)
  } else {
    contigs <- unique(df$Seq_Id)
  }

  # 1. Create the Dropdown HTML Element
  dropdown <- tags$div(
    style = "margin-bottom: 15px; padding: 10px; background-color: #f8f9fa; border-radius: 5px;",
    tags$label(style = "font-family: Arial; font-weight: bold; margin-right: 10px;", "Select Contig Map:"),
    tags$select(
      id = "contig_selector",
      style = "padding: 6px 12px; font-size: 14px; border-radius: 4px; border: 1px solid #ccc; cursor: pointer;",
      onchange = "showContigPlot(this.value)",
      lapply(seq_along(contigs), function(i) tags$option(value = i, contigs[i]))
    )
  )

  # 2. Javascript to handle the switching of plots without reloading the page
  js_script <- tags$script(HTML("
    function showContigPlot(index) {
      var plots = document.getElementsByClassName('contig-plot-container');
      for(var i=0; i < plots.length; i++) {
        plots[i].style.display = 'none';
      }
      var activePlot = document.getElementById('plot_container_' + index);
      if(activePlot) {
        activePlot.style.display = 'block';
        window.dispatchEvent(new Event('resize')); // Forces Plotly to scale correctly
      }
    }
  "))

  # 3. Generate a separate Plotly object for each contig
  message("Generating map widgets for contigs...")
  plot_divs <- lapply(seq_along(contigs), function(i) {
    c_name <- contigs[i]
    c_df <- df %>% filter(Seq_Id == c_name)
    
    p <- ggplot(c_df, aes(xmin = Start, xmax = Stop, ymin = -0.5, ymax = 0.5, fill = Gene, text = Tooltip)) +
      geom_rect(color = "black", size = 0.1, alpha = 0.8) +
      scale_fill_viridis_d(option = "viridis") +
      theme_minimal() + 
      labs(title = paste("Contig:", c_name), x = "Genomic Position (bp)", y = "") +
      theme(
        axis.text.y = element_blank(), axis.ticks.y = element_blank(),
        panel.grid.major.y = element_blank(), legend.position = "none"
      )
    
    p_widget <- ggplotly(p, tooltip = "text") %>% layout(hoverlabel = list(bgcolor = "white"))
    
    # Wrap each plot in a div (only the first one is visible by default)
    tags$div(
      id = paste0("plot_container_", i),
      class = "contig-plot-container",
      style = if(i == 1) "display: block;" else "display: none;",
      p_widget
    )
  })

  # Return the combined UI components (Dropdown + JS + Plots)
  # If only 1 contig exists, hide the dropdown.
  if (length(contigs) == 1) {
    return(tagList(plot_divs))
  } else {
    return(tagList(dropdown, js_script, plot_divs))
  }
}

# --- EXECUTION FLOW ---

# Load TSV Data
bakta_df <- process_bakta_tsv(opt$input)

# Prepare Dashboard Elements
dashboard_elements <- tagList(
  tags$h2(style = "font-family: Arial, sans-serif; color: #2C3E50;", "Bakta Annotation Dashboard"),
  tags$hr()
)

# Process and Add Summary Tables (if provided)
if (!is.null(opt$summary)) {
  summary_df <- process_bakta_summary(opt$summary)
  
  summary_layout <- tags$div(style = "display: flex; gap: 40px; margin-bottom: 20px;")
  
  seq_df <- summary_df %>% filter(Category == "Sequence(s)") %>% select(Feature, Value)
  if(nrow(seq_df) > 0) {
    seq_table <- datatable(seq_df, rownames = FALSE, options = list(dom = 't', paging = FALSE), class = 'cell-border stripe')
    seq_div <- tags$div(style = "flex: 1;", tags$h4(style = "font-family: Arial, sans-serif; color: #34495E;", "Sequence Statistics"), seq_table)
    summary_layout <- tagAppendChild(summary_layout, seq_div)
  }
  
  ann_df <- summary_df %>% filter(Category == "Annotation") %>% select(Feature, Value)
  if(nrow(ann_df) > 0) {
    ann_table <- datatable(ann_df, rownames = FALSE, options = list(dom = 't', paging = FALSE), class = 'cell-border stripe')
    ann_div <- tags$div(style = "flex: 1;", tags$h4(style = "font-family: Arial, sans-serif; color: #34495E;", "Annotation Counts"), ann_table)
    summary_layout <- tagAppendChild(summary_layout, ann_div)
  }
  
  dashboard_elements <- tagAppendChildren(dashboard_elements, summary_layout, tags$hr())
}

# Build the Interactive Map with Dropdown UI
interactive_map_ui <- create_map_ui(bakta_df, opt$contig)

dashboard_elements <- tagAppendChildren(
  dashboard_elements,
  tags$h4(style = "font-family: Arial, sans-serif; color: #34495E;", "Interactive Genome Map"),
  interactive_map_ui,
  tags$hr()
)

# Create and Add the Searchable Gene Table
gene_display_df <- bakta_df %>% select(Seq_Id, Start, Stop, Strand, Locus, Gene, Product)
gene_table <- datatable(
  gene_display_df, 
  rownames = FALSE, 
  filter = 'top',
  options = list(pageLength = 10, autoWidth = TRUE, dom = 'ftip'),
  class = 'cell-border stripe hover'
)

dashboard_elements <- tagAppendChildren(
  dashboard_elements,
  tags$h4(style = "font-family: Arial, sans-serif; color: #34495E;", "Searchable Gene Database"),
  gene_table
)

# Combine into a final HTML document
final_html <- browsable(dashboard_elements)

# Save Output
message(paste("Saving interactive dashboard to:", opt$output))
save_html(final_html, file = opt$output)
message("Done! Open the HTML file in any web browser.")