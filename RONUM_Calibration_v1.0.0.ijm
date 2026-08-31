// RONUM Calibration v1.0.0
// Semi-automated ImageJ/Fiji macro for cereal rust disease quantification
//
// Calibration only.
// This macro saves:
// - optional leaf-detection HSB threshold values and leaf-size parameters
// - pustule HSB threshold values and Pass/Stop states
// - smallest viable pustule area
// - largest single pustule area / cluster flag threshold
//
// It does NOT save experiment folders, output folders, processing choices,
// or quantification output options. Those belong in the quantification macro.
//

requires("1.54");


// ============================================================
// RONUM paths
// ============================================================

// Choose the main RONUM folder.
// This should contain:
// Settings/
// Run_Presets/

BASE_DIR = getDirectory("Choose main RONUM folder");

if (BASE_DIR == "") {
    exit("No RONUM folder selected.");
}

BASE_DIR = replace(BASE_DIR, "\\", "/");

if (!endsWith(BASE_DIR, "/")) {
    BASE_DIR = BASE_DIR + "/";
}

SETTINGS_DIR = BASE_DIR + "Settings/";
PRESETS_DIR = BASE_DIR + "Run_Presets/";
HELP_IMAGES_DIR = BASE_DIR + "Help_Images/";
ROI_GUIDE = HELP_IMAGES_DIR + "ROI_selection_guide.png";
LEAF_GUIDE = HELP_IMAGES_DIR + "Leaf_thresholding_guide.png";
PUSTULE_GUIDE = HELP_IMAGES_DIR + "Pustule_thresholding_guide.png";

if (!File.exists(SETTINGS_DIR)) {
    File.makeDirectory(SETTINGS_DIR);
}

if (!File.exists(PRESETS_DIR)) {
    File.makeDirectory(PRESETS_DIR);
}


// ============================================================
// Helper functions
// ============================================================

function cleanName(s) {
    s = replace(s, " ", "_");
    s = replace(s, ":", "-");
    s = replace(s, "/", "-");
    s = replace(s, "\\", "-");
    s = replace(s, "*", "-");
    s = replace(s, "?", "-");
    s = replace(s, "\"", "-");
    s = replace(s, "<", "-");
    s = replace(s, ">", "-");
    s = replace(s, "|", "-");
    return s;
}

function boolText(v) {
    if (v == 1) return "true";
    return "false";
}

function appendSetting(path, key, value) {
    File.append(key + "," + value + "\n", path);
}

function passTextToBool(s) {
    if (s == "Pass") return 1;
    return 0;
}

function trueTextToBool(s) {
    if (s == "true") return 1;
    return 0;
}

// Screen and window layout helpers. These keep the active image on the left,
// Color Threshold in the centre, and the instruction popup on the right.
function getScreenSizeText() {
    js = "var d=java.awt.Toolkit.getDefaultToolkit().getScreenSize();" +
         "d.width+'|'+d.height;";
    return eval("script", js);
}

function positionCurrentImage(x, y, w, h) {
    js = "var WM=Java.type('ij.WindowManager');var win=WM.getCurrentWindow();" +
         "if(win!=null){win.setLocation(" + x + "," + y + ");" +
         "win.setSize(" + w + "," + h + ");}";
    eval("script", js);
}

function positionColorThresholdWindow(x, y) {
    js =
        "var C=java.lang.Class.forName('ij.plugin.frame.ColorThresholder');" +
        "var fi=C.getDeclaredField('instance');fi.setAccessible(true);" +
        "var o=fi.get(null);if(o!=null){o.setLocation(" + x + "," + y + ");}";
    eval("script", js);
}

// Shows a modeless instruction window so the user can still interact with
// the active image. If the guide image is missing, the instructions still run.
function showInstruction(title, message, guidePath, x, y) {
    Dialog.createNonBlocking(title);
    Dialog.addMessage(message);
    if (File.exists(guidePath))
        Dialog.addImage(guidePath);
    else
        Dialog.addMessage("Guide image not found:\n" + guidePath);
    Dialog.setLocation(x, y);
    Dialog.show();
}

// Reads the live ImageJ Color Threshold window using Java reflection.
// Returned fields:
// color space | method | dark background | display mode |
// channel 1 min | max | Pass/Stop | channel 2 min | max | Pass/Stop |
// channel 3 min | max | Pass/Stop
function readColorThresholdSettings() {
    js =
        "var C=java.lang.Class.forName('ij.plugin.frame.ColorThresholder');" +
        "var fi=C.getDeclaredField('instance');fi.setAccessible(true);" +
        "var o=fi.get(null);" +
        "if(o==null) 'ERROR:no_instance'; else {" +
        "function field(n){var f=C.getDeclaredField(n);f.setAccessible(true);return f.get(o);}" +
        "var cs=''+field('colorSpaceChoice').getSelectedItem();" +
        "var method=''+field('methodChoice').getSelectedItem();" +
        "var dark=field('darkBackground').getState()?'true':'false';" +
        "var mode=''+field('modeChoice').getSelectedItem();" +
        "var hp=field('bandPassH').getState()?'Pass':'Stop';" +
        "var sp=field('bandPassS').getState()?'Pass':'Stop';" +
        "var bp=field('bandPassB').getState()?'Pass':'Stop';" +
        "cs+'|'+method+'|'+dark+'|'+mode+'|' +" +
        "field('minHue')+'|'+field('maxHue')+'|'+hp+'|' +" +
        "field('minSat')+'|'+field('maxSat')+'|'+sp+'|' +" +
        "field('minBri')+'|'+field('maxBri')+'|'+bp;" +
        "}";
    return eval("script", js);
}


// Restores the source image immediately after Color Threshold opens while
// leaving the threshold controls active. This is equivalent to clicking
// the Color Threshold window's "Original" button.
function showOriginalInColorThreshold() {
    js =
        "var C=java.lang.Class.forName('ij.plugin.frame.ColorThresholder');" +
        "var fi=C.getDeclaredField('instance');fi.setAccessible(true);" +
        "var o=fi.get(null);" +
        "if(o!=null){" +
        "var fb=C.getDeclaredField('originalB');fb.setAccessible(true);" +
        "var b=fb.get(o);" +
        "var E=java.awt.event.ActionEvent;" +
        "o.actionPerformed(new E(b,E.ACTION_PERFORMED,'Original'));" +
        "}";
    eval("script", js);
}

// Closes the live ImageJ Color Threshold window before another image is selected.
// Otherwise its red preview is immediately applied to the newly selected image.
function closeColorThresholdWindow() {
    js =
        "var C=java.lang.Class.forName('ij.plugin.frame.ColorThresholder');" +
        "var fi=C.getDeclaredField('instance');fi.setAccessible(true);" +
        "var o=fi.get(null);" +
        "if(o!=null){o.close();}";
    eval("script", js);
}

// ============================================================
// Get current image information
// ============================================================

if (nImages == 0) {
    imagePath = File.openDialog("No image is open - choose a calibration image");
    if (imagePath == "") exit("No calibration image selected.");
    open(imagePath);
}

originalImageID = getImageID();
imageTitle = getTitle();
imageDir = getDirectory("image");

getPixelSize(unit, pixelWidth, pixelHeight);

screenText = getScreenSizeText();
screenParts = split(screenText, "|");
screenW = parseInt(screenParts[0]);
screenH = parseInt(screenParts[1]);

layoutTop = 35;
layoutGap = 12;
layoutImageW = 620;
layoutImageH = minOf(screenH - 90, 760);
layoutThresholdW = 430;
layoutPopupW = 570;

// Compress the layout on smaller displays while preserving the same order.
if (screenW < 1750) layoutImageW = 520;
if (screenW < 1500) layoutImageW = 440;

layoutImageX = 8;
layoutThresholdX = layoutImageX + layoutImageW + layoutGap;
layoutPopupX = layoutThresholdX + layoutThresholdW + layoutGap;
if (layoutPopupX + layoutPopupW > screenW)
    layoutPopupX = maxOf(layoutThresholdX + 260, screenW - layoutPopupW - 8);


// ============================================================
// Main profile dialog
// ============================================================

Dialog.create("RONUM Calibration v1.0.0");

Dialog.addString("Calibration Profile:", "Profile name");

Dialog.addMessage("Scale options:");
Dialog.addCheckbox("Set/overwrite image scale for scans", true);
Dialog.addNumber("Scale pixels per mm:", 47.22);

Dialog.addMessage("Optional leaf detection calibration:");
Dialog.addCheckbox("Calibrate leaf detection parameters", true);

Dialog.addMessage("Pustule threshold helper:");
Dialog.addCheckbox("Open representative ROI for live Color Threshold tuning", true);

Dialog.addMessage("Pustule size calibration:");
Dialog.addCheckbox("Measure smallest viable pustule", true);
Dialog.addCheckbox("Measure largest single pustule / cluster threshold", true);

Dialog.addHelp(
    "<html><h2>RONUM calibration setup</h2>" +
    "<h3>Calibration Profile</h3>" +
    "<p>This is the name of the CSV settings file created by calibration. Use a short, meaningful name; unsupported filename characters are replaced automatically.</p>" +
    "<h3>Image scale</h3>" +
    "<p><b>Set/overwrite image scale</b> converts pixel measurements to millimetres. Keep this enabled for scans made at a known, consistent resolution. The default 47.22 pixels/mm corresponds to 1200 dpi.</p>" +
    "<p>Disable it only when the open images already contain a correct spatial scale.</p>" +
    "<h3>Leaf detection calibration</h3>" +
    "<p>Defines how RONUM separates leaf tissue from the background. This is recommended when images contain multiple leaves or surrounding plate/background area.</p>" +
    "<h3>Pustule threshold helper</h3>" +
    "<p>Opens ImageJ Color Threshold on a representative region and imports the final HSB values automatically. Keep the colour space set to HSB.</p>" +
    "<h3>Pustule size calibration</h3>" +
    "<p>The smallest viable pustule provides an optional lower particle-area cutoff for excluding debris. The largest single pustule provides an optional threshold above which detections can be flagged as probable clusters.</p>" +
    "<p>These size measurements are stored in the calibration profile and can be enabled or disabled later in the quantification macro.</p></html>"
);

Dialog.show();

profileName = Dialog.getString();
profileName = cleanName(profileName);

overwriteScale = Dialog.getCheckbox();
scanPixelsPerMM = Dialog.getNumber();

calibrateLeafDetection = Dialog.getCheckbox();
useThresholdHelper = Dialog.getCheckbox();

measureSmall = Dialog.getCheckbox();
measureLarge = Dialog.getCheckbox();

if (profileName == "") exit("Profile name cannot be blank.");

// Apply scale before any mm2-based leaf-size calibration.
// Without this, minimum leaf area in mm2 behaves like pixels on unscaled scans.
if (overwriteScale) {
    run("Set Scale...", "distance=" + scanPixelsPerMM + " known=1 unit=mm");
}

getPixelSize(unit, pixelWidth, pixelHeight);

settingsPath = SETTINGS_DIR + profileName + ".csv";


// ============================================================
// Overwrite existing profile if confirmed
// ============================================================

if (File.exists(settingsPath)) {

    overwrite = getBoolean(
        "Settings profile already exists:\n\n" +
        settingsPath +
        "\n\nOverwrite this profile?"
    );

    if (!overwrite) {
        exit("Calibration cancelled. Existing profile was not overwritten.");
    }

    File.delete(settingsPath);
}


// ============================================================
// Optional leaf detection calibration
// ============================================================

leafHMin = 0;
leafHMax = 255;
leafHPass = true;
leafSMin = 0;
leafSMax = 255;
leafSPass = true;
leafBMin = 0;
leafBMax = 255;
leafBPass = true;
leafFillHoles = true;
leafSmoothMask = true;
leafSmoothRadiusPx = 5;
leafMinAreaMM2 = 25;
leafMaxAreaMM2 = 0;
leafMinCircularity = 0.00;
leafExpectedCount = 0;
leafMaxCount = 20;
leafRemoveBackgroundDefault = true;
leafColorSpace = "HSB";
leafThresholdMethod = "Default";
leafDarkBackground = true;
leafThresholdDisplay = "Red";

if (calibrateLeafDetection) {

    selectImage(originalImageID);
    positionCurrentImage(layoutImageX, layoutTop, layoutImageW, layoutImageH);
    setTool("rectangle");

    showInstruction(
        "Select calibration replicate",
        "Here we will select what a replicate looks like for calibration.\n\n" +
        "Using the RECTANGLE tool, select a broad region typical of a single replicate.\n\n" +
        "It is advised to have several images open spanning the phenotypes in the experiment.\n" +
        "Only this ROI will be shown in the threshold preview.\n\n" +
        "Click OK when the ROI is ready.",
        ROI_GUIDE,
        layoutPopupX, layoutTop
    );

    if (selectionType() == -1) {
        exit("No representative leaf ROI was selected.");
    }

    run("Duplicate...", "title=RONUM_leaf_threshold_preview");
    leafPreviewID = getImageID();

    // Keep a pristine copy because Color Threshold can leave its red preview
    // rendered into the working image when the operator finishes.
    run("Duplicate...", "title=RONUM_leaf_threshold_original");
    leafPristineID = getImageID();
    selectImage(leafPreviewID);
    positionCurrentImage(layoutImageX, layoutTop, layoutImageW, layoutImageH);

    run("Color Threshold...");
    wait(150);
    positionColorThresholdWindow(layoutThresholdX, layoutTop);
    showOriginalInColorThreshold();
    setTool("oval");

    showInstruction(
        "Leaf detection calibration",
        "Calibrate leaf detection using several images spanning the phenotypes in the experiment.\n\n" +
        "1) Select a small healthy leaf region and press Sample.\n" +
        "2) Check that the leaf is shown in red and that most background remains unselected. Some noise is fine.\n" +
        "3) To refine, press Select, hold Shift, add missed leaf regions, then press Sample again.\n" +
        "4) Repeat until satisfied, then click OK.\n\n" +
        "Press Original to restart. Keep Color space set to HSB. RONUM imports the final settings automatically.",
        LEAF_GUIDE,
        layoutPopupX, layoutTop
    );

    leafImported = readColorThresholdSettings();
    closeColorThresholdWindow();
    leafParts = split(leafImported, "|");
    if (leafParts.length != 13)
        exit("Could not import the leaf Color Threshold settings. Returned: " + leafImported);

    leafColorSpace = leafParts[0];
    leafThresholdMethod = leafParts[1];
    leafDarkBackground = trueTextToBool(leafParts[2]);
    leafThresholdDisplay = leafParts[3];
    leafHMin = parseInt(leafParts[4]);
    leafHMax = parseInt(leafParts[5]);
    leafHPass = passTextToBool(leafParts[6]);
    leafSMin = parseInt(leafParts[7]);
    leafSMax = parseInt(leafParts[8]);
    leafSPass = passTextToBool(leafParts[9]);
    leafBMin = parseInt(leafParts[10]);
    leafBMax = parseInt(leafParts[11]);
    leafBPass = passTextToBool(leafParts[12]);

    if (leafColorSpace != "HSB")
        exit("RONUM requires HSB Color Threshold settings for leaf detection. Color space was set to: " + leafColorSpace + ". Re-run calibration and select HSB.");

    // Discard the colour-threshold preview and continue from the untouched copy.
    selectImage(leafPreviewID);
    setOption("Changes", false);
    close();
    selectImage(leafPristineID);
    rename("RONUM_leaf_threshold_preview");
    leafPreviewID = getImageID();

    Dialog.create("RONUM leaf mask settings");
    Dialog.addMessage(
        "Imported leaf threshold: H " + leafHMin + "-" + leafHMax + " " + leafParts[6] +
        ", S " + leafSMin + "-" + leafSMax + " " + leafParts[9] +
        ", B " + leafBMin + "-" + leafBMax + " " + leafParts[12] + "."
    );
    Dialog.addMessage("Leaf object filtering / sanity checks:");
    Dialog.addCheckbox("Fill holes in leaf mask", true);
    Dialog.addCheckbox("Smooth leaf mask", true);
    Dialog.addNumber("Leaf smoothing radius px:", 5);
    Dialog.addNumber("Minimum leaf area mm2:", 25);
    Dialog.addNumber("Maximum leaf area mm2, 0 = no maximum:", 0);
    Dialog.addNumber("Minimum leaf circularity:", 0.00);
    Dialog.addNumber("Expected leaves, 0 = detect all:", 0);
    Dialog.addNumber("Maximum leaves to quantify:", 20);
    Dialog.addCheckbox("Default: remove background outside detected leaf", true);

    Dialog.addHelp(
        "<html><h2>Leaf mask settings</h2>" +
        "<h3>Imported HSB threshold</h3>" +
        "<p>The Hue, Saturation and Brightness limits and their Pass/Stop states were imported automatically from ImageJ Color Threshold.</p>" +
        "<p><b>Pass</b> includes pixels inside the stated range. <b>Stop</b> includes pixels outside the stated range.</p>" +
        "<h3>Fill holes</h3>" +
        "<p>Fills enclosed gaps inside detected leaf objects. This is useful where disease, glare or veins create holes in an otherwise continuous leaf mask.</p>" +
        "<h3>Smooth leaf mask</h3>" +
        "<p>Applies a median filter to reduce jagged boundaries and small defects before the binary leaf mask is rebuilt. Larger radii produce stronger smoothing and may merge nearby objects.</p>" +
        "<h3>Leaf area limits</h3>" +
        "<p><b>Minimum leaf area</b> removes small background detections. <b>Maximum leaf area</b> can reject implausibly large merged objects; enter 0 for no upper limit.</p>" +
        "<h3>Circularity and leaf counts</h3>" +
        "<p>Minimum circularity can reject very irregular objects, but should usually remain at 0 for long leaf strips.</p>" +
        "<p>Expected leaves is a sanity check. Maximum leaves limits how many detected objects are quantified.</p>" +
        "<h3>Remove background</h3>" +
        "<p>When enabled by default, downstream disease measurements are restricted to the detected leaf region.</p></html>"
    );

    Dialog.show();

    leafFillHoles = Dialog.getCheckbox();
    leafSmoothMask = Dialog.getCheckbox();
    leafSmoothRadiusPx = Dialog.getNumber();
    leafMinAreaMM2 = Dialog.getNumber();
    leafMaxAreaMM2 = Dialog.getNumber();
    leafMinCircularity = Dialog.getNumber();
    leafExpectedCount = Dialog.getNumber();
    leafMaxCount = Dialog.getNumber();
    leafRemoveBackgroundDefault = Dialog.getCheckbox();

    if (leafHMax <= leafHMin) exit("Leaf hue max must be greater than leaf hue min.");
    if (leafSMax <= leafSMin) exit("Leaf saturation max must be greater than leaf saturation min.");
    if (leafBMax <= leafBMin) exit("Leaf brightness max must be greater than leaf brightness min.");

    // Build and test leaf mask on preview image
    selectImage(leafPreviewID);
    run("Duplicate...", "title=RONUM_leaf_hsb_work");
    leafHSBID = getImageID();
    run("HSB Stack");

    setSlice(1);
    run("Duplicate...", "title=RONUM_leaf_H_mask");
    leafHMaskID = getImageID();
    setThreshold(leafHMin, leafHMax);
    setOption("BlackBackground", true);
    run("Convert to Mask");
    if (!leafHPass) run("Invert");
    leafHMaskTitle = getTitle();

    selectImage(leafHSBID);
    setSlice(2);
    run("Duplicate...", "title=RONUM_leaf_S_mask");
    leafSMaskID = getImageID();
    setThreshold(leafSMin, leafSMax);
    setOption("BlackBackground", true);
    run("Convert to Mask");
    if (!leafSPass) run("Invert");
    leafSMaskTitle = getTitle();

    selectImage(leafHSBID);
    setSlice(3);
    run("Duplicate...", "title=RONUM_leaf_B_mask");
    leafBMaskID = getImageID();
    setThreshold(leafBMin, leafBMax);
    setOption("BlackBackground", true);
    run("Convert to Mask");
    if (!leafBPass) run("Invert");
    leafBMaskTitle = getTitle();

    imageCalculator("AND create", leafHMaskTitle, leafSMaskTitle);
    rename("RONUM_leaf_HS_mask");
    leafHSMaskID = getImageID();
    leafHSMaskTitle = getTitle();

    imageCalculator("AND create", leafHSMaskTitle, leafBMaskTitle);
    rename("RONUM_leaf_detection_mask");
    leafMaskID = getImageID();

    selectImage(leafMaskID);
    if (leafFillHoles) run("Fill Holes");
    if (leafSmoothMask) {
        run("Median...", "radius=" + leafSmoothRadiusPx);
        setThreshold(128, 255);
        setOption("BlackBackground", true);
        run("Convert to Mask");
    }

    if (isOpen("Results")) {
        selectWindow("Results");
        run("Close");
    }
    if (isOpen("ROI Manager")) {
        roiManager("Reset");
    }

   // Analyze Particles uses calibrated area units when image scale is set.
// Therefore use mm2 values directly here.
if (leafMaxAreaMM2 > 0) {
    leafSizeString = d2s(leafMinAreaMM2, 3) + "-" + d2s(leafMaxAreaMM2, 3);
} else {
    leafSizeString = d2s(leafMinAreaMM2, 3) + "-Infinity";
}

    run("Set Measurements...", "area centroid redirect=None decimal=6");
    run("Analyze Particles...", "size=" + leafSizeString + " circularity=" + leafMinCircularity + "-1.00 display clear add");

    detectedLeafCount = roiManager("count");

    selectImage(leafPreviewID);
    run("Duplicate...", "title=RONUM_leaf_detection_QC");
    leafQCID = getImageID();
    Overlay.clear;

    if (detectedLeafCount > 0) {
        nShow = detectedLeafCount;
        if (leafMaxCount > 0 && nShow > leafMaxCount) nShow = leafMaxCount;

        for (li = 0; li < nShow; li++) {
            roiManager("Select", li);
            selectImage(leafQCID);
            roiManager("Select", li);
            Overlay.addSelection("cyan", 8);
            xC = getResult("X", li);
            yC = getResult("Y", li);
            makeText(d2s(li + 1, 0), xC, yC);
            Overlay.addSelection("yellow", 1);
            run("Select None");
        }
    }

    Overlay.show;

    approvalText =
        "Detected leaf objects: " + detectedLeafCount + "\n\n" +
        "Expected leaves: " + leafExpectedCount + "\n" +
        "Maximum leaves: " + leafMaxCount + "\n\n" +
        "Approve these leaf-detection settings?";

    if (leafExpectedCount > 0 && detectedLeafCount != leafExpectedCount) {
        approvalText =
            "WARNING: detected leaf count does not match expected count.\n\n" +
            approvalText;
    }

    okLeafCalibration = getBoolean(approvalText);

    if (!okLeafCalibration) {
        exit("Leaf detection calibration cancelled. Adjust leaf threshold/settings and re-run calibration.");
    }

    // Close temporary leaf calibration windows except QC/preview for inspection
    selectImage(leafHSBID); setOption("Changes", false); close();
    selectImage(leafHMaskID); setOption("Changes", false); close();
    selectImage(leafSMaskID); setOption("Changes", false); close();
    selectImage(leafBMaskID); setOption("Changes", false); close();
    selectImage(leafHSMaskID); setOption("Changes", false); close();
    selectImage(leafMaskID); setOption("Changes", false); close();
}


// ============================================================
// Optional threshold helper
// ============================================================

pustuleColorSpace = "HSB";
pustuleThresholdMethod = "Default";
pustuleDarkBackground = true;
pustuleThresholdDisplay = "Red";
hMin = 17;
hMax = 244;
hPass = false;
sMin = 68;
sMax = 249;
sPass = true;
bMin = 108;
bMax = 255;
bPass = true;

if (useThresholdHelper) {

    selectImage(originalImageID);
    positionCurrentImage(layoutImageX, layoutTop, layoutImageW, layoutImageH);

    setTool("rectangle");

    showInstruction(
        "Select calibration replicate",
        "Here we will select what a replicate looks like for calibration.\n\n" +
        "Using the RECTANGLE tool, select a broad region typical of one replicate and containing representative disease.\n\n" +
        "It is advised to have several images open spanning the phenotypes in the experiment.\n" +
        "Only this ROI will be shown in the threshold preview.\n\n" +
        "Click OK when the ROI is ready.",
        ROI_GUIDE,
        layoutPopupX, layoutTop
    );

    if (selectionType() == -1) {
        exit("No representative ROI was selected.");
    }

    run("Duplicate...", "title=RONUM_threshold_preview");
    pustulePreviewID = getImageID();

    // Keep a pristine copy so the red Color Threshold preview is never used
    // as an analysis image or left behind as the apparent source image.
    run("Duplicate...", "title=RONUM_threshold_original");
    pustulePristineID = getImageID();
    selectImage(pustulePreviewID);
    positionCurrentImage(layoutImageX, layoutTop, layoutImageW, layoutImageH);

    run("Color Threshold...");
    wait(150);
    positionColorThresholdWindow(layoutThresholdX, layoutTop);
    showOriginalInColorThreshold();
    setTool("oval");

    showInstruction(
        "Pustule detection calibration",
        "Calibrate disease detection using several images spanning the phenotypes in the experiment.\n\n" +
        "1) Use the oval tool to select about half a pustule, then press Sample.\n" +
        "2) Press Select to make the current threshold editable.\n" +
        "3) Hold Shift and add small regions missed by the current selection. Press Sample to preview.\n" +
        "4) Repeat gradually across several pustules.\n" +
        "5) Click OK when the full disease area is captured with minimal healthy tissue or background.\n\n" +
        "Press Original to restart. Keep Color space set to HSB. RONUM imports the final settings automatically.\n\n" +
        "Note: small particles and debris are easily filtered. Accurate pustule area is most important.",
        PUSTULE_GUIDE,
        layoutPopupX, layoutTop
    );

    pustuleImported = readColorThresholdSettings();
    closeColorThresholdWindow();
    pustuleParts = split(pustuleImported, "|");
    if (pustuleParts.length != 13)
        exit("Could not import the pustule Color Threshold settings. Returned: " + pustuleImported);

    pustuleColorSpace = pustuleParts[0];
    pustuleThresholdMethod = pustuleParts[1];
    pustuleDarkBackground = trueTextToBool(pustuleParts[2]);
    pustuleThresholdDisplay = pustuleParts[3];
    hMin = parseInt(pustuleParts[4]);
    hMax = parseInt(pustuleParts[5]);
    hPass = passTextToBool(pustuleParts[6]);
    sMin = parseInt(pustuleParts[7]);
    sMax = parseInt(pustuleParts[8]);
    sPass = passTextToBool(pustuleParts[9]);
    bMin = parseInt(pustuleParts[10]);
    bMax = parseInt(pustuleParts[11]);
    bPass = passTextToBool(pustuleParts[12]);

    if (pustuleColorSpace != "HSB")
        exit("RONUM requires HSB Color Threshold settings for pustule detection. Color space was set to: " + pustuleColorSpace + ". Re-run calibration and select HSB.");

    // Restore the untouched representative region automatically.
    selectImage(pustulePreviewID);
    setOption("Changes", false);
    close();
    selectImage(pustulePristineID);
    rename("RONUM_threshold_preview");
    pustulePreviewID = getImageID();

    Dialog.create("Pustule threshold imported");
    Dialog.addMessage(
        "Color space: " + pustuleColorSpace + "\n" +
        "Method: " + pustuleThresholdMethod + "\n" +
        "Dark background: " + boolText(pustuleDarkBackground) + "\n" +
        "Threshold display: " + pustuleThresholdDisplay + "\n\n" +
        "Hue: " + hMin + "-" + hMax + " " + pustuleParts[6] + "\n" +
        "Saturation: " + sMin + "-" + sMax + " " + pustuleParts[9] + "\n" +
        "Brightness: " + bMin + "-" + bMax + " " + pustuleParts[12]
    );
    Dialog.addHelp(
        "<html><h2>Imported pustule threshold</h2>" +
        "<p>RONUM has copied the final settings directly from ImageJ Color Threshold.</p>" +
        "<p><b>Hue</b> mainly distinguishes colours. <b>Saturation</b> distinguishes vivid colours from grey or pale pixels. <b>Brightness</b> distinguishes light from dark pixels.</p>" +
        "<p><b>Pass</b> includes values within the displayed range. <b>Stop</b> includes values outside that range.</p>" +
        "<p>The thresholding method and Dark background setting affect automatic threshold suggestions. The final numeric HSB ranges and Pass/Stop states are what RONUM uses for quantification.</p>" +
        "<p>The threshold display colour changes only the preview appearance and does not alter the saved segmentation limits.</p></html>"
    );
    Dialog.show();
}

if (hMax <= hMin) exit("Hue max must be greater than hue min.");
if (sMax <= sMin) exit("Saturation max must be greater than saturation min.");
if (bMax <= bMin) exit("Brightness max must be greater than brightness min.");


// ============================================================
// Return to original image for pustule calibration
// ============================================================

selectImage(originalImageID);
run("Select None");


// ============================================================
// Measure smallest viable pustule
// ============================================================

smallArea = 0;

if (measureSmall) {

    setTool("oval");

    waitForUser(
        "Smallest viable pustule",
        "Use the oval tool to circle the smallest object you\n" +
        "would still accept as a real pustule.\n\n" +
        "This defines the optional lower cutoff for debris and\n" +
        "very small detections. If uncertain, select a region\n" +
        "about 50% the size of the smallest pustule in a\n" +
        "representative image or image set.\n\n" +
        "Press OK without a selection to skip this measurement."
    );

    if (selectionType() != -1) {
        run("Measure");
        smallArea = getResult("Area", nResults - 1);
        roiManager("Add");
        run("Select None");
    } else {
        smallArea = 0;
        measureSmall = false;
    }
}


// ============================================================
// Measure largest single pustule / cluster threshold
// ============================================================

largeArea = 0;

if (measureLarge) {

    run("Select None");
    setTool("oval");

    waitForUser(
        "Largest single pustule",
        "Use the oval tool to circle the largest object you\n" +
        "would still consider ONE single pustule.\n\n" +
        "This defines the optional upper cutoff separating\n" +
        "single pustules from clusters. If uncertain, select a\n" +
        "region slightly larger than the largest single pustule\n" +
        "in a representative image or image set.\n\n" +
        "Do not choose a clear cluster. Press OK without a\n" +
        "selection to skip this measurement."
    );

    if (selectionType() != -1) {
        run("Measure");
        largeArea = getResult("Area", nResults - 1);
        roiManager("Add");
        run("Select None");
    } else {
        largeArea = 0;
        measureLarge = false;
    }
}


// ============================================================
// Derived size thresholds
// ============================================================

smallFilterArea = smallArea;
largeFlagArea = largeArea;


// ============================================================
// Summary confirmation
// ============================================================

summary =
    "RONUM calibration profile:\n\n" +
    "Profile: " + profileName + "\n" +
    "Image: " + imageTitle + "\n\n" +

    "Leaf detection enabled: " + boolText(calibrateLeafDetection) + "\n" +
    "Leaf min area mm2: " + d2s(leafMinAreaMM2, 3) + "\n" +
    "Leaf max area mm2: " + d2s(leafMaxAreaMM2, 3) + "\n" +
    "Expected leaves: " + d2s(leafExpectedCount, 0) + "\n\n" +

    "Scale unit: " + unit + "\n" +
    "Pixel width: " + pixelWidth + "\n" +
    "Pixel height: " + pixelHeight + "\n\n" +

    "HSB threshold:\n" +
    "H: " + hMin + "-" + hMax + " Pass=" + boolText(hPass) + "\n" +
    "S: " + sMin + "-" + sMax + " Pass=" + boolText(sPass) + "\n" +
    "B: " + bMin + "-" + bMax + " Pass=" + boolText(bPass) + "\n\n" +

    "Smallest viable pustule area: " + d2s(smallArea, 3) + "\n" +
    "Largest single pustule area: " + d2s(largeArea, 3) + "\n\n" +

    "Small-particle filter area: " + d2s(smallFilterArea, 3) + "\n" +
    "Large-particle flag area: " + d2s(largeFlagArea, 3) + "\n\n" +

    "Click OK to save this profile.";

Dialog.create("RONUM calibration summary");
Dialog.addMessage(summary);
Dialog.addHelp(
    "<html><h2>Calibration summary</h2>" +
    "<p>This window lists the settings that will be written to the calibration-profile CSV.</p>" +
    "<p>The profile stores the leaf threshold and leaf-mask parameters, pustule HSB threshold, spatial scale and optional particle-size limits.</p>" +
    "<p>Quantification settings such as Fill Holes, Despeckle, Watershed, output images and filename rules are selected separately in the quantification macro.</p>" +
    "<p>Click OK to save. If a value is clearly wrong, cancel the macro and repeat calibration rather than editing the CSV manually.</p></html>"
);
Dialog.show();


// ============================================================
// Save settings CSV
// ============================================================

File.append("setting,value\n", settingsPath);

appendSetting(settingsPath, "tool_name", "RONUM");
appendSetting(settingsPath, "tool_long_name", "Semi-automated ImageJ/Fiji macro for cereal rust disease quantification");
appendSetting(settingsPath, "calibration_macro_version", "1.0.0");

appendSetting(settingsPath, "profile_name", profileName);

appendSetting(settingsPath, "calibration_image", imageTitle);
appendSetting(settingsPath, "calibration_image_directory", imageDir);

appendSetting(settingsPath, "overwrite_scale", boolText(overwriteScale));
appendSetting(settingsPath, "scan_pixels_per_mm", scanPixelsPerMM);
appendSetting(settingsPath, "scale_unit", unit);
appendSetting(settingsPath, "pixel_width", pixelWidth);
appendSetting(settingsPath, "pixel_height", pixelHeight);

appendSetting(settingsPath, "leaf_detection_enabled", boolText(calibrateLeafDetection));
appendSetting(settingsPath, "leaf_color_space", leafColorSpace);
appendSetting(settingsPath, "leaf_threshold_method", leafThresholdMethod);
appendSetting(settingsPath, "leaf_dark_background", boolText(leafDarkBackground));
appendSetting(settingsPath, "leaf_threshold_display", leafThresholdDisplay);
appendSetting(settingsPath, "leaf_h_min", leafHMin);
appendSetting(settingsPath, "leaf_h_max", leafHMax);
appendSetting(settingsPath, "leaf_h_pass", boolText(leafHPass));
appendSetting(settingsPath, "leaf_s_min", leafSMin);
appendSetting(settingsPath, "leaf_s_max", leafSMax);
appendSetting(settingsPath, "leaf_s_pass", boolText(leafSPass));
appendSetting(settingsPath, "leaf_b_min", leafBMin);
appendSetting(settingsPath, "leaf_b_max", leafBMax);
appendSetting(settingsPath, "leaf_b_pass", boolText(leafBPass));
appendSetting(settingsPath, "leaf_fill_holes", boolText(leafFillHoles));
appendSetting(settingsPath, "leaf_smooth_mask", boolText(leafSmoothMask));
appendSetting(settingsPath, "leaf_smooth_radius_px", leafSmoothRadiusPx);
appendSetting(settingsPath, "leaf_min_area_mm2", leafMinAreaMM2);
appendSetting(settingsPath, "leaf_max_area_mm2", leafMaxAreaMM2);
appendSetting(settingsPath, "leaf_min_circularity", leafMinCircularity);
appendSetting(settingsPath, "leaf_expected_count", leafExpectedCount);
appendSetting(settingsPath, "leaf_max_count", leafMaxCount);
appendSetting(settingsPath, "leaf_remove_background_default", boolText(leafRemoveBackgroundDefault));

appendSetting(settingsPath, "pustule_color_space", pustuleColorSpace);
appendSetting(settingsPath, "pustule_threshold_method", pustuleThresholdMethod);
appendSetting(settingsPath, "pustule_dark_background", boolText(pustuleDarkBackground));
appendSetting(settingsPath, "pustule_threshold_display", pustuleThresholdDisplay);
appendSetting(settingsPath, "h_min", hMin);
appendSetting(settingsPath, "h_max", hMax);
appendSetting(settingsPath, "h_pass", boolText(hPass));

appendSetting(settingsPath, "s_min", sMin);
appendSetting(settingsPath, "s_max", sMax);
appendSetting(settingsPath, "s_pass", boolText(sPass));

appendSetting(settingsPath, "b_min", bMin);
appendSetting(settingsPath, "b_max", bMax);
appendSetting(settingsPath, "b_pass", boolText(bPass));

appendSetting(settingsPath, "min_viable_pustule_area", smallArea);
appendSetting(settingsPath, "max_single_pustule_area", largeArea);
appendSetting(settingsPath, "small_filter_area", smallFilterArea);
appendSetting(settingsPath, "large_flag_area", largeFlagArea);

appendSetting(settingsPath, "small_pustule_measured", boolText(measureSmall));
appendSetting(settingsPath, "large_pustule_measured", boolText(measureLarge));

// Compatibility fields used by the quantification macro
appendSetting(settingsPath, "filter_small_particles", boolText(measureSmall));
appendSetting(settingsPath, "flag_large_particles", boolText(measureLarge));

print("Saved RONUM calibration profile:");
print(settingsPath);

showMessage(
    "RONUM calibration saved",
    "Saved profile:\n\n" + settingsPath
);
