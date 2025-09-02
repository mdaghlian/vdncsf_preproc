sub=gla02
qsub -q long.q@zeus -pe smp 4 -wd $PWD -N fpBFILT${sub}_SYN12 -o logs/fpBFILT${sub}_SYN12.txt fprep_command.sh ${sub}