# RONUM

RONUM is a Fiji/ImageJ macro package for semi-automated quantification of cereal rust disease from digital images.

## Contents

- `RONUM_Calibration_v1.0.0.ijm` – calibration of leaf and disease-detection parameters
- `RONUM_Quantification_v1.0.0.ijm` – guided and batch image quantification
- `example_data/` – example images for testing the workflow
- `Help_Images/` – instructional images used by the calibration macro
- `docs/` – user guide
- `validation/` – scripts used for validation analyses reported in Mann et al. (2026)

## Requirements

- Fiji/ImageJ v. 1.54

## Quick start

1. Run `RONUMS_Calibration_v1.0.0.ijm`
2. Calibrate detection parameters using representative images
3. Save the calibration profile
4. Run `RONUM_Quantification_v1.0.0.ijm`
5. Load the calibration profile and quantify the dataset

## Citation

Mann et al. (2026). *A rapid, semi-automated image-based method for quantitative assessment of rust disease progression in wheat*. Plant Methods. [publication details to be updated]

## Version

v1.0.0
