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

## Licence

RONUM is open-source software licensed under the GNU Affero General Public License v3.0 (AGPLv3). See the `LICENSE` file for the full licence terms.

The software is provided without warranty; use of RONUM and interpretation of its outputs remain the responsibility of the user.

Commercial or proprietary licensing arrangements may be available separately. [Contact details for enquiry are to be updated]. 


## About the name

RONUM is not an acronym.

The project was originally developed under the name **ROBIGUS**, after Robigus/Robigo, the Roman deity associated with cereal rust and the annual Robigalia rites intended to protect crops from the disease. Shortly before publication, we discovered that the name Robigus had recently been adopted by an unrelated plant-pathology software project, so the macro was renamed to avoid confusion.

I commend Assistant Professor Braham Dhillon for their excellent taste.

**RONUM** was chosen as a short replacement, loosely evoking rust quantification and numerical measurement.

ROBIGUS was a better name. Such is life.
