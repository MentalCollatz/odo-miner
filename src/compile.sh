#!/bin/bash

# Copyright (C) 2019 MentalCollatz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
