from fireants.io.image import Image, BatchedImages
from fireants.registration.rigid import RigidRegistration
from fireants.registration.affine import AffineRegistration
from fireants.registration.syn import SyNRegistration
from time import time

# 1. Load fixed (MNI) and moving (MP2RAGE) images
fixed_img  = Image.load_file("/packages/fsl/6.0.7.15/data/standard/MNI152_T1_1mm.nii.gz")
moving_img = Image.load_file("/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/pymp2rage/sub-gla03/ses-A/sub-gla03_ses-A_acq-MP2RAGE_T1w.nii.gz")

fixed  = BatchedImages([fixed_img])
moving = BatchedImages([moving_img])

# 2. Shared multiscale settings
scales      = [8, 4, 2, 1]                 # shrink factors 8x4x2x1
iterations  = [1000, 500, 250, 100]        # convergence [1000x500x250x100,...]
mi_params   = {"bins": 32, "sampling": 0.25}
cc_params   = {"kernel_size": 4}
lr          = 0.1                          # learning‐rate for all stages

# 3. Rigid registration (MI)
rigid = RigidRegistration(
    scales=scales, iterations=iterations,
    fixed_images=fixed, moving_images=moving,
    optimizer="Adam", optimizer_lr=lr,
    metric="MI", metric_params=mi_params
)
t0 = time()
rigid.optimize()
print(f"Rigid finished in {time() - t0:.1f}s")

# 4. Affine registration (MI), initialize from Rigid
affine = AffineRegistration(
    scales=scales, iterations=iterations,
    fixed_images=fixed, moving_images=moving,
    optimizer="Adam", optimizer_lr=lr,
    metric="MI", metric_params=mi_params,
    init_affine=rigid.get_affine_matrix().detach()
)
t1 = time()
affine.optimize()
print(f"Affine finished in {time() - t1:.1f}s")

# 5. SyN registration (CC), initialize from Affine
syn = SyNRegistration(
    scales=scales, iterations=iterations,
    fixed_images=fixed, moving_images=moving,
    optimizer="Adam", optimizer_lr=lr,
    metric="CC", metric_params=cc_params,
    init_affine=affine.get_affine_matrix().detach()
)
t2 = time()
syn.optimize()
print(f"SyN finished in {time() - t2:.1f}s")

# 6. Save as ANTs‐compatible warp & composite transform
out_prefix = "/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/ants/sub-gla03/ses-A/sub-gla03_ses-A_from-T1w_to-MNI152NLin6Asym"
syn.save_as_ants_transforms(f"{out_prefix}_warp.nii.gz")
