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

EPOCH_LEN=864000
ANY=0
ERROR=0

for PROJECT in "$@"
do
    if [ "$PROJECT" == "--testnet" ]
    then
        EPOCH_LEN=86400
    elif [ -d "projects/$PROJECT" ]
    then
        ANY=1
    else
        echo "Error: project $PROJECT does not exist" 1>&2
        ERROR=1
    fi
done

if [ $ERROR -eq 1 -o $ANY -eq 0 ]
then
    echo "usage: $0 [--testnet] <project> [...]" 1>&2
    exit 1
fi

UPTODATE=0
while true
do
    NOW=$( date +%s )
    CURRENT_SEED=$(( $NOW - $NOW % $EPOCH_LEN ))
    NEXT_SEED=$(( $CURRENT_SEED + $EPOCH_LEN ))
    for SEED in $CURRENT_SEED $NEXT_SEED
    do
        for PROJECT in "$@"
        do
            if [ "$PROJECT" == "--testnet" ]
            then
                continue
            fi
            if [ -e "projects/$PROJECT/output_files/miner_$SEED.sof" ]
            then
                continue
            fi
            UPTODATE=0
            ./compile.sh $PROJECT $SEED
            # We might have advanced to the next epoch by now.
            break 2
        done
        if [ $SEED -eq $NEXT_SEED ]
        then
            if [ $UPTODATE -eq 0 ]
            then
                echo "Up to date"
                UPTODATE=1
            fi
            # Nothing to do. Sleep for a while.
            sleep 60
        fi
    done
done
