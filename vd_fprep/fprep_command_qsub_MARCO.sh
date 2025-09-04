
for sub in ctrl05 ctrl06; do 
    qsub -q long.q@zeus -pe smp 4 -wd $PWD -N fp${sub} -o logs/fpMARCO${sub}_SYN12.txt fprep_command_MARCO.sh ${sub}
done