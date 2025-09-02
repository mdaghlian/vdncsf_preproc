
for sub in ctrl03; do 
    qsub -q long.q@zeus -pe smp 4 -wd $PWD -N fpMARCO${sub} -o logs/fpMARCO${sub}_SYN12.txt fprep_command_MARCO.sh ${sub}
done