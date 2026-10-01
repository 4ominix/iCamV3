$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$required=@('Makefile','control','iCamV3.plist','iCamV3Controls.plist','iCamV3App.entitlements',
 'app/main.m','app/AppDelegate.h','app/AppDelegate.m','app/MainViewController.h','app/MainViewController.m',
 'shared/LMCConfig.h','shared/LMCConfig.m','shared/LMCGeometry.h','shared/LMCRender.h','shared/LMCRender.m',
 'shared/LMCControlPanel.h','shared/LMCControlPanel.m','tweak/Tweak.mm','tweak/Controls.mm',
 'iCamV3App/Info.plist','layout/DEBIAN/preinst','layout/DEBIAN/postinst','layout/DEBIAN/prerm',
 'tests/geometry.c','tests/test_source.py','README.md','FEATURE_SCOPE.md',
 '.github/workflows/build-deb.yml','.gitignore','.gitattributes','scripts/validate.ps1',
 'scripts/verify_package.py','scripts/verify_entitlements.py',
 'iCamV3App/Resources/AppIcon60x60.png','iCamV3App/Resources/AppIcon60x60@2x.png','iCamV3App/Resources/AppIcon60x60@3x.png')
foreach($file in $required){if(!(Test-Path (Join-Path $root $file))){throw "Missing: $file"}}
$make=Get-Content (Join-Path $root 'Makefile') -Raw
foreach($line in ($make -split "`n")){
 if($line -match '^\w+_FILES = (.+)$'){
  foreach($file in ($Matches[1].Trim() -split '\s+')){if(!(Test-Path (Join-Path $root $file))){throw "Makefile source missing: $file"}}
 }
}
$e=[xml](Get-Content (Join-Path $root 'iCamV3App.entitlements') -Raw)
foreach($key in @('platform-application','com.apple.private.security.no-sandbox','com.apple.private.security.storage.AppBundles','com.apple.private.security.storage.AppDataContainers')){
 $node=$e.SelectSingleNode("/plist/dict/key[text()='$key']")
 if(!$node -or $node.NextSibling.Name -ne 'true'){throw "Missing entitlement: $key"}
}
$info=[xml](Get-Content (Join-Path $root 'iCamV3App/Info.plist') -Raw)
$version=$info.SelectSingleNode('/plist/dict/key[text()="CFBundleShortVersionString"]').NextSibling.InnerText
if((Get-Content (Join-Path $root 'control') -Raw) -notmatch "(?m)^Version: $([regex]::Escape($version))\s*$"){throw 'Bundle/package version mismatch'}
$config=Get-Content (Join-Path $root 'shared/LMCConfig.m') -Raw
if(!$config.Contains('jbroot(@"/var/mobile/Library/iCamV3")')){throw 'Shared storage not RootHide-aware'}
$tweak=Get-Content (Join-Path $root 'tweak/Tweak.mm') -Raw
if($tweak.Contains('dispatch_sync') -or $tweak.Contains('toCVPixelBuffer:dst')){throw 'Blocking/direct rendering returned to camera callback'}
foreach($needle in @('LMCCopyPixels','os_unfair_lock_trylock','InstallHooks','CameraStatus.%@.plist','CMSampleBufferGetPresentationTimeStamp')){
 if(!$tweak.Contains($needle)){throw "Missing runtime anchor: $needle"}
}
foreach($dir in @('app','shared','tweak')){
 foreach($file in (Get-ChildItem (Join-Path $root $dir) -File | Where-Object Extension -in '.m','.mm','.h')){
  $s=Get-Content $file.FullName -Raw
  foreach($forbidden in @('NSURLSession','NSURLConnection','NWConnection','vcnext.corev.bond','CapabilityLease','AuthSession','RTMP')){
   if($s.Contains($forbidden)){throw "Online feature: $forbidden in $($file.Name)"}
  }
 }
}
foreach($script in @('preinst','postinst','prerm')){
 $bytes=[IO.File]::ReadAllBytes((Join-Path $root "layout/DEBIAN/$script"))
 if([Text.Encoding]::UTF8.GetString($bytes[0..9]) -ne "#!/bin/sh`n"){throw "Invalid shell header/BOM: $script"}
 if($bytes -contains 13){throw "CRLF in shell: $script"}
}
foreach($icon in @(@('AppIcon60x60.png',60),@('AppIcon60x60@2x.png',120),@('AppIcon60x60@3x.png',180))){
 $b=[IO.File]::ReadAllBytes((Join-Path $root "iCamV3App/Resources/$($icon[0])"))
 if($b.Length -lt 24 -or $b[0] -ne 137 -or $b[1] -ne 80){throw 'Invalid icon'}
 $w=[BitConverter]::ToUInt32([byte[]]@($b[19],$b[18],$b[17],$b[16]),0)
 $h=[BitConverter]::ToUInt32([byte[]]@($b[23],$b[22],$b[21],$b[20]),0)
 if($w -ne $icon[1] -or $h -ne $icon[1]){throw 'Icon size mismatch'}
}
Write-Output "PASS: $($required.Count) files, metadata, RootHide storage/entitlements, offline and nonblocking anchors."
Write-Output 'NOTE: static validation only; iOS compilation and real-device behavior must be tested separately.'
