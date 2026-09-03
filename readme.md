# Tyrant Unleashed XML Visualizer

A PowerShell utility designed to track, parse, and visualize balancing changes between XML asset files for the collectible card game *Tyrant Unleashed*.

It automatically fetches the latest card definitions, compares them against archived versions, and generates both an interactive HTML changelog and high-resolution JPG images of all updated units.

## Features

* **Automated Data Retrieval**: Downloads the latest `cards_section_*.xml` files (sections 1–21) and `skills_set.xml` directly from game assets.
* **Smart XML Rotation**: Automatically archives existing data into `XML-old` before saving fresh updates to `XML-new`.
* **Dynamic Parsing**: Resolves dynamic skills, triggers, card factions, and summoned unit stats (`fusion_level 2` / Quad units).
* **Visually Appealing HTML Output**: Generates `Changelog.html` featuring custom CSS styling, color-coded card rarities, and side-by-side stat diffs.
* **Automated Image Rendering & Cropping**: Uses a headless Chromium browser (Microsoft Edge or Google Chrome) to render screenshots of individual modified cards and automatically crops background padding using C# `System.Drawing`.

## Prerequisites

* **Operating System**: Windows 10 / 11 / Linux / macOS
* **PowerShell**: Version 7.0 or higher (PowerShell Core recommended)
* **Browser**: Microsoft Edge or Google Chrome (required for headless JPG screenshot generation)
* **Local Images**: Local card artwork images stored inside the `images/` folder (PNG or JPG formats).

## Folder Structure

TU_XML_visualizer/
|-- images/          # Local card illustration assets
|-- XML-new/         # Store location for the latest downloaded XMLs
|-- XML-old/         # Archived XML files from previous runs
|-- visualize.ps1    # Main PowerShell script
`-- Changelog.html   # Generated HTML changelog report

## Configuration

> **Important**: Before running the script for the first time, open `visualize.ps1` and update the `$BaseDir` variable at the top of the file to match your local project path:
>
> `$BaseDir = "C:\Users\Bob\Desktop\changeme"`

## Usage

1. Open PowerShell 7+ and navigate to the project directory:
   cd "C:\Path\To\TU_XML_visualizer"

2. Execute the script:
   .\visualize.ps1

3. Once complete, view the rendered report in your browser by opening `Changelog.html` or inspect the newly generated cropped `.jpg` images directly in the root directory.

## License

Distributed under the MIT License. Feel free to modify and adapt for personal use.