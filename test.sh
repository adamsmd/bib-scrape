#!/bin/sh

if test 0 -eq $#; then
    set -- tests/*.t
fi

for i in "$@"; do
    echo $i
    URL=`head -n 1 $i`
    (echo "$URL"; ./wmech.pl `head -n 1 $i`) | diff $i -
done