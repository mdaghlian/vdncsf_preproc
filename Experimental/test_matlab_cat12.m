%-----------------------------------------------------------------------------
% Created on Mon Jul 14 14:01:29 CEST 2025. Running with 1113

clear;
addpath(genpath('/data1/projects/dumoulinlab/Lab_members/Marcus/programs/spm12'));
matlabbatch{1}.spm.tools.cat.estwrite.data = {'/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/denoised/sub-ctrl01/ses-A/sub-ctrl01_ses-A_acq-MP2RAGE_T1w.nii,1'};
matlabbatch{1}.spm.tools.cat.estwrite.nproc = 0;
matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = {'/data1/projects/dumoulinlab/Lab_members/Marcus/programs/spm12/tpm/TPM.nii'};
matlabbatch{1}.spm.tools.cat.estwrite.opts.affreg = 'mni';
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.dartel = 0;  
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.native = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.dartel = 0; 
matlabbatch{1}.spm.tools.cat.estwrite.output.label.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.dartel = 0;   
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.native = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.native = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.warps = [0 0];
matlabbatch{1}.spm.tools.cat.estwrite.opts.ngaus = [1 1 2 3 4 2];
matlabbatch{1}.spm.tools.cat.estwrite.opts.biasreg = 0.01;
matlabbatch{1}.spm.tools.cat.estwrite.opts.biasfwhm = 90;
matlabbatch{1}.spm.tools.cat.estwrite.opts.warpreg = [0 0.001 0.5 0.05 0.2];
matlabbatch{1}.spm.tools.cat.estwrite.opts.samp = 3;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.APP = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.sanlm = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.NCstr = -Inf;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.LASstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.gcutstr = 2;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.cleanupstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.regstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.WMHCstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.WMHC = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.darteltpm = {'/data1/projects/dumoulinlab/Lab_members/Marcus/programs/spm12/toolbox/cat12/templates_1.50mm/Template_1_IXI555_MNI152.nii'};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.restypes.native = struct([]);
matlabbatch{1}.spm.tools.cat.estwrite.extopts.vox = 1.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.pbtres = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.scale_cortex = 0.7;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.add_parahipp = 0.1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.ignoreErrors = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROI = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.neuromorphometrics = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.lpba40 = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.cobra = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.hammers = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.jacobian.warped = 0;

cat_get_defaults('extopts.expertgui',1);
spm_jobman('initcfg');
spm('defaults','fMRI')
spm_jobman('run', matlabbatch);
exit
