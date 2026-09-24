# =========================================================================
# DIRECTORY DEFINITIONS & ASSEMBLY LOADING
# =========================================================================
Add-Type -AssemblyName System.Drawing

$BaseDir      = "C:\Users\Bob\Desktop\changeme"
$OldDir       = Join-Path $BaseDir "XML-old"
$NewDir       = Join-Path $BaseDir "XML-new"
$PicturesDir  = Join-Path $BaseDir "images"
$HtmlOutput   = Join-Path $BaseDir "Changelog.html"
# =========================================================================

if (-not (Test-Path $OldDir)) { New-Item -ItemType Directory -Path $OldDir -Force | Out-Null }
if (-not (Test-Path $NewDir)) { New-Item -ItemType Directory -Path $NewDir -Force | Out-Null }

# STATIC RARITY LOOKUP MAP
$script:GlobalRarityMap = @{
    "1" = "Common"
    "2" = "Rare"
    "3" = "Epic"
    "4" = "Legendary"
    "5" = "Vindicator"
    "6" = "Mythic"
}

# -------------------------------------------------------------------------
# CROP FUNCTION FOR AUTOMATIC BORDER TRIMMING
# -------------------------------------------------------------------------
function Crop-Image ([string]$imagePath) {
    if (-not (Test-Path $imagePath)) { return }
    try {
        $bmp = [System.Drawing.Bitmap]::FromFile($imagePath)
        $bgColor = $bmp.GetPixel(0, 0)
        
        $minX = $bmp.Width
        $minY = $bmp.Height
        $maxX = 0
        $maxY = 0

        for ($y = 0; $y -lt $bmp.Height; $y += 3) {
            for ($x = 0; $x -lt $bmp.Width; $x += 3) {
                $pixel = $bmp.GetPixel($x, $y)
                $diff = [Math]::Abs([int]$pixel.R - [int]$bgColor.R) +
                        [Math]::Abs([int]$pixel.G - [int]$bgColor.G) +
                        [Math]::Abs([int]$pixel.B - [int]$bgColor.B)
                if ($diff -gt 12) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }

        if ($maxX -gt $minX -and $maxY -gt $minY) {
            $padding = 12
            $cropX = [Math]::Max(0, $minX - $padding)
            $cropY = [Math]::Max(0, $minY - $padding)
            $cropW = [Math]::Min($bmp.Width - $cropX, ($maxX - $minX) + ($padding * 2))
            $cropH = [Math]::Min($bmp.Height - $cropY, ($maxY - $minY) + ($padding * 2))

            $rect = [System.Drawing.Rectangle]::new($cropX, $cropY, $cropW, $cropH)
            $croppedBmp = $bmp.Clone($rect, $bmp.PixelFormat)
            $bmp.Dispose()
            $croppedBmp.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $croppedBmp.Dispose()
        } else {
            $bmp.Dispose()
        }
    } catch {
        Write-Warning "Could not crop image ${imagePath}: $_"
    }
}

# -------------------------------------------------------------------------
# STEP 1: ROTATE EXISTING XMLs FROM NEW TO OLD
# -------------------------------------------------------------------------
Write-Host "Archiving existing XML files from 'XML-new' to 'XML-old'..." -ForegroundColor Yellow
$existingNewFiles = Get-ChildItem -Path $NewDir -Filter "*.xml"

foreach ($file in $existingNewFiles) {
    $targetPath = Join-Path $OldDir $file.Name
    Move-Item -Path $file.FullName -Destination $targetPath -Force
}

# -------------------------------------------------------------------------
# STEP 2: DOWNLOAD FRESH XML FILES
# -------------------------------------------------------------------------
Write-Host "Downloading latest XML sections (1-21) & skills_set.xml..." -ForegroundColor Cyan
$ProgressPreference = 'SilentlyContinue'

$skillsSetUrl  = "http://mobile.tyrantonline.com/assets/skills_set.xml"
$skillsSetPath = Join-Path $NewDir "skills_set.xml"
try {
    Invoke-WebRequest -Uri $skillsSetUrl -OutFile $skillsSetPath -UseBasicParsing
    Write-Host " Fetched: skills_set.xml" -ForegroundColor Gray
} catch {
    Write-Warning "Failed to download skills_set.xml from ${skillsSetUrl}: ${_}"
}

for ($i = 1; $i -le 21; $i++) {
    $fileName = "cards_section_$i.xml"
    $url      = "http://mobile.tyrantonline.com/assets/$fileName"
    $destPath = Join-Path $NewDir $fileName
    
    Write-Host " Fetching: $fileName" -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
    } catch {
        Write-Warning "Failed to download $fileName from ${url}: ${_}"
    }
}

# -------------------------------------------------------------------------
# STEP 3: PARSE SKILLS_SET.XML
# -------------------------------------------------------------------------
$script:GlobalSkillsMap   = @{}
$script:GlobalFactionsMap = @{}

if (Test-Path $skillsSetPath) {
    Write-Host "Parsing skills_set.xml for dynamic skills & factions..." -ForegroundColor Cyan
    [xml]$skillsXml = Get-Content -Path $skillsSetPath
    
    foreach ($unitType in $skillsXml.root.unitType) {
        $fId   = $unitType.id.ToString()
        $fName = $unitType.name.ToString()
        $script:GlobalFactionsMap[$fId] = $fName
    }

    foreach ($skillDef in $skillsXml.root.skillType) {
        $id = $skillDef.id.ToString()
        $script:GlobalSkillsMap[$id] = @{
            Name        = if ($skillDef.name) { $skillDef.name.ToString() } else { $id }
            DefaultTrig = if ($skillDef.trigger) { $skillDef.trigger.ToString() } else { $null }
        }
    }
} else {
    Write-Warning "skills_set.xml not found! Fallback to raw IDs."
}

function Get-PicturePath ([string]$picName, [string]$baseDir) {
    if ([string]::IsNullOrWhiteSpace($picName)) { return $null }
    $directPath = Join-Path $baseDir $picName
    if (Test-Path $directPath) { return $directPath }
    
    $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($picName)
    $png = Join-Path $baseDir "$cleanName.png"
    $jpg = Join-Path $baseDir "$cleanName.jpg"
    
    if (Test-Path $png) { return $png }
    if (Test-Path $jpg) { return $jpg }
    return $null
}

function Format-SkillText ($s, [hashtable]$idMap) {
    $id = $s.id.ToString()
    $meta = $script:GlobalSkillsMap[$id]
    $name = if ($meta -and $meta.Name) { $meta.Name } else { $id }

    if ($id -eq "summon") {
        $targetId = $s.card_id.ToString()
        $targetName = if ($idMap.ContainsKey($targetId)) { $idMap[$targetId].Name } else { "Card #$targetId" }
        $trigText = if ($s.trigger -eq "death") { "on Death" } else { "on Play" }
        return "Summon $targetName ($trigText)"
    }

    if ($id -eq "flurry") {
        $shots = if ($s.x) { $s.x } elseif ($s.c) { $s.c } else { "1" }
        $str = "$name $shots"
        if ($s.c -and $s.x -and $s.c -ne $s.x) { $str += " every $($s.c)" }
        return $str
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($name)

    if ($s.n) { $parts.Add($s.n.ToString()) }
    if ($s.all -eq "1" -or $s.all -eq "true") { $parts.Add("All") }

    if ($s.s) {
        $s1Meta = $script:GlobalSkillsMap[$s.s.ToString()]
        $s1Name = if ($s1Meta -and $s1Meta.Name) { $s1Meta.Name } else { $s.s }
        if ($s.s2) {
            $s2Meta = $script:GlobalSkillsMap[$s.s2.ToString()]
            $s2Name = if ($s2Meta -and $s2Meta.Name) { $s2Meta.Name } else { $s.s2 }
            $parts.Add("[$s1Name -> $s2Name]")
        } else {
            $parts.Add("[$s1Name]")
        }
    }

    if ($s.y) {
        $yRaw = $s.y.ToString()
        $factionName = if ($script:GlobalFactionsMap.ContainsKey($yRaw)) { $script:GlobalFactionsMap[$yRaw] } else { $yRaw }
        $parts.Add("[$factionName]")
    }

    if ($s.x) { $parts.Add($s.x.ToString()) }
    if ($s.c) { $parts.Add("every $($s.c)") }

    $resultString = $parts -join " "

    $triggerVal = if ($s.trigger) { $s.trigger.ToString() } else { if ($meta) { $meta.DefaultTrig } else { $null } }
    if ($triggerVal -and $triggerVal -ne "activate") {
        $trigFormatted = $triggerVal.Substring(0,1).ToUpper() + $triggerVal.Substring(1)
        $resultString += " (on $trigFormatted)"
    }

    return $resultString.Trim()
}

function Get-RarityName ([string]$rarityId) {
    if ([string]::IsNullOrWhiteSpace($rarityId)) { return "Common" }
    if ($script:GlobalRarityMap.ContainsKey($rarityId)) {
        return $script:GlobalRarityMap[$rarityId]
    }
    return "Common"
}

function Parse-UnitBlock ([string]$xmlBlock) {
    [xml]$xml = "<root>$xmlBlock</root>"
    $unit = $xml.root.unit

    $name     = $unit.name
    $attack   = if ($null -ne $unit.attack) { [int]$unit.attack } else { 0 }
    $health   = if ($null -ne $unit.health) { [int]$unit.health } else { 0 }
    $delay    = if ($null -ne $unit.cost)   { [int]$unit.cost } else { 0 }
    $typeId   = if ($unit.type) { $unit.type.ToString() } else { "0" }
    $rarityId = if ($unit.rarity) { $unit.rarity.ToString() } else { "1" }
    
    $skills = @()
    foreach ($s in $unit.skill) { $skills += Format-SkillText -s $s -idMap @{} }

    $upgrades = $unit.upgrade
    if ($upgrades) {
        foreach ($upg in $upgrades) {
            if ($upg.attack) { $attack = [int]$upg.attack }
            if ($upg.health) { $health = [int]$upg.health }
            if ($upg.cost)   { $delay  = [int]$upg.cost }
            if ($upg.type)   { $typeId = $upg.type.ToString() }
            if ($upg.skill) {
                $skills = @()
                foreach ($s in $upg.skill) { $skills += Format-SkillText -s $s -idMap @{} }
            }
        }
    }

    $finalPic = $unit.picture
    if ($upgrades) {
        $sortedUpg = $upgrades | Sort-Object { 
            $lvl = $_.level
            if ($null -ne $lvl) { [int]$lvl } else { 0 }
        } -Descending

        foreach ($u in $sortedUpg) {
            if ($u.picture -and -not [string]::IsNullOrWhiteSpace($u.picture)) {
                $finalPic = $u.picture
                break
            }
        }
    }

    $factionName = if ($script:GlobalFactionsMap.ContainsKey($typeId)) { $script:GlobalFactionsMap[$typeId] } else { "Faction #$typeId" }
    $rarityName  = Get-RarityName -rarityId $rarityId

    return @{
        Name    = $name
        Pic     = $finalPic
        Attack  = $attack
        Health  = $health
        Delay   = $delay
        Faction = $factionName
        Rarity  = $rarityName
        Skills  = $skills
        RawXml  = $xmlBlock
    }
}

function Build-GlobalCardMap ([string]$dirPath) {
    $idMap = @{}
    $files = Get-ChildItem -Path $dirPath -Filter "cards_section_*.xml"
    
    foreach ($file in $files) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $matches = [regex]::Matches($content, '(?si)<unit>(.*?)</unit>')
        
        foreach ($m in $matches) {
            $block = $m.Value
            [xml]$xml = "<root>$block</root>"
            $unit = $xml.root.unit
            $parsedStats = Parse-UnitBlock -xmlBlock $block

            if ($unit.id) { $idMap[ $unit.id.ToString() ] = $parsedStats }

            foreach ($upg in $unit.upgrade) {
                if ($upg.card_id) { $idMap[ $upg.card_id.ToString() ] = $parsedStats }
            }
        }
    }
    return $idMap
}

Write-Host "Initializing global card ID lookup tables..." -ForegroundColor Cyan
$GlobalCardMap = Build-GlobalCardMap -dirPath $NewDir

function Get-UnitStats ([string]$xmlBlock, [hashtable]$idMap) {
    [xml]$xml = "<root>$xmlBlock</root>"
    $unit = $xml.root.unit

    $name     = $unit.name
    $attack   = if ($null -ne $unit.attack) { [int]$unit.attack } else { 0 }
    $health   = if ($null -ne $unit.health) { [int]$unit.health } else { 0 }
    $delay    = if ($null -ne $unit.cost)   { [int]$unit.cost } else { 0 }
    $typeId   = if ($unit.type) { $unit.type.ToString() } else { "0" }
    $rarityId = if ($unit.rarity) { $unit.rarity.ToString() } else { "1" }

    $parseSkills = {
        param($skillList)
        $result = @()
        $summons = @()

        foreach ($s in $skillList) {
            if ($s.id -eq "summon") {
                $targetId = $s.card_id.ToString()
                $triggerText = if ($s.trigger -eq "death") { "on Death" } else { "on Play" }
                
                if ($idMap.ContainsKey($targetId)) {
                    $targetObj = $idMap[$targetId]
                    $summons += @{
                        Name    = $targetObj.Name
                        Pic     = $targetObj.Pic
                        Attack  = $targetObj.Attack
                        Health  = $targetObj.Health
                        Delay   = $targetObj.Delay
                        Faction = $targetObj.Faction
                        Rarity  = $targetObj.Rarity
                        Skills  = $targetObj.Skills
                        Trigger = $triggerText
                    }
                } else {
                    $summons += @{
                        Name    = "Card #$targetId"
                        Pic     = $null
                        Attack  = 0
                        Health  = 0
                        Delay   = 0
                        Faction = "Unknown"
                        Rarity  = "Common"
                        Skills  = @()
                        Trigger = $triggerText
                    }
                }
                $result += "Summon $($summons[-1].Name) ($triggerText)"
            } else {
                $result += Format-SkillText -s $s -idMap $idMap
            }
        }
        return @{ Skills = $result; Summons = $summons }
    }

    $parsed = &$parseSkills $unit.skill
    $skills = $parsed.Skills
    $summons = $parsed.Summons

    $upgrades = $unit.upgrade
    if ($upgrades) {
        foreach ($upg in $upgrades) {
            if ($upg.attack) { $attack = [int]$upg.attack }
            if ($upg.health) { $health = [int]$upg.health }
            if ($upg.cost)   { $delay  = [int]$upg.cost }
            if ($upg.type)   { $typeId = $upg.type.ToString() }
            if ($upg.skill) {
                $parsed = &$parseSkills $upg.skill
                $skills = $parsed.Skills
                $summons = $parsed.Summons
            }
        }
    }

    $finalPic = $unit.picture
    if ($upgrades) {
        $sortedUpg = $upgrades | Sort-Object { 
            $lvl = $_.level
            if ($null -ne $lvl) { [int]$lvl } else { 0 }
        } -Descending

        foreach ($u in $sortedUpg) {
            if ($u.picture -and -not [string]::IsNullOrWhiteSpace($u.picture)) {
                $finalPic = $u.picture
                break
            }
        }
    }

    $factionName = if ($script:GlobalFactionsMap.ContainsKey($typeId)) { $script:GlobalFactionsMap[$typeId] } else { "Faction #$typeId" }
    $rarityName  = Get-RarityName -rarityId $rarityId

    return @{
        Name    = $name
        Pic     = $finalPic
        Attack  = $attack
        Health  = $health
        Delay   = $delay
        Faction = $factionName
        Rarity  = $rarityName
        Skills  = $skills
        Summons = $summons
    }
}

function Get-QuadUnitsMap ([string]$filePath, [hashtable]$idMap) {
    if (-not (Test-Path $filePath)) { return @{} }
    
    $content = [System.IO.File]::ReadAllText($filePath)
    $matches = [regex]::Matches($content, '(?si)<unit>(.*?)</unit>')
    
    $map = @{}
    foreach ($m in $matches) {
        $block = $m.Value
        if ($block -match '<fusion_level>2</fusion_level>') {
            $stats = Get-UnitStats -xmlBlock $block -idMap $idMap
            if ($stats.Name) { $map[$stats.Name] = $stats }
        }
    }
    return $map
}

function Render-TwoColumnHtml {
    param(
        [array]$Stats,
        [array]$Skills
    )
    
    $html = "<table class='two-col-table'>"
    $maxRows = [Math]::Max($Stats.Count, $Skills.Count)
    
    for ($i = 0; $i -lt $maxRows; $i++) {
        $leftCell  = if ($i -lt $Stats.Count)  { $Stats[$i] } else { "" }
        $rightCell = if ($i -lt $Skills.Count) { "<span class='skill-val'>$($Skills[$i])</span>" } else { "" }
        
        $html += "<tr><td class='left-col'>$leftCell</td><td class='right-col'>$rightCell</td></tr>"
    }
    
    $html += "</table>"
    return $html
}

$newXmlFiles = Get-ChildItem -Path $NewDir -Filter "cards_section_*.xml"
$changesList = [System.Collections.Generic.List[psobject]]::new()

Write-Host "Analyzing $($newXmlFiles.Count) XML files..." -ForegroundColor Cyan

foreach ($file in $newXmlFiles) {
    $newFilePath = $file.FullName
    $oldFilePath = Join-Path $OldDir $file.Name

    Write-Host " Processing: $($file.Name)" -ForegroundColor Gray

    $unitsNew = Get-QuadUnitsMap -filePath $newFilePath -idMap $GlobalCardMap
    $unitsOld = Get-QuadUnitsMap -filePath $oldFilePath -idMap $GlobalCardMap

    foreach ($name in $unitsNew.Keys) {
        $new = $unitsNew[$name]
        $old = $unitsOld[$name]

        $picPath = Get-PicturePath -picName $new.Pic -baseDir $PicturesDir

        $summonCards = @()
        foreach ($s in $new.Summons) {
            $sPicPath = Get-PicturePath -picName $s.Pic -baseDir $PicturesDir
            if (-not $sPicPath) { $sPicPath = Get-PicturePath -picName $s.Name -baseDir $PicturesDir }
            $summonCards += @{
                Name    = $s.Name
                PicPath = $sPicPath
                Attack  = $s.Attack
                Health  = $s.Health
                Delay   = $s.Delay
                Faction = $s.Faction
                Rarity  = $s.Rarity
                Skills  = $s.Skills
                Trigger = $s.Trigger
            }
        }

        if ($null -eq $old) {
            $leftStats = @(
                "rarity: <span class='new'>$($new.Rarity)</span>",
                "faction: <span class='new'>$($new.Faction)</span>",
                "delay: <span class='new'>$($new.Delay)</span>",
                "attack: <span class='new'>$($new.Attack)</span>",
                "health: <span class='new'>$($new.Health)</span>"
            )
            
            $rightSkills = @()
            foreach ($s in $new.Skills) { $rightSkills += $s }

            $changesList.Add([PSCustomObject]@{
                SourceFile  = $file.Name
                Name        = $name
                Rarity      = $new.Rarity
                PicPath     = $picPath
                IsNew       = $true
                SummonCards = $summonCards
                Stats       = $leftStats
                Skills      = $rightSkills
            })
            continue
        }

        $leftStats = @()
        
        $rarityStr = if ($old.Rarity -ne $new.Rarity) { "<span class='old'>$($old.Rarity)</span> &rarr; <span class='new'>$($new.Rarity)</span>" } else { "<span class='new'>$($new.Rarity)</span>" }
        $leftStats += "rarity: $rarityStr"

        $factionStr = if ($old.Faction -ne $new.Faction) { "<span class='old'>$($old.Faction)</span> &rarr; <span class='new'>$($new.Faction)</span>" } else { "<span class='new'>$($new.Faction)</span>" }
        $leftStats += "faction: $factionStr"

        $delayStr = if ($old.Delay -ne $new.Delay) { "<span class='old'>$($old.Delay)</span> &rarr; <span class='new'>$($new.Delay)</span>" } else { "<span class='new'>$($new.Delay)</span>" }
        $leftStats += "delay: $delayStr"

        $attackStr = if ($old.Attack -ne $new.Attack) { "<span class='old'>$($old.Attack)</span> &rarr; <span class='new'>$($new.Attack)</span>" } else { "<span class='new'>$($new.Attack)</span>" }
        $leftStats += "attack: $attackStr"

        $healthStr = if ($old.Health -ne $new.Health) { "<span class='old'>$($old.Health)</span> &rarr; <span class='new'>$($new.Health)</span>" } else { "<span class='new'>$($new.Health)</span>" }
        $leftStats += "health: $healthStr"

        $rightSkills = @()
        $hasChanges = ($old.Rarity -ne $new.Rarity) -or ($old.Faction -ne $new.Faction) -or ($old.Delay -ne $new.Delay) -or ($old.Attack -ne $new.Attack) -or ($old.Health -ne $new.Health)

        $oldSkillStr = $old.Skills -join ", "
        $newSkillStr = $new.Skills -join ", "

        if ($oldSkillStr -ne $newSkillStr) {
            $hasChanges = $true
            $maxS = [Math]::Max($old.Skills.Count, $new.Skills.Count)
            for ($i = 0; $i -lt $maxS; $i++) {
                $sOld = if ($i -lt $old.Skills.Count) { $old.Skills[$i] } else { $null }
                $sNew = if ($i -lt $new.Skills.Count) { $new.Skills[$i] } else { $null }

                if ($sOld -ne $sNew) {
                    if ($null -ne $sOld -and $null -ne $sNew) {
                        $rightSkills += "<span class='old'>$sOld</span> &rarr; <span class='new'>$sNew</span>"
                    } elseif ($null -eq $sOld) {
                        $rightSkills += "<span class='new'>+ $sNew</span>"
                    } else {
                        $rightSkills += "<span class='old'>- $sOld</span>"
                    }
                } else {
                    $rightSkills += "<span class='new'>$sNew</span>"
                }
            }
        } else {
            foreach ($s in $new.Skills) { $rightSkills += "<span class='new'>$s</span>" }
        }

        if ($hasChanges) {
            $changesList.Add([PSCustomObject]@{
                SourceFile  = $file.Name
                Name        = $name
                Rarity      = $new.Rarity
                PicPath     = $picPath
                IsNew       = $false
                SummonCards = $summonCards
                Stats       = $leftStats
                Skills      = $rightSkills
            })
        }
    }
}

# =========================================================================
# HTML REPORT GENERATION
# =========================================================================
$htmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Unit Stats Changelog</title>
<style>
    body { 
        background-color: #090a0f; 
        color: #e0e6ed; 
        font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, sans-serif; 
        padding: 20px; 
        margin: 0;
        display: inline-block;
        width: fit-content;
    }
    h1 { 
        color: #f39c12; 
        font-size: 28px;
        text-transform: uppercase;
        letter-spacing: 2px;
        border-bottom: 2px solid #2c3e50; 
        padding-bottom: 12px; 
        margin-bottom: 25px;
        display: block;
        width: 100%;
        box-sizing: border-box;
    }
    .card-wrapper { 
        display: inline-flex; 
        align-items: stretch; 
        margin-bottom: 20px; 
        gap: 15px; 
        padding: 10px;
        background: #090a0f;
        width: fit-content;
    }
    
    .card-container { 
        display: flex; 
        align-items: center; 
        background: #121824; 
        border: 2px solid #2a364f; 
        border-radius: 10px; 
        padding: 16px 20px; 
        width: fit-content;
        box-shadow: 0 4px 15px rgba(0,0,0,0.5);
        box-sizing: border-box;
    }
    .rarity-Common { border-color: #7f8c8d; }
    .rarity-Rare { border-color: #2980b9; box-shadow: 0 0 10px rgba(41, 128, 185, 0.3); }
    .rarity-Epic { border-color: #8e44ad; box-shadow: 0 0 12px rgba(142, 68, 173, 0.4); }
    .rarity-Legendary { border-color: #f39c12; box-shadow: 0 0 15px rgba(243, 156, 18, 0.4); }
    .rarity-Vindicator { border-color: #c0392b; box-shadow: 0 0 15px rgba(192, 57, 43, 0.5); }
    .rarity-Mythic { border-color: #16a085; box-shadow: 0 0 18px rgba(22, 160, 133, 0.6); }

    .summon-container { 
        display: flex; 
        align-items: center; 
        background: #0f172a; 
        border: 1px dashed #38bdf8; 
        border-radius: 10px; 
        padding: 16px 20px; 
        width: fit-content;
        box-sizing: border-box;
    }
    
    .card-image { 
        width: 140px; 
        height: 190px; 
        border-radius: 6px; 
        margin-right: 18px; 
        object-fit: cover; 
        background: #000; 
        border: 1px solid #475569; 
        flex-shrink: 0;
    }
    .card-details { flex-grow: 1; }
    .card-title { font-size: 22px; font-weight: 700; margin-bottom: 2px; color: #ffffff; letter-spacing: 0.5px; white-space: nowrap; }
    .card-source { font-size: 11px; color: #64748b; margin-bottom: 8px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; white-space: nowrap; }
    .summon-badge { font-size: 11px; color: #38bdf8; font-weight: bold; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; white-space: nowrap; }
    
    .badge-new-card {
        display: inline-block;
        background: #22c55e;
        color: #000;
        font-weight: 800;
        font-size: 11px;
        padding: 2px 8px;
        border-radius: 4px;
        margin-bottom: 8px;
        letter-spacing: 1px;
    }

    .two-col-table { border-collapse: collapse; margin-top: 4px; }
    .two-col-table td { padding: 3px 0; vertical-align: top; font-family: 'Consolas', 'Courier New', monospace; font-size: 13px; }
    .left-col { color: #94a3b8; white-space: nowrap; padding-right: 25px; vertical-align: top; min-width: 210px; }
    .right-col { padding-left: 5px; white-space: nowrap; vertical-align: top; }

    .old { text-decoration: line-through; color: #64748b; margin-right: 6px; }
    .new { color: #facc15; font-weight: bold; }
    .skill-val { font-weight: bold; color: #ffffff; }

    .no-pic { 
        width: 140px; 
        height: 190px; 
        display: flex; 
        align-items: center; 
        justify-content: center; 
        background: #1e293b; 
        color: #64748b; 
        font-size: 12px; 
        border-radius: 6px; 
        margin-right: 18px; 
        border: 1px solid #334155;
        flex-shrink: 0;
    }
</style>
</head>
<body>
<h1>Card Balance Changelog</h1>
"@

$htmlBody = ""
$cardIndex = 0

foreach ($item in $changesList) {
    $rarityClass = "rarity-" + ($item.Rarity -replace '\s+', '')
    
    $mainImgTag = if ($item.PicPath) {
        "<img class='card-image' src='file:///$($item.PicPath)' alt='$($item.Name)'>"
    } else {
        "<div class='no-pic'>No Image</div>"
    }

    $tableHtml = Render-TwoColumnHtml -Stats $item.Stats -Skills $item.Skills
    $newBadge  = if ($item.IsNew) { "<div class='badge-new-card'>Newly Added!</div>" } else { "" }

    $summonBlocks = ""
    foreach ($sc in $item.SummonCards) {
        $sRarityClass = "rarity-" + ($sc.Rarity -replace '\s+', '')
        $sImgTag = if ($sc.PicPath) {
            "<img class='card-image' src='file:///$($sc.PicPath)' alt='$($sc.Name)'>"
        } else {
            "<div class='no-pic'>No Image</div>"
        }

        $sStats = @(
            "rarity: <span class='new'>$($sc.Rarity)</span>",
            "faction: <span class='new'>$($sc.Faction)</span>",
            "delay: <span class='new'>$($sc.Delay)</span>",
            "attack: <span class='new'>$($sc.Attack)</span>",
            "health: <span class='new'>$($sc.Health)</span>"
        )
        $sTableHtml = Render-TwoColumnHtml -Stats $sStats -Skills $sc.Skills

        $summonBlocks += @"
        <div class="summon-container $sRarityClass">
            $sImgTag
            <div class="card-details">
                <div class="summon-badge">Summoned ($($sc.Trigger))</div>
                <div class="card-title">$($sc.Name)</div>
                $sTableHtml
            </div>
        </div>
"@
    }

    $htmlBody += @"
    <div id="card-$cardIndex" class="card-wrapper">
        <div class="card-container $rarityClass">
            $mainImgTag
            <div class="card-details">
                <div class="card-title">$($item.Name)</div>
                <div class="card-source">FILE: $($item.SourceFile)</div>
                $newBadge
                $tableHtml
            </div>
        </div>
        $summonBlocks
    </div>
    <br>
"@
    $cardIndex++
}

$htmlFooter = "</body></html>"

Set-Content -Path $HtmlOutput -Value ($htmlHeader + $htmlBody + $htmlFooter) -Encoding UTF8
Write-Host "HTML Report saved to '$HtmlOutput'." -ForegroundColor Green

# =========================================================================
# STEP 4: GENERATE OVERALL JPG AND INDIVIDUAL JPGs VIA HEADLESS BROWSER
# =========================================================================
$edgePath   = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"

$browserPath = if (Test-Path $edgePath) { $edgePath } elseif (Test-Path $chromePath) { $chromePath } else { $null }

if ($browserPath) {
    # ---------------------------------------------------------------------
    # 4A: GENERATE OVERALL JPG OF ALL CARDS
    # ---------------------------------------------------------------------
    $overallJpgOutput = Join-Path $BaseDir "Changelog_All_Cards.jpg"
    Write-Host "Rendering overall JPG with ALL cards: '$overallJpgOutput'..." -ForegroundColor Cyan

    $overallArgs = @(
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--log-level=3",
        "--silent",
        "--force-device-scale-factor=2",
        "--window-size=2500,10000",
        "--screenshot=""$overallJpgOutput""",
        """file:///$HtmlOutput"""
    )

    $process = [System.Diagnostics.Process]::Start($browserPath, ($overallArgs -join " "))
    $process.WaitForExit()
    
    # Executing cropping logic
    Crop-Image -imagePath $overallJpgOutput
    Write-Host " Overall JPG generated and cropped successfully!" -ForegroundColor Green

    # ---------------------------------------------------------------------
    # 4B: SAVE EACH CARD AS AN INDIVIDUAL JPG
    # ---------------------------------------------------------------------
    Write-Host "Rendering individual JPG images per card..." -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $changesList.Count; $i++) {
        $item = $changesList[$i]
        
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $cleanName = $item.Name
        foreach ($char in $invalidChars) {
            $cleanName = $cleanName.Replace($char.ToString(), "")
        }
        
        $cardJpgOutput = Join-Path $BaseDir "$cleanName.jpg"
        Write-Host " Generating JPG for: $($item.Name)" -ForegroundColor Gray

        $singleCardHtmlPath = Join-Path $BaseDir "temp_card_$i.html"
        $singleCardHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
    body { background-color: #090a0f; margin: 0; padding: 10px; display: inline-block; width: fit-content; }
    $($htmlHeader.Substring($htmlHeader.IndexOf("<style>") + 7, $htmlHeader.IndexOf("</style>") - $htmlHeader.IndexOf("<style>") - 7))
</style>
</head>
<body>
    <div class="card-wrapper">
        <div class="card-container rarity-$($item.Rarity -replace '\s+', '')">
            $(if ($item.PicPath) { "<img class='card-image' src='file:///$($item.PicPath)' alt='$($item.Name)'>" } else { "<div class='no-pic'>No Image</div>" })
            <div class="card-details">
                <div class="card-title">$($item.Name)</div>
                <div class="card-source">FILE: $($item.SourceFile)</div>
                $(if ($item.IsNew) { "<div class='badge-new-card'>Newly Added!</div>" } else { "" })
                $(Render-TwoColumnHtml -Stats $item.Stats -Skills $item.Skills)
            </div>
        </div>
        $(
            $sBlocks = ""
            foreach ($sc in $item.SummonCards) {
                $sImg = if ($sc.PicPath) { "<img class='card-image' src='file:///$($sc.PicPath)' alt='$($sc.Name)'>" } else { "<div class='no-pic'>No Image</div>" }
                $sStats = @("rarity: <span class='new'>$($sc.Rarity)</span>", "faction: <span class='new'>$($sc.Faction)</span>", "delay: <span class='new'>$($sc.Delay)</span>", "attack: <span class='new'>$($sc.Attack)</span>", "health: <span class='new'>$($sc.Health)</span>")
                $sTable = Render-TwoColumnHtml -Stats $sStats -Skills $sc.Skills
                $sBlocks += "<div class='summon-container rarity-$($sc.Rarity -replace '\s+', '')'>$sImg<div class='card-details'><div class='summon-badge'>Summoned ($($sc.Trigger))</div><div class='card-title'>$($sc.Name)</div>$sTable</div></div>"
            }
            $sBlocks
        )
    </div>
</body>
</html>
"@
        Set-Content -Path $singleCardHtmlPath -Value $singleCardHtml -Encoding UTF8

        $renderArgs = @(
            "--headless",
            "--disable-gpu",
            "--hide-scrollbars",
            "--log-level=3",
            "--silent",
            "--force-device-scale-factor=2",
            "--window-size=2500,800",
            "--screenshot=""$cardJpgOutput""",
            """file:///$singleCardHtmlPath"""
        )

        $process = [System.Diagnostics.Process]::Start($browserPath, ($renderArgs -join " "))
        $process.WaitForExit()

        # Executing cropping logic for single image
        Crop-Image -imagePath $cardJpgOutput

        Remove-Item -Path $singleCardHtmlPath -ErrorAction SilentlyContinue
    }

    Write-Host "All individual JPG images saved and cropped successfully." -ForegroundColor Green
} else {
    Write-Warning "No compatible Browser (Edge/Chrome) found for JPG screenshot generation."
}

Write-Host "Process completed! Total unit changes processed: $($changesList.Count)." -ForegroundColor Green