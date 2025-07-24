#!/usr/bin/env python
#$ -j Y
#$ -cwd
#$ -V
import getopt

import numpy as np
import os
import sys
import warnings
import yaml
import pickle
from datetime import datetime, timedelta
import time

warnings.filterwarnings('ignore')
opj = os.path.join

import numpy as np  
import nibabel as nb
import os
opj = os.path.join

# from amb_scripts.load_saved_info import *
from dpu_mini.utils import *


# sub_list = ['sub-01', 'sub-02']
sub_list = ['amb01', 'amb02', 'gla01', 'gla02', 'gla03', 'ctrl01']
fs_dir = '/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer'
b14_dict = {
    1:  'V1',   2: 'V2',    3: 'V3',    4: 'hV4',
    5: 'VO1',   6:  'VO2',  7: 'LO1',   8: 'LO2',
    9: 'TO1',   10: 'TO2',  11: 'V3b',  12: 'V3a'}

for sub in sub_list:
    label_dir = opj(fs_dir, sub, 'label')
    custom_label_dir = opj(fs_dir, sub, 'label', 'custom')
    if not os.path.exists(custom_label_dir):
        os.mkdir(custom_label_dir)
    n_verts = dag_load_nverts(sub=sub, fs_dir=fs_dir)
    total_num_vx = np.sum(n_verts)

    # Else look for rois in subs freesurfer label folder
    roi_line1 = f'#!ascii label  , from subject {sub} vox2ras=TkReg\n'
    b14_file = {}  
    b14_name = 'benson14_varea-0001'  
    b14_file['lh'] = dag_find_file_in_folder([b14_name, '.label', 'lh'], label_dir, recursive=True)    
    b14_file['rh'] = dag_find_file_in_folder([b14_name, '.label', 'rh'], label_dir, recursive=True)    
    for hemi in ['lh', 'rh']:
        for varea_i in b14_dict.keys():
            varea_n = b14_dict[varea_i]
            with open(b14_file[hemi]) as f:
                contents = f.readlines()            
            val_str = [contents[i].split(' ')[-1].split('\n')[0] for i in range(2,len(contents))]
            val_int = [int(float(val_str[i])) for i in range(len(val_str))]
            # Find where id matches...
            varea_match = [i==varea_i for i in val_int]
            varea_match = np.where(varea_match)[0] + 2 # +2 because contents has 2 lines at the start
            this_roi_txt = ''
            this_roi_txt += roi_line1
            this_roi_txt += f'{len(varea_match)}\n'
            for i_line in varea_match:
                this_roi_txt += contents[i_line]
                    
            this_roi_name = f'{hemi}.b14_{varea_n}.label'        
            dag_str2file(
                filename=opj(custom_label_dir, this_roi_name),
                txt=this_roi_txt, 
            )
