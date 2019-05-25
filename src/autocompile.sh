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

MAINNET_EPOCH_LEN=864000
TESTNET_EPOCH_LEN=86400

EPOCH_LEN=$MAINNET_EPOCH_LEN
ANY=0
ERROR=0
CLEAN=1

for PROJECT in "$@"
do
    if [ "$PROJECT" == "--testnet" ]
    then
        EPOCH_LEN=$TESTNET_EPOCH_LEN
    elif [ "$PROJECT" == "--noclean" ]
    then
        CLEAN=0
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
    echo "usage: $0 [--testnet] [--noclean] <project> [...]" 1>&2
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
            if [[ "$PROJECT" == --* ]]
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
                if [ $CLEAN -eq 1 ]
                then
                    # Always delete old files based on mainnet seeds, since
                    # mainnet needs files for longer than testnet.
                    MAINNET_SEED=$(( $NOW - $NOW % $MAINNET_EPOCH_LEN ))
                    for PROJECT in "$@"
                    do
                        if [[ "$PROJECT" == --* ]]
                        then
                            continue
                        fi
                        # delete all build files
                        rm -rf projects/$PROJECT/build_files/*
                        # delete output files from old epochs
                        for FILE in projects/$PROJECT/output_files/miner_*
                        do
                            FILENAME=$(basename "$FILE")
                            EPOCH=${FILENAME//[^0-9]/}
                            if [ $EPOCH -lt $MAINNET_SEED ]
                            then
                                rm "$FILE"
                            fi
                        done
                    done
                fi
                echo "Up to date"
                UPTODATE=1
            fi
            # Nothing to do. Sleep for a while.
            sleep 60
        fi
    done
done
