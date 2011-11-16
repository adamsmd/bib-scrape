#!/bin/sh

if test 0 -eq $#; then
    set -- tests/*.t
fi

for i in "$@"; do
    echo $i
    URL=`head -n 1 $i`
    (head -n 2 $i; ./bib-scrape.pl `head -n 1 $i` | ./bib-fix.pl) | diff $i -
done
