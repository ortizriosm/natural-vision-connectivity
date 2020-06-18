#!/bin/tcsh
# affine alignment of individual dataset to D99 template
#
# usage:
#    macaque_align.csh dset template_dset segmentation_dset
#
# example:
#    tcsh -x macaque_align.csh Puffin_3mar11_MDEFT_500um+orig \
#      atlas_dir/D99_template+tlrc atlas_dir/D99_atlas+tlrc \
#      atlas_dir/D99_template+tlrc atlas_dir/D99_atlas_right+tlrc \
#
set atlas_dir = "../../data/D99_atlas/"
if ("$#" <  "3") then
   echo "usage:"
   echo "   macaque_align.csh dset template_dset segmentation_dset segmentation_right_only_dset"
   echo "example:"
   echo " tcsh -x macaque_align.csh macaque1+orig \"
   echo "   ${atlas_dir}/D99_template.nii.gz \"
   echo " ${atlas_dir}/D99_atlas_1.2a.nii.gz \"
   echo " ${atlas_dir}/D99_atlas_1.2a_right.nii.gz"
   exit
endif

setenv AFNI_COMPRESSOR GZIP

set dset = $1
set base = $2
set segset = $3

if ("$#" >=  "4") then
   set rightseg = $4
else
   set rightseg = ""
endif


# optional resample to D99_template resolution and use that
# set finalmaster = `@GetAfniPrefix $base`
set finalmaster = $dset

# set dset = Puffin_3mar11_MDEFT_500um+orig
# set base = atlasdir/D99s_template+tlrc.
# set segset = atlasdir/D99_atlas+tlrc
# set rightseg = atlasdir/D99_atlas_right+tlrc

set dsetprefix = `@GetAfniPrefix $dset`
set origdsetprefix = $dsetprefix
set segsetprefix = `@GetAfniPrefix $segset`
set segsetdir = `dirname $segset`

@Align_Centers -base $base -dset $dset

set dset = ${dsetprefix}_shft+orig
set dsetprefix = `@GetAfniPrefix $dset`

# goto apply_warps

# do affine alignment with lpa cost
# using dset as dset2 input and the base as dset1 
# (the base and source are treated differently 
# by align_epi_anats resampling and by 3dAllineate)
align_epi_anat.py -dset2 $dset -dset1 $base -overwrite -dset2to1 \
    -giant_move -suffix _al2std -dset1_strip None -dset2_strip None
#
## put affine aligned data on template grid
##  can't remember if this step is needed with giant_move in previous step
3dAllineate -1Dmatrix_apply ${dsetprefix}_al2std_mat.aff12.1D \
    -prefix ${dsetprefix}_aff -base $base -master BASE         \
    -source $dset -overwrite

# affinely align to template 
#  (could let auto_warp.py hande this, but AUTO_CENTER option might be needed)
# @auto_tlrc -base $base -input $dset -no_ss -init_xform AUTO_CENTER

# !!! Now skipping cheap skullstripping !!!
#   didn't work for macaques with very different size brains. V1 got cut off
#   probably could work with dilated mask
# "cheap" skullstripping with affine registered dataset
#  the macaque brains are similar enough that the affine seems to be sufficient here
#  for skullstripping
# 3dcalc -a ${dsetprefix}_aff+tlrc. -b $base -expr 'a*step(b)'   \
#    -prefix ${dsetprefix}_aff_ns -overwrite


# nonlinear alignment of affine skullstripped dataset to template
#  by default,the warp and the warped dataset are computed
#  by using "-qw_opts ", one could save the inverse warp and do extra padding
#  with -qw_opts '-iwarp -expad 30'
# change qw_opts to remove max_lev 2 for final   ********************
rm -rf awpy_${dsetprefix}
auto_warp.py -base $base -affine_input_xmat ID -qworkhard 0 2 \
   -input ${dsetprefix}_aff+tlrc -overwrite \
   -output_dir awpy_${dsetprefix} 

apply_warps:
# the awpy has the result dataset, copy the warped data and the warp
cp awpy_${dsetprefix}/${dsetprefix}_aff.aw.nii ./${dsetprefix}_warp2std.nii
cp awpy_${dsetprefix}/anat.un.qw_WARP.nii ${dsetprefix}_WARP.nii

# if the datasets are compressed, then copy those instead
cp awpy_${dsetprefix}/${dsetprefix}_aff.aw.nii.gz ./${dsetprefix}_warp2std.nii.gz
cp awpy_${dsetprefix}/anat.un.qw_WARP.nii.gz  ./${dsetprefix}_WARP.nii.gz

# compress these copies (if not already compressed)
gzip -f ${dsetprefix}_warp2std.nii ${dsetprefix}_WARP.nii


# Solution 1 combining and transforming with 3dNwarpApply
# put affine transformation in 1D file (already have the inverse as strip_shift.Xat.aff.1D)
#cat_matvec -ONELINE "${dsetprefix}+tlrc::WARP_DATA" >! ${dsetprefix}_at.1D
## one step concatenation and apply
#3dNwarpApply -prefix ${dsetprefix}_iwarpback                      \
#    -nwarp "${dsetprefix}_at.1D INV(${dsetprefix}_WARP.nii.gz)"   \
#    -source ${dsetprefix}_warp2std.nii.gz -master $dset -overwrite
#
#3dNwarpApply -prefix ${dsetprefix}_seg -interp NN                 \
#    -nwarp "${dsetprefix}_at.1D INV(${dsetprefix}_WARP.nii.gz)"   \
#    -source $segset -master $dset -overwrite


cat_matvec -ONELINE ${dsetprefix}_al2std_mat.aff12.1D -I >! ${dsetprefix}_inv.aff12.1D
# warp segmentation from atlas back to the original macaque space 
#  of the input dataset (compose overall warp when applying)
#  note - if transforming other datasets like the template
#    back to the same native space, it will be faster to compose
#    the warp separately with 3dNwarpCat or 3dNwarpCalc rather
#    than composing it for each 3dNwarpApply
3dNwarpApply -ainterp NN -short -overwrite -nwarp \
   "${dsetprefix}_inv.aff12.1D INV(${dsetprefix}_WARP.nii.gz)"  -overwrite \
   -source $segset -master ${dsetprefix}+orig -prefix __tmp_${dsetprefix}_seg

# put back in non-shifted version (really native space) 
@Align_Centers -base ${finalmaster} -dset  __tmp_${dsetprefix}_seg+orig. -no_cp

# change the datum type to byte to save space
# this step also gets rid of the shift transform in the header
3dcalc -a __tmp_${dsetprefix}_seg+orig -expr a -datum byte -nscale \
   -overwrite -prefix ${origdsetprefix}_seg

# copy segmentation information from atlas to this native-space
#   segmentation dataset and mark to be shown with integer colormap
3drefit -cmap INT_CMAP ${origdsetprefix}_seg+orig
3drefit -copytables $segset ${origdsetprefix}_seg+orig

# create transformed D99 template in this macaque's native space
# this dataset is useful for visualization
3dNwarpApply -overwrite -short -nwarp "${dsetprefix}_inv.aff12.1D INV(${dsetprefix}_WARP.nii.gz)" \
   -source $base -master ${dsetprefix}+orig -prefix __tmp_D99_in_${dsetprefix}_native -overwrite
@Align_Centers -base ${finalmaster} -dset __tmp_D99_in_${dsetprefix}_native+orig. -no_cp
# change the datum type to byte to save space
# this step also gets rid of the shift transform in the header
3dcalc -a __tmp_D99_in_${dsetprefix}_native+orig -expr a -datum byte -nscale \
   -prefix D99_in_${origdsetprefix}_native -overwrite


# Warp the right side of the atlas separately
# easier than figuring out right from left in native space directly
if ($rightseg != "") then
   3dNwarpApply -ainterp NN -short -overwrite -nwarp \
      "${dsetprefix}_inv.aff12.1D INV(${dsetprefix}_WARP.nii.gz)"  -overwrite \
      -source ${rightseg} -master ${dsetprefix}+orig -prefix __tmp_${dsetprefix}_right_seg

   # put back in non-shifted version (really native space) 
   @Align_Centers -base ${finalmaster} -dset  __tmp_${dsetprefix}_right_seg+orig. -no_cp

   # change the datum type to byte to save space
   # this step also gets rid of the shift transform in the header
   3dcalc -a __tmp_${dsetprefix}_right_seg+orig -expr a -datum byte -nscale \
      -overwrite -prefix ${origdsetprefix}_right_seg  -overwrite

   # copy segmentation information from atlas to this native-space
   #   segmentation dataset and mark to be shown with integer colormap
   3drefit -cmap INT_CMAP ${origdsetprefix}_right_seg+orig
   3drefit -copytables $segset ${origdsetprefix}_right_seg+orig
   mkdir right_surfaces
   cd right_surfaces
   IsoSurface -isorois+dsets -o native.gii -input ../${origdsetprefix}_right_seg+orig -noxform \
      -Tsmooth 0.1 100 -remesh 0.1
   cd ..
endif 

# create surfaces for all regions in atlas, but now in native space
mkdir surfaces
cd surfaces
IsoSurface -isorois+dsets -o native.gii -input ../${origdsetprefix}_seg+orig -noxform \
   -Tsmooth 0.1 100 -remesh 0.1
cd ..


# "carve" out D99 surface in native space to use as representative surface
#  using anisotropic smoothing
# could use skullstripped original instead
3danisosmooth -prefix D99_in_${origdsetprefix}_aniso -3D -iters 6 -matchorig D99_in_${origdsetprefix}_native+orig
# also remove any  small clusters for surface generation (threshold here is specific so may need tweaking)
3dclust -1Dformat -nosum -1dindex 0 -1tindex 0 -2thresh -57.2 57.2 \
   -savemask D99_in_${origdsetprefix}_aniso_clust -dxyz=1 1.01 20000 D99_in_${origdsetprefix}_aniso+orig
IsoSurface -isorange 1 255 -overwrite -input  D99_in_${origdsetprefix}_aniso_clust+orig. \
   -o  D99_in_${origdsetprefix}_aniso.gii -overwrite -noxform -Tsmooth 0.1 20

echo "Dataset output:"
echo "   segmentation in native space:  ${origdsetprefix}_seg+orig"
echo "   base template in native space: D99_in_${origdsetprefix}+orig"
echo "   surfaces in native space in surfaces directory"
echo "   right-side surfaces in native space in right_surfaces directory"
echo   
echo "to show surfaces in suma, use a command like this:"
echo "    suma -onestate -i surfaces/native*.gii -vol ${origdsetprefix}+orig -sv  D99_in_${origdsetprefix}_native+orig"
echo "or to show the template transformed to native space, use this:"
echo "    suma -onestate -i surfaces/native*.gii -vol ${origdsetprefix}+orig -sv  D99_in_${origdsetprefix}_native+orig"
echo
echo "or show D99 template as a *surface* in native space with segmentation volume, use this command"
echo "    suma -onestate -anatomical -i D99_in_${origdsetprefix}_aniso.gii -vol ${origdsetprefix}_seg+orig  -sv ${origdsetprefix}_seg+orig"
echo

# notes

# warp the transformed macaque back to its original space
#  just as a quality control. The two datasets should be very similar
# 3dNwarpApply -overwrite -short -nwarp \
#   "${dsetprefix}_inv.aff12.1D INV(${dsetprefix}_WARP.nii.gz)" \
#   -source ${dsetprefix}_warp2std.nii.gz -master ${finalmaster}+orig \
#   -prefix ${dsetprefix}_iwarpback -overwrite


# zeropad the warp if segmentation doesn't cover the brain and reapply the warp
# 3dZeropad -S 50 -prefix ${dsetprefix}_zp_WARP.nii.gz ${dsetprefix}_WARP.nii.gz
# 3dNwarpApply -interp NN \
#   -nwarp "${dsetprefix}_inv.aff12.1D INV(${dsetprefix}_zp_WARP.nii.gz)" \
#   -source $segset -master $dset -prefix ${dsetprefix}_seg_zp
# 3drefit -cmap INT_CMAP ${dsetprefix}_seg_zp+orig
# 3drefit -copytables $segset ${dsetprefix}_seg_zp+orig
