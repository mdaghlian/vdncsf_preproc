#!/usr/bin/env python
#$ -j Y
#$ -cwd
#$ -V
"""
animated_slices.py

Improved, faster, and prettier version of your script that:
 - Loads 3D/4D NIfTI files (works with fMRIPrep outputs)
 - Extracts sagittal, coronal and axial central slices (and frames if 4D)
 - Builds a single animation with three panels (sagittal / coronal / axial)
 - Displays file number + frame number in the title
 - Uses memory-friendly nibabel indexing (doesn't load whole 4D volumes when possible)
 - Auto-scales intensity using robust percentiles
 - Saves to MP4 using ffmpeg (or GIF if requested)

Usage:
    python animated_slices.py --data-dir /path/to/data --out out_movie.mp4 --fps 6

Dependencies: nibabel, numpy, matplotlib. For MP4 output you'll need ffmpeg installed.
"""

import os
import argparse
import glob
from pathlib import Path
import numpy as np
import nibabel as nib
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from dpu_mini.utils import dag_find_file_in_folder


def extract_central_slices(img, t_index=None):
    """Return (sagittal, coronal, axial) arrays for a given nibabel image.
    If the image is 4D supply t_index (int). If image is 3D, t_index is ignored.
    Uses img.dataobj to avoid loading whole volume into memory when possible.
    Returns float32 arrays.
    """
    shape = img.shape
    dataobj = img.dataobj

    if img.ndim == 3:
        # shapes: (X, Y, Z)
        X, Y, Z = shape
        mid_x, mid_y, mid_z = X // 2, Y // 2, Z // 2
        sag = np.array(dataobj[mid_x, :, :], dtype=np.float32)
        cor = np.array(dataobj[:, mid_y, :], dtype=np.float32)
        axl = np.array(dataobj[:, :, mid_z], dtype=np.float32)
    elif img.ndim == 4:
        X, Y, Z, T = shape
        if t_index is None:
            t_index = 0
        mid_x, mid_y, mid_z = X // 2, Y // 2, Z // 2
        # Use array proxy indexing to only read the needed slices
        sag = np.array(dataobj[mid_x, :, :, t_index], dtype=np.float32)
        cor = np.array(dataobj[:, mid_y, :, t_index], dtype=np.float32)
        axl = np.array(dataobj[:, :, mid_z, t_index], dtype=np.float32)
    else:
        raise ValueError(f"Unsupported image dimensionality: {img.ndim}")

    return sag, cor, axl


def build_frame_stacks(file_list):
    """Iterate files and extract central slices for every 3D volume or for every timepoint
    in a 4D file. Returns three stacks: sagittal_stack, coronal_stack, axial_stack with shapes
    (N_frames, H, W) and a frames_meta list of dicts: {file_idx, file_name, time_idx}.
    Also returns vmin, vmax computed robustly across frames for display scaling.
    """
    sag_list = []
    cor_list = []
    axl_list = []
    frames_meta = []

    # We'll compute percentiles incrementally for vmin/vmax
    all_values = []

    for fi, fpath in enumerate(file_list):
        try:
            img = nib.load(fpath)
        except Exception as e:
            print(f"Skipping {fpath}: error loading ({e})")
            continue
        print(fpath)
        fname = os.path.basename(fpath)
        if img.ndim == 3:
            sag, cor, axl = extract_central_slices(img)
            sag_list.append(sag)
            cor_list.append(cor)
            axl_list.append(axl)
            frames_meta.append({"file_idx": fi, "file_name": fname, "time_idx": 0})
            all_values.append(sag.ravel())
            all_values.append(cor.ravel())
            all_values.append(axl.ravel())

        elif img.ndim == 4:
            T = img.shape[3]
            for t in range(T):
                sag, cor, axl = extract_central_slices(img, t_index=t)
                sag_list.append(sag)
                cor_list.append(cor)
                axl_list.append(axl)
                frames_meta.append({"file_idx": fi, "file_name": fname, "time_idx": t})
                all_values.append(sag.ravel())
                all_values.append(cor.ravel())
                all_values.append(axl.ravel())
        else:
            print(f"File {fpath} has unexpected ndim {img.ndim} -- skipping")

    if not sag_list:
        raise RuntimeError("No frames extracted from the provided files.")

    # Stack into arrays (N, H, W)
    sagittal_stack = np.stack(sag_list, axis=0)
    coronal_stack = np.stack(cor_list, axis=0)
    axial_stack = np.stack(axl_list, axis=0)

    # Compute robust vmin/vmax using percentiles across a sampled subset (concatenate could be big)
    # Combine a random subset if very large
    all_values_concat = np.concatenate([v for v in all_values], axis=0)
    vmin, vmax = np.percentile(all_values_concat, [1.0, 99.0])

    return sagittal_stack, coronal_stack, axial_stack, frames_meta, (vmin, vmax)


def make_animation(sag_stack, cor_stack, axl_stack, frames_meta, out_file, fps=5, cmap="gray", vmin=None, vmax=None, dpi=150):
    n_frames = sag_stack.shape[0]

    # Choose figure layout: three panels side-by-side
    fig, axes = plt.subplots(1, 3, figsize=(12, 5))
    titles = ["Sagittal", "Coronal", "Axial"]
    im_objs = []

    for ax, title in zip(axes, titles):
        ax.axis('off')
        ax.set_title(title, fontsize=10)

    # Initial images (transpose for consistent orientation and origin lower)
    im0 = axes[0].imshow(sag_stack[0].T, origin='lower', cmap=cmap, vmin=vmin, vmax=vmax)
    im1 = axes[1].imshow(cor_stack[0].T, origin='lower', cmap=cmap, vmin=vmin, vmax=vmax)
    im2 = axes[2].imshow(axl_stack[0].T, origin='lower', cmap=cmap, vmin=vmin, vmax=vmax)

    im_objs.extend([im0, im1, im2])

    # Add a subtle overall title placeholder (will be updated each frame)
    suptitle = fig.suptitle("", fontsize=12)

    def update(frame_idx):
        meta = frames_meta[frame_idx]
        file_idx = meta['file_idx']
        fname = meta['file_name']
        t_idx = meta['time_idx']

        im_objs[0].set_array(sag_stack[frame_idx].T)
        im_objs[1].set_array(cor_stack[frame_idx].T)
        im_objs[2].set_array(axl_stack[frame_idx].T)

        suptitle.set_text(f"File {file_idx+1}/{len(set(m['file_idx'] for m in frames_meta))} : {fname}  |  Frame {frame_idx+1}/{n_frames}  (vol {t_idx+1})")

        return im_objs + [suptitle]

    ani = FuncAnimation(fig, update, frames=n_frames, interval=1000 / fps, blit=True)

    # Save
    print(f"Saving animation to {out_file}...")
    try:
        if out_file.lower().endswith('.mp4'):
            # Use ffmpeg (ensure ffmpeg is installed in system PATH)
            ani.save(out_file, writer='ffmpeg', fps=fps, dpi=dpi)
        elif out_file.lower().endswith('.gif'):
            ani.save(out_file, writer='imagemagick', fps=fps, dpi=dpi)
        else:
            # default to mp4
            ani.save(out_file + '.mp4', writer='ffmpeg', fps=fps, dpi=dpi)
        print("Saved successfully.")
    except Exception as e:
        print(f"Error saving animation: {e}")

    plt.close(fig)


def main():
    p = argparse.ArgumentParser(description='Create a 3-panel (sag/cor/ax) animation from NIfTI files')
    p.add_argument('--data-dir', required=True, help='Directory containing NIfTI files (or a single file)')
    p.add_argument('--out', default='slices_movie.mp4', help='Output file (mp4 or gif)')
    p.add_argument('--filt', nargs='*', default=['T1w', 'preproc', 'bold', 'nii.gz'], help='Filename filters (all must appear)')
    p.add_argument('--fps', type=int, default=5, help='Frames per second')
    p.add_argument('--dpi', type=int, default=150, help='DPI for saved movie')
    args = p.parse_args()

    # Resolve files
    if os.path.isfile(args.data_dir) and args.data_dir.endswith(('.nii', '.nii.gz')):
        file_list = [args.data_dir]
    else:
        file_list = dag_find_file_in_folder(
            filt=args.filt,
            path=args.data_dir, 
            recursive=True, 
            )
        

    if not file_list:
        raise SystemExit(f"No files found in {args.data_dir} matching filters {args.filt}")

    print(f"Found {len(file_list)} files. Building frames...")
    sag, cor, axl, frames_meta, (vmin, vmax) = build_frame_stacks(file_list)

    print(f"Total frames: {sag.shape[0]}  | intensity range (1-99 %%): {vmin:.3f} - {vmax:.3f}")

    make_animation(sag, cor, axl, frames_meta, args.out, fps=args.fps, cmap='gray', vmin=vmin, vmax=vmax, dpi=args.dpi)


if __name__ == '__main__':
    main()
