http://portal.acm.org/citation.cfm?id=258960
Fix Blu -> Blume.  (Bug in ACM BibTeX.)
@inproceedings{Blume:1997:10.1145/258948.258960,
  author = {Blume, Matthias and Appel, Andrew W.},
  title = {Lambda-splitting: a higher-order approach to cross-module optimizations},
  booktitle = {Proceedings of the second ACM SIGPLAN international conference on Functional programming},
  series = {ICFP '97},
  location = {Amsterdam, The Netherlands},
  pages = {112--124},
  numpages = {13},
  year = {1997},
  publisher = {ACM},
  address = {New York, NY, USA},
  isbn = {0-89791-918-1},
  doi = {10.1145/258948.258960},
  acmid = {258960},
  abstract = {We describe an algorithm for automatic inline expansion across module boundaries that works in the presence of higher-order functions and free variables; it rearranges bindings and scopes as necessary to move nonexpansive code from one module to another. We describe---and implement---the algorithm as transformations on {\lambda}-calculus. Our inliner interacts well with separate compilation and is efficient, robust, and practical enough for everyday use in the SML/NJ compiler. Inlining improves performance by 4--8\% on existing code, and makes it possible to use much more data abstraction by consistently eliminating penalties for modularity.},
}
