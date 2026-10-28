#!/bin/bash
# shieldXL (norns shield 210330) on Raspberry Pi OS trixie (arm64), step 5:
# the default scripts: awake (the script a new norns starts with) and
# firstlight. Cloned with git into ~/dust/code, as maiden does, so they can be
# updated from maiden. Run once norns is up (after the reboot that follows
# step 3); scripts that are already there are skipped.
set -e
CODE=~/dust/code
mkdir -p $CODE

while read name url; do
  if [ -d $CODE/$name ]; then
    echo "$name: already there"
  else
    git clone -q $url $CODE/$name && echo "$name: installed"
  fi
done <<LIST
awake https://github.com/tehn/awake.git
firstlight https://github.com/monome/firstlight.git
LIST

echo "step 5 done: SELECT on the norns lists the new scripts"
