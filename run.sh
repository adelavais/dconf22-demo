rm -f app.d
bison app.y # generate app.d
dub run     # run D program
