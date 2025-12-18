import pandas as pd
import io
#from google.colab import drive
#drive.mount('/content/drive')
#from __future__ import print_function
import pandas as pd
pd.__version__
import pandas as pd
import sys
import re
from collections import defaultdict

def filter_lines(input_file, output_file):
    """
    Filters lines in a file, keeping only those where the leading digit is greater than 1.

    Args:
        input_file: Path to the input file.
        output_file: Path to the output file.
    """

    try:
        with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
            for line in infile:
                parts = line.split()  # Split the line by whitespace
#                print("parts: ", parts)
 #               print("len: ", len(parts))
                if len(parts) >= 2:  # Ensure there's at least a digit and a string
                    digit =float(parts[0])  # Try converting the first part to an integer
  #                  print("digit: ", digit, ", ", parts[0], ", ", parts[1])
                    #if digit > 0.1:
                    if digit > 0.5:
                        outfile.write(line)  # Write the line to the output file
                else:
                    print(f"Skipping line: '{line.strip()}' - Not enough parts") #Example of ignoring the line
                    continue # Continue to the next line without writing anything.



    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

def main():
    input_filename = sys.argv[1]
    output_filename = sys.argv[2]
    filter_lines(input_filename, output_filename)
    print(f"Filtered lines written to '{output_filename}'")

if __name__ == "__main__":
    main()


