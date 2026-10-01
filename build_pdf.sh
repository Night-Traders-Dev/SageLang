#!/bin/bash
cd core/docs
pandoc SageLang_Guide.md -o The_Sage_Programming_Language.pdf --pdf-engine=xelatex -V geometry:margin=1in
