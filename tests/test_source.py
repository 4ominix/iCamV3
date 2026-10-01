#!/usr/bin/env python3
"""Structural regression tests. These do NOT substitute for an iOS compile/device test."""
import pathlib, plistlib, re, shlex, subprocess, tempfile, unittest, sys
ROOT=pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv)>1: sys.argv=sys.argv[:1]
def read(name): return (ROOT/name).read_text(encoding="utf-8-sig")
class SourceTests(unittest.TestCase):
    def test_rootHide_storage_and_entitlements(self):
        self.assertIn('jbroot(@"/var/mobile/Library/iCamV3")', read('shared/LMCConfig.m'))
        e=plistlib.loads((ROOT/'iCamV3App.entitlements').read_bytes())
        for k in ('platform-application','com.apple.private.security.no-sandbox',
                  'com.apple.private.security.storage.AppBundles','com.apple.private.security.storage.AppDataContainers'):
            self.assertIs(e.get(k),True,k)
        script=read('layout/DEBIAN/postinst')
        self.assertIn('SHARED_DIR="/var/mobile/Library/iCamV3"',script)
        self.assertNotIn('/var/jb',script.replace('# RootHide bootstrap tools operate on jbroot-relative paths (not /var/jb).',''))
        self.assertIn('chown mobile:mobile "$SHARED_DIR"',script)
    def test_import_transaction(self):
        app=read('app/MainViewController.m')
        self.assertIn('PHPickerConfigurationAssetRepresentationModeCurrent',app)
        self.assertIn('copyItemAtURL:url',app)
        self.assertLess(app.index('copyItemAtURL:url'),app.index('NSError *importError=error'))
        self.assertIn('next.mediaPath=name',app)
        self.assertIn('if(![next save:&saveError])',app)
        self.assertIn('Lỗi nhập media',app)
    def test_nonblocking_failsafe_and_late_hooks(self):
        tweak=read('tweak/Tweak.mm')
        self.assertNotIn('dispatch_sync',tweak)
        self.assertIn('os_unfair_lock_trylock',tweak)
        self.assertIn('LMCCopyPixels',tweak)
        self.assertIn('toCVPixelBuffer:scratch',tweak)
        self.assertNotIn('toCVPixelBuffer:dst',tweak)
        self.assertIn('CMSampleBufferGetPresentationTimeStamp',tweak)
        self.assertIn('static void InstallHooks',tweak)
        self.assertIn('if(*original)return',tweak)
        for name in ('BWNodeOutput','BWImageQueueSinkNode','BWPhotoEncoderNode','BWRemoteQueueSinkNode','BWStillImageSampleBufferSinkNode'):
            self.assertIn(name,tweak)
    def test_controls_and_shared_geometry(self):
        for name in ('shared/LMCRender.m','app/MainViewController.m','tweak/Tweak.mm'):
            self.assertIn('LMCComposeImage' if name!='shared/LMCRender.m' else 'LMCGeometry',read(name))
        for key in ('Zoom','OffsetX','OffsetY'):
            self.assertIn('@"'+key+'"',read('shared/LMCConfig.m'))
        self.assertIn('SpringBoard',read('iCamV3Controls.plist'))
        self.assertIn('com.apple.springboard.lockstate',read('tweak/Controls.mm'))
        self.assertIn('LMCControlPanel',read('tweak/Controls.mm'))
    def test_offline(self):
        files=list((ROOT/'app').glob('*.m'))+list((ROOT/'shared').glob('*.m'))+list((ROOT/'tweak').glob('*.mm'))
        for f in files:
            s=f.read_text(encoding='utf-8-sig')
            for forbidden in ('NSURLSession','NSURLConnection','NWConnection','vcnext.corev.bond','CapabilityLease','AuthSession','RTMP'):
                self.assertNotIn(forbidden,s,str(f))
    def test_metadata_and_build(self):
        info=plistlib.loads((ROOT/'iCamV3App/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'],'com.icamv3.app')
        control=read('control');version=re.search(r'^Version: (.+)$',control,re.M).group(1)
        self.assertEqual(info['CFBundleShortVersionString'],version)
        make=read('Makefile')
        self.assertIn('TWEAK_NAME = iCamV3 iCamV3Controls',make)
        self.assertIn('ARCHS = arm64 arm64e',make)
        for match in re.finditer(r'^\w+_FILES = (.+)$',make,re.M):
            for file in match.group(1).split(): self.assertTrue((ROOT/file).is_file(),file)
    def test_lipo_input_precedes_architecture_list(self):
        workflow=read('.github/workflows/build-deb.yml')
        commands=[shlex.split(line.strip()) for line in workflow.splitlines()
                  if line.strip().startswith('xcrun lipo ') and '-verify_arch' in line]
        self.assertEqual(commands,[['xcrun','lipo','$RUNNER_TEMP/icam-data/$binary',
                                    '-verify_arch','arm64','arm64e']])
        for binary in ('Applications/iCamV3App.app/iCamV3App',
                       'Library/MobileSubstrate/DynamicLibraries/iCamV3.dylib',
                       'Library/MobileSubstrate/DynamicLibraries/iCamV3Controls.dylib'):
            self.assertIn("'"+binary+"'",workflow)
    def test_entitlements_per_architecture(self):
        workflow=read('.github/workflows/build-deb.yml')
        self.assertIn('for arch in arm64 arm64e; do',workflow)
        self.assertIn('xcrun lipo "$app_binary" -thin "$arch" -output "$thin_binary"',workflow)
        self.assertIn('"$ldid_path" -e "$thin_binary" > "$entitlements_file"',workflow)
        self.assertIn('python3 scripts/verify_entitlements.py "$entitlements_file"',workflow)
        self.assertNotIn('"$ldid_path" -e "$RUNNER_TEMP/icam-data/',workflow)
    def entitlement_result(self,data):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'signed-slice.plist';path.write_bytes(data)
            return subprocess.run([sys.executable,str(ROOT/'scripts/verify_entitlements.py'),str(path)],
                                  capture_output=True,text=True)
    def test_entitlements_valid_formats(self):
        entitlements=plistlib.loads((ROOT/'iCamV3App.entitlements').read_bytes())
        for fmt in (plistlib.FMT_XML,plistlib.FMT_BINARY):
            with self.subTest(format=fmt):
                result=self.entitlement_result(plistlib.dumps(entitlements,fmt=fmt))
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('PASS:',result.stdout)
    def test_entitlements_bad_documents(self):
        xml=(ROOT/'iCamV3App.entitlements').read_bytes()
        for data in (b'',b'not a plist',xml+xml,xml+b'garbage',plistlib.dumps([])):
            with self.subTest(input=data[:30]):
                result=self.entitlement_result(data)
                self.assertEqual(result.returncode,1)
                self.assertIn('ERROR:',result.stderr)
                self.assertNotIn('Traceback',result.stderr)
                self.assertNotIn('PASS:',result.stdout)
    def test_entitlements_required_boolean(self):
        original=plistlib.loads((ROOT/'iCamV3App.entitlements').read_bytes())
        for key in original:
            for value in (None,False,1,'true'):
                with self.subTest(key=key,value=value):
                    entitlements=original.copy()
                    if value is None: del entitlements[key]
                    else: entitlements[key]=value
                    result=self.entitlement_result(plistlib.dumps(entitlements))
                    self.assertEqual(result.returncode,1)
                    self.assertIn('missing entitlement: '+key,result.stderr)
    def test_entitlements_cli_errors(self):
        script=str(ROOT/'scripts/verify_entitlements.py')
        result=subprocess.run([sys.executable,script],capture_output=True,text=True)
        self.assertEqual(result.returncode,2)
        self.assertIn('Usage:',result.stderr)
        with tempfile.TemporaryDirectory() as directory:
            result=subprocess.run([sys.executable,script,str(pathlib.Path(directory)/'missing.plist')],
                                  capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('Cannot read entitlements',result.stderr)
        self.assertNotIn('Traceback',result.stderr)
    def test_shell_encoding(self):
        for f in (ROOT/'layout/DEBIAN').iterdir():
            data=f.read_bytes();self.assertTrue(data.startswith(b'#!/bin/sh\n'),str(f));self.assertNotIn(b'\r',data)
    def test_diagnostics_not_false_success(self):
        self.assertIn('CameraStatus.%@.plist',read('app/MainViewController.m'))
        self.assertIn('CameraStatus.%@.plist',read('tweak/Tweak.mm'))
        self.assertIn('Chưa có tín hiệu',read('app/MainViewController.m'))
        self.assertNotIn('Camera sẽ cập nhật tự động',read('app/MainViewController.m'))
    def test_short_video_eof_interval(self):
        tweak=read('tweak/Tweak.mm')
        self.assertIn('elapsed<_videoEnd',tweak)
        self.assertIn('CMSampleBufferGetDuration(_pending)',tweak)
        self.assertIn('if(!isfinite(duration)||duration<=0)duration=_frameDuration',tweak)
        self.assertIn('BOOL restarted=NO',tweak)
        self.assertIn('_config.loop && !restarted',tweak)
    def test_deleted_source_rechecked(self):
        tweak=read('tweak/Tweak.mm')
        check=tweak.index('if(n.enabled && ![NSFileManager.defaultManager isReadableFileAtPath:path])')
        self.assertLess(check,tweak.index('if(!sourceChanged)return'))
        self.assertIn('_loadedPath=@"";_stillImage=nil;[self clearReader];[self clearCache]',tweak)
    def test_targeted_config_updates(self):
        app=read('app/MainViewController.m')
        for name in ('enabledSwitch','loopSwitch','mirrorSwitch','modeControl','rotationControl'):
            self.assertIn('sender==self.'+name,app)
        self.assertIn('LMCConfig *latest=[LMCConfig load]',app)
        self.assertIn('latest.offsetX=self.config.offsetX',app)
    def test_lock_transition_dispatch(self):
        self.assertIn('notify_register_dispatch',read('tweak/Controls.mm'))
        self.assertIn('notify_cancel(self.lockToken)',read('tweak/Controls.mm'))
    def test_large_buffer_and_rotation_bounds(self):
        self.assertIn('w*h<=24*1024*1024',read('tweak/Tweak.mm'))
        self.assertIn('fmod(Number(d,@"Rotation",0),360.0)',read('shared/LMCConfig.m'))
    def test_preview_background_lifecycle(self):
        app=read('app/MainViewController.m')
        self.assertIn('UIApplicationDidEnterBackgroundNotification',app)
        self.assertIn('UIApplicationWillEnterForegroundNotification',app)
        self.assertIn('self.player.muted=YES',app)
        self.assertIn('self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark',app)
if __name__=='__main__': unittest.main(verbosity=2)
