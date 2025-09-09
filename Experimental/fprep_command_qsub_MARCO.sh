
for sub in gla03; do 
    qsub -q long.q@zeus -pe smp 1 -wd $PWD -N fp${sub} -o logs/fp${sub}.txt fprep_command_MARCO.sh ${sub}
done