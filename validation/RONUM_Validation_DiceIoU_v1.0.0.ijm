// RONUM Validation Dice/IoU v1.0.0
// Reproducibility/validation analysis script; not required for routine RONUM quantification.
// This script is configured for the cropped-reference validation dataset used in the manuscript.
//
// ============================================================
// Dice / IoU comparison - CROPPED REFERENCES
//
// Use this after regenerating the manual reference masks with
// the exact RONUM crop.
//
// This macro:
//   1) asks for the folder containing CROPPED manual masks
//   2) asks for the parent DICE folder containing PPC folders
//   3) matches each manual mask to each PPC mask
//   4) applies the RONUM minimum particle filter (0.02332 mm^2)
//      to the PPC mask ONLY
//   5) calculates Dice + IoU
//   6) writes one CSV
//
// It does NOT crop, resize, register, or otherwise alter geometry.
//
// Expected PPC folders:
//   NoPPC Masks
//   Fill Masks
//   Despeckle Masks
//   Smooth Masks
//   SmoothDspeck Masks
//   WS Fill Masks
//   FILL+DESPECK+WS Masks
//   WS Smooth Fill Masks
//   AllPPC Masks
// ============================================================

minArea = 0.02332;

refDir = getDirectory("Choose CROPPED manual reference mask folder");
if (refDir == "") exit("No reference folder selected.");

parent = getDirectory("Choose parent DICE scores folder");
if (parent == "") exit("No parent folder selected.");

folders = newArray(
    "NoPPC Masks",
    "Fill Masks",
    "Despeckle Masks",
    "Smooth1 Masks",
    "Smooth Masks",
    "SmoothDspeck Masks",
    "WS Fill Masks",
    "FILL+DESPECK+WS Masks",
    "WS Smooth Fill Masks",
    "AllPPC Masks"
);

conditions = newArray(
    "Unprocessed",
    "Fill holes",
    "Despeckle",
    "Smooth1",
    "Smooth",
    "Smooth + Despeckle",
    "Fill holes + Watershed",
    "Fill holes + Despeckle + Watershed",
    "Fill + Smooth + Watershed",
    "All (Default)"
);

out = parent + "RONUM_Dice_IoU_CROPPED_REFERENCES.csv";

File.saveString(
    "Sample_ID,Condition,Dice,IoU,Reference_pixels,Filtered_test_pixels,Intersection_pixels,Reference_width,Reference_height,Test_width,Test_height,Reference_file,Test_file,Status\n",
    out
);

refs = getFileList(refDir);
totalOK = 0;
totalFail = 0;


// ============================================================
// MAIN LOOP
// ============================================================

for (r = 0; r < refs.length; r++) {

    refName = refs[r];

    if (!isTif(refName))
        continue;

    sampleID = manualToSampleID(refName);

    if (sampleID == "") {
        writeNameFailure(refName, "REFERENCE NAME NOT RECOGNISED");
        totalFail++;
        continue;
    }

    for (c = 0; c < folders.length; c++) {

        testDir = parent + folders[c] + File.separator;

        if (!File.exists(testDir)) {
            writeFailure(
                sampleID, conditions[c],
                "", "",
                0, 0, 0, 0,
                refName, "",
                "PPC FOLDER NOT FOUND"
            );
            totalFail++;
            continue;
        }

        match = findMatchingTif(testDir, sampleID);

        if (match == "") {
            writeFailure(
                sampleID, conditions[c],
                "", "",
                0, 0, 0, 0,
                refName, "",
                "NO MATCH FOUND"
            );
            totalFail++;
            continue;
        }


        // ----------------------------------------------------
        // OPEN REFERENCE
        // ----------------------------------------------------

        open(refDir + refName);
        rename("__DICE_REF__");

        standardizeBinaryWhiteForeground();

        refW = getWidth();
        refH = getHeight();

        refPix = foregroundPixels();


        // ----------------------------------------------------
        // OPEN TEST MASK
        // ----------------------------------------------------

        open(testDir + match);
        rename("__DICE_TEST_RAW__");

        standardizeBinaryWhiteForeground();

        testW = getWidth();
        testH = getHeight();

        getPixelSize(unitTest, pwTest, phTest, pdTest);


        // ----------------------------------------------------
        // DIMENSION CHECK
        // ----------------------------------------------------

        if (refW != testW || refH != testH) {

            writeFailure(
                sampleID, conditions[c],
                "", "",
                refW, refH, testW, testH,
                refName, match,
                "SIZE MISMATCH"
            );

            closePair();
            totalFail++;
            continue;
        }


        // ----------------------------------------------------
        // SCALE CHECK
        // ----------------------------------------------------

        if (pwTest == 1 && phTest == 1 && unitTest == "pixel") {

            writeFailure(
                sampleID, conditions[c],
                "", "",
                refW, refH, testW, testH,
                refName, match,
                "NO SPATIAL CALIBRATION"
            );

            closePair();
            totalFail++;
            continue;
        }


        // ----------------------------------------------------
        // FILTER PPC MASK USING SAME MINIMUM PARTICLE AREA
        // ----------------------------------------------------

        selectWindow("__DICE_TEST_RAW__");

        run(
            "Analyze Particles...",
            "size=" + minArea + "-Infinity show=Masks clear"
        );

        // Analyze Particles creates a new mask and makes it active.
        rename("__DICE_TEST_FILTERED__");

        standardizeBinaryWhiteForeground();

        filteredW = getWidth();
        filteredH = getHeight();

        if (filteredW != testW || filteredH != testH) {

            writeFailure(
                sampleID, conditions[c],
                "", "",
                refW, refH, filteredW, filteredH,
                refName, match,
                "FILTERED MASK DIMENSION ERROR"
            );

            selectWindow("__DICE_TEST_FILTERED__");
            close();

            selectWindow("__DICE_TEST_RAW__");
            close();

            selectWindow("__DICE_REF__");
            close();

            totalFail++;
            continue;
        }

        filteredPix = foregroundPixels();


        // ----------------------------------------------------
        // INTERSECTION
        // ----------------------------------------------------

        imageCalculator(
            "AND create",
            "__DICE_REF__",
            "__DICE_TEST_FILTERED__"
        );

        rename("__DICE_INT__");

        standardizeBinaryWhiteForeground();

        intersection = foregroundPixels();


        // ----------------------------------------------------
        // HARD SANITY CHECK
        // ----------------------------------------------------

        if (intersection > refPix || intersection > filteredPix) {

            writeFailure(
                sampleID, conditions[c],
                "", "",
                refW, refH, testW, testH,
                refName, match,
                "INVALID INTERSECTION"
            );

            closeAllDiceWindows();
            totalFail++;
            continue;
        }


        // ----------------------------------------------------
        // DICE + IoU
        // ----------------------------------------------------

        denomDice = refPix + filteredPix;
        unionPix = refPix + filteredPix - intersection;

        if (denomDice == 0)
            dice = 1;
        else
            dice = (2 * intersection) / denomDice;

        if (unionPix == 0)
            iou = 1;
        else
            iou = intersection / unionPix;


        // ----------------------------------------------------
        // WRITE RESULT
        // ----------------------------------------------------

        File.append(
            cleanSampleID(sampleID) + "," +
            conditions[c] + "," +
            d2s(dice, 6) + "," +
            d2s(iou, 6) + "," +
            refPix + "," +
            filteredPix + "," +
            intersection + "," +
            refW + "," +
            refH + "," +
            testW + "," +
            testH + "," +
            refName + "," +
            match + "," +
            "OK\n",
            out
        );

        totalOK++;


        // ----------------------------------------------------
        // CLEAN UP
        // ----------------------------------------------------

        closeAllDiceWindows();
    }
}


print("--------------------------------");
print("DICE ANALYSIS COMPLETE");
print("OK comparisons: " + totalOK);
print("Failed comparisons: " + totalFail);
print("Output:");
print(out);
print("--------------------------------");


// ============================================================
// FUNCTIONS
// ============================================================

function isTif(name) {
    low = toLowerCase(name);
    return endsWith(low, ".tif") || endsWith(low, ".tiff");
}


// ------------------------------------------------------------
// Force binary white foreground on black background.
// Disease should occupy the minority of pixels.
// ------------------------------------------------------------

function standardizeBinaryWhiteForeground() {

    run("8-bit");

    setThreshold(1, 255);
    setOption("BlackBackground", true);
    run("Convert to Mask");

    getHistogram(vv, cc, 256);

    white = cc[255];
    black = cc[0];

    if (white > black)
        run("Invert");
}


// ------------------------------------------------------------
// Manual-mask filename -> common sample key.
//
// Supports:
//   1.1_6.1_RONUM_leaf08_ManMask.tif
//   GFP_5_RONUM_leaf03_ManMask.tif
//   TEF_2_RONUM_leaf01_ManMask.tif
//   B1Leaf1_ManMask.tif
//
// Legacy ROBIGUS filenames from the manuscript validation dataset
// are also supported.
// Also tolerates extra crop suffixes after _ManMask.
// ------------------------------------------------------------

function manualToSampleID(name) {

    base = name;
    low = toLowerCase(base);

    if (endsWith(low, ".tiff"))
        base = substring(base, 0, lengthOf(base) - 5);
    else if (endsWith(low, ".tif"))
        base = substring(base, 0, lengthOf(base) - 4);

    // Prefer current RONUM filenames, but retain support for
    // legacy ROBIGUS filenames used in the manuscript validation dataset.
    tag = "_RONUM_leaf";
    p = indexOf(base, tag);

    if (p < 0) {
        tag = "_ROBIGUS_leaf";
        p = indexOf(base, tag);
    }

    if (p >= 0) {

        prefix = substring(base, 0, p);

        rest = substring(
            base,
            p + lengthOf(tag)
        );

        q = indexOf(rest, "_");

        if (q < 0)
            return "";

        leafNum = substring(rest, 0, q);
        leafNum = "" + parseInt(leafNum);

        return prefix + "|leaf" + leafNum;
    }

    p = indexOf(base, "_ManMask");

    if (p >= 0)
        return substring(base, 0, p);

    // Some recovery runs may save an otherwise-identical name
    // without _ManMask. Accept simple *LeafN names conservatively.
    if (indexOf(base, "Leaf") >= 0)
        return base;

    return "";
}


// ------------------------------------------------------------
// Find matching PPC TIFF.
// Handles the naming forms used in the validation dataset.
// ------------------------------------------------------------

function findMatchingTif(dir, sampleID) {

    list = getFileList(dir);

    p = indexOf(sampleID, "|");

    if (p >= 0) {

        prefix = substring(sampleID, 0, p);

        leafPart = substring(sampleID, p + 1);
        leafNum = substring(leafPart, 4);

        leafPad = leafNum;
        if (parseInt(leafNum) < 10)
            leafPad = "0" + leafNum;

        for (i = 0; i < list.length; i++) {

            name = list[i];

            if (!isTif(name))
                continue;

            // 1.1_6.1_leaf8_NOPPC_leaf01_mask.tif
            if (startsWith(name, prefix + "_leaf" + leafNum + "_"))
                return name;

            // TEF_2_leaf01_NOPPC_leaf01_mask.tif
            if (startsWith(name, prefix + "_leaf" + leafPad + "_"))
                return name;

            // GFP_5_RONUM_leaf03_raw_strip_NOPPC_leaf01_mask.tif
            if (startsWith(name, prefix + "_RONUM_leaf" + leafPad + "_"))
                return name;

            // Legacy manuscript-validation filename:
            // GFP_5_ROBIGUS_leaf03_raw_strip_NOPPC_leaf01_mask.tif
            if (startsWith(name, prefix + "_ROBIGUS_leaf" + leafPad + "_"))
                return name;
        }

        return "";
    }


    // Simple style: B1Leaf1_NOPPC_leaf01_mask.tif
    p = indexOf(sampleID, "Leaf");

    if (p >= 0) {

        prefix = substring(sampleID, 0, p);
        leafNum = substring(sampleID, p + 4);

        leafPad = leafNum;
        if (parseInt(leafNum) < 10)
            leafPad = "0" + leafNum;

        for (i = 0; i < list.length; i++) {

            name = list[i];

            if (!isTif(name))
                continue;

            if (startsWith(name, prefix + "Leaf" + leafNum + "_"))
                return name;

            if (startsWith(name, prefix + "Leaf" + leafPad + "_"))
                return name;
        }
    }

    return "";
}


// ------------------------------------------------------------
// Count white foreground pixels.
// ------------------------------------------------------------

function foregroundPixels() {

    getHistogram(values, counts, 256);

    if (counts.length == 256)
        return counts[255];

    return 0;
}


// ------------------------------------------------------------
// Clean display ID.
// ------------------------------------------------------------

function cleanSampleID(sampleID) {

    p = indexOf(sampleID, "|");

    if (p < 0)
        return sampleID;

    return substring(sampleID, 0, p) +
           "_" +
           substring(sampleID, p + 1);
}


// ------------------------------------------------------------
// Failure writers.
// ------------------------------------------------------------

function writeNameFailure(refName, message) {

    File.append(
        refName +
        ",,,,,,,,,,,," +
        refName + ",," +
        message + "\n",
        out
    );
}


function writeFailure(
    sampleID,
    condition,
    dice,
    iou,
    refW,
    refH,
    testW,
    testH,
    refName,
    testName,
    message
) {

    File.append(
        cleanSampleID(sampleID) + "," +
        condition + "," +
        dice + "," +
        iou + "," +
        ",,," +
        refW + "," +
        refH + "," +
        testW + "," +
        testH + "," +
        refName + "," +
        testName + "," +
        message + "\n",
        out
    );
}


// ------------------------------------------------------------
// Window cleanup.
// ------------------------------------------------------------

function closePair() {

    if (isOpen("__DICE_TEST_RAW__")) {
        selectWindow("__DICE_TEST_RAW__");
        close();
    }

    if (isOpen("__DICE_REF__")) {
        selectWindow("__DICE_REF__");
        close();
    }
}


function closeAllDiceWindows() {

    if (isOpen("__DICE_INT__")) {
        selectWindow("__DICE_INT__");
        close();
    }

    if (isOpen("__DICE_TEST_FILTERED__")) {
        selectWindow("__DICE_TEST_FILTERED__");
        close();
    }

    if (isOpen("__DICE_TEST_RAW__")) {
        selectWindow("__DICE_TEST_RAW__");
        close();
    }

    if (isOpen("__DICE_REF__")) {
        selectWindow("__DICE_REF__");
        close();
    }
}