#!/bin/tcsh
# set environment variables in AFNI's .afnirc file in the user's home directory
# usage : tcsh macaque_env.csh

@AfniEnv -set AFNI_SUPP_ATLAS_DIR /Volumes/MyBookData/atlas/macaque/macaqueatlas_1.2a
@AfniEnv -set AFNI_WHEREAMI_DEC_PLACES 2
@AfniEnv -set AFNI_ATLAS_COLORS D99_atlas
@AfniEnv -set AFNI_TEMPLATE_SPACE_LIST D99_Macaque,D99_Macaque_book
@AfniEnv -set AFNI_WEBBY_WAMI YES
