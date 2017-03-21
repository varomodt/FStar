#!/usr/bin/env bash

# Sorry, everyone
if (( ${BASH_VERSION%%.*} < 4 )); then
  echo "This script requires Bash >= 4. On OSX, try: brew install bash"
  exit 1
fi

# Any error is fatal.
set -e
set -o pipefail

echo "** TO DO: Clean up existing packages first **"

echo "*** Make package ***"
cd src
cd ocaml-output
make package

echo "*** Test Package -- need to figure out how want to verify! ***"
# Unzip .zip file if exists
if [ -f fstar_0.9.4.0_Windows_x64.zip ]; then
  unzip -o fstar_0.9.4.0_Windows_x64.zip
fi

# Extract linux file if exists
if [ -f fstar_0.9.4.0_Linux_x86_64.tar.gz ]; then
  tar -x fstar_0.9.4.0_Linux_x86_64.tar.gz
fi

cd fstar

echo "*** Maybe check versions of fstar"
make -C examples/micro-benchmarks

echo "*** If you have OCaml installed the following command should print Hello F*!"
make -C examples/hello ocaml

echo "*** If you have F# installed the following command should print Hello F*!"
make -C examples/hello fs

echo "***You can verify all the examples, keeping in mind that this might take a long time."
make -j6 -C examples

## TO DO 
# These all seem to work -- just need to make more robust
# Updated Build Definitions to see if it works with process_build call
## TO DO 

# Push all changes to ocaml output ???

# Update Version.txt

# Create a new branch based on version (i.e. v0.9.x.y)

# Document the release


echo "**** DONE!!! ****"
