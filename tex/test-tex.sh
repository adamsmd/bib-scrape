#!/bin/bash

cat ../tests/*.t >test.bib

rm test.bbl test.aux test.pdf
cat >test.tex <<EOF
\documentclass[11pt]{article}
\usepackage{hyperref}
\usepackage{amssymb}

\begin{document}

\nocite{*}

\bibliography{test}
\bibliographystyle{bib-scrape}
\end{document}
EOF

pdflatex test && bibtex test && pdflatex test && pdflatex test
