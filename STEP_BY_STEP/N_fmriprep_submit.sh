
for sub in ctrl05DEOB; do 
    qsub -q long.q@zeus -pe smp 1 -wd $PWD -N fp${sub} -o logs/fp${sub}.txt N_fmriprep.sh ${sub}
done