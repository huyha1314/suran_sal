import sys
import argparse
from Bio import Phylo

def find_taxa(tree_path, target_genome, output_path, num_relatives):
    print(f"Loading tree from: {tree_path}")
    tree = Phylo.read(tree_path, "newick")
    
    # 1. Find your genome in the tree
    try:
        target_clade = next(tree.find_elements(name=target_genome))
    except StopIteration:
        print(f"Error: Target genome '{target_genome}' not found in the tree.")
        sys.exit(1)

    # 2. Get the path from the root to your genome
    path_to_target = tree.get_path(target_clade)
    path_to_target.reverse() # Start checking immediate parents first

    close_relatives = []
    outgroup = None

    # 3. Walk up the tree
    for parent in path_to_target:
        leaves = parent.get_terminals()
        
        # Filter for references (usually start with RS_ or GB_ in GTDB)
        references = [leaf.name for leaf in leaves if leaf.name != target_genome and ("RS_" in leaf.name or "GB_" in leaf.name)]

        # Collect closest relatives
        if len(close_relatives) < num_relatives:
            for ref in references:
                if ref not in close_relatives and len(close_relatives) < num_relatives:
                    close_relatives.append(ref)
                    
        # Find the outgroup (the first reference on the NEXT branch)
        elif outgroup is None:
            for ref in references:
                if ref not in close_relatives:
                    outgroup = ref
                    break

        if len(close_relatives) == num_relatives and outgroup is not None:
            break

    # 4. Save the results to the specified output file
    try:
        with open(output_path, "w") as f:
            f.write(target_genome + "\n")
            for ref in close_relatives:
                f.write(ref + "\n")
            if outgroup:
                f.write(outgroup + "\n")
        
        print("\n=== Success ===")
        print(f"Target: {target_genome}")
        print(f"Found {len(close_relatives)} close relatives.")
        print(f"Found 1 outgroup: {outgroup}")
        print(f"List saved to: {output_path}")

    except IOError as e:
        print(f"Error writing to output file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Set up the argument parser
    parser = argparse.ArgumentParser(description="Extract a specific target genome, its closest relatives, and an outgroup from a GTDB-Tk tree.")
    
    # Define the expected arguments
    parser.add_argument("-i", "--input_tree", required=True, help="Path to the input GTDB-Tk Newick tree file.")
    parser.add_argument("-t", "--target", required=True, help="The exact ID of your target assembly in the tree (e.g., sam1).")
    parser.add_argument("-o", "--output", required=True, help="Path for the output text file containing the selected IDs.")
    parser.add_argument("-n", "--num_relatives", type=int, default=20, help="Number of close relatives to extract (default: 20).")

    # Parse the arguments from the command line
    args = parser.parse_args()

    # Run the main function with the parsed arguments
    find_taxa(args.input_tree, args.target, args.output, args.num_relatives)