#!/bin/bash

set -x
set -e
set -o pipefail

for f in amdbuild aomp_tests common_build debbuild relbuild; do
    rm -f ../bin/$f
    ln $f ../bin/$f
done


