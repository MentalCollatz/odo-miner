#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"

if [ $# -ne 2 ]
then
    echo "usage: $0 <project> <seed>" 1>&2
    exit 1
fi

PROJECT="$1"
SEED="$2"

if ! [ -d "projects/$PROJECT" ]
then
    echo "Error: project $PROJECT does not exist" 1>&2
    exit 1
fi

if [ -z "$QUARTUSPATH" ]
then
    EXECUTABLE=$(which quartus_sh)
    if [ -z "$EXECUTABLE" ]
    then
        echo 'Error: could not locate quartus_sh, please set $QUARTUSPATH' 1>&2
        exit 1
    fi
else
    EXECUTABLE="$QUARTUSPATH/quartus_sh"
fi

set -e

source "projects/$PROJECT/params.sh"

BUILDDIR="projects/$PROJECT/build_files"
PROJFILE="$BUILDDIR/miner_$SEED.qsf"

( cd verilog && make odo_gen )
mkdir -p "$BUILDDIR"
sed -e s/SEED/$SEED/ -e s/_THROUGHPUT/$THROUGHPUT/ < "projects/$PROJECT/project.txt" > "$PROJFILE"
verilog/odo_gen "$SEED" "$THROUGHPUT" "odo_" > "$BUILDDIR/odo_$SEED.v"

"$EXECUTABLE" --flow compile "$PROJFILE"
