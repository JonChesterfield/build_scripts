#!/bin/bash

set -x
set -e
set -o pipefail

cd $HOME/.emacs.d/build_scripts # pain to find the actual dir
for f in amdbuild aomp_tests common_build debbuild relbuild; do
    rm -f ../bin/$f
    ln $f ../bin/$f
done


