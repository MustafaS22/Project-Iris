from pathlib import Path
import plistlib, shutil
root=Path(__file__).resolve().parent
base={ 'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'Iris','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.1','CFBundleVersion':'2','LSRequiresIPhoneOS':True,'NSSupportsLiveActivities':True,'NSCalendarsFullAccessUsageDescription':'Iris reads only calendars you check to include upcoming events in answers. It does not change events.','NSRemindersFullAccessUsageDescription':'Iris reads only lists you check to include incomplete reminders in answers. It does not change reminders.','NSMicrophoneUsageDescription':'Iris listens only when you summon it or tap the microphone.','NSSpeechRecognitionUsageDescription':'Iris transcribes your spoken question. Recognition may process audio with Apple.','UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UIBackgroundModes':['audio'],'CFBundleURLTypes':[{'CFBundleURLName':'com.arize.iris.iphone','CFBundleURLSchemes':['iris']} ] }
(root/'App/Info.plist').write_bytes(plistlib.dumps(base))
ext={'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'Iris Island','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'XPC!','CFBundleShortVersionString':'1.1','CFBundleVersion':'2','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
(root/'Island/Info.plist').write_bytes(plistlib.dumps(ext))
asset=root/'App/Assets.xcassets/AppIcon.appiconset';asset.mkdir(parents=True,exist_ok=True)
assert (asset/'IrisIcon.png').exists(), 'Keep the bundled IrisIcon.png in App/Assets.xcassets/AppIcon.appiconset'
(asset/'Contents.json').write_text('{"images":[{"filename":"IrisIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}')
(root/'App/Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
objects={};counter=0

def obj(isa,**kw):
 global counter
 counter+=1; key=f'{counter:024X}';objects[key]={'isa':isa,**kw};return key

def config(name,settings):return obj('XCBuildConfiguration',name=name,buildSettings=settings)
def configs(settings):return obj('XCConfigurationList',buildConfigurations=[config('Debug',{**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'}),config('Release',{**settings,'SWIFT_COMPILATION_MODE':'wholemodule'})],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
appProduct=obj('PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Iris.app',sourceTree='BUILT_PRODUCTS_DIR')
widgetProduct=obj('PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='IrisIsland.appex',sourceTree='BUILT_PRODUCTS_DIR')
files={}
for path in sorted(str(p.relative_to(root)) for folder in ['App','Shared','Island'] for p in (root/folder).glob('*.swift')):
 files[path]=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>')
shortcut=obj('PBXFileReference',lastKnownFileType='file',path='App/Ask-Iris-in-Island.shortcut',sourceTree='<group>')
assets=obj('PBXFileReference',lastKnownFileType='folder.assetcatalog',path='App/Assets.xcassets',sourceTree='<group>')
products=obj('PBXGroup',children=[appProduct,widgetProduct],name='Products',sourceTree='<group>')
group=obj('PBXGroup',children=[*files.values(),assets,shortcut,products],sourceTree='<group>')
common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','SWIFT_EMIT_LOC_STRINGS':'YES','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'1.1','CLANG_ENABLE_MODULES':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','ENABLE_BITCODE':'NO'}

def phase(isa,paths):return obj(isa,buildActionMask=2147483647,files=[obj('PBXBuildFile',fileRef=files[p]) for p in paths],runOnlyForDeploymentPostprocessing=0)
widget=obj('PBXNativeTarget',buildConfigurationList=configs({**common,'PRODUCT_BUNDLE_IDENTIFIER':'com.arize.iris.iphone.island','PRODUCT_NAME':'IrisIsland','INFOPLIST_FILE':'Island/Info.plist','SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'}),buildPhases=[phase('PBXSourcesBuildPhase',[p for p in files if p.startswith(('Shared/','Island/'))]),obj('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)],buildRules=[],dependencies=[],name='IrisIsland',productName='IrisIsland',productReference=widgetProduct,productType='com.apple.product-type.app-extension')
projectID=f'{counter+1000:024X}'
proxy=obj('PBXContainerItemProxy',containerPortal=projectID,proxyType=1,remoteGlobalIDString=widget,remoteInfo='IrisIsland')
dep=obj('PBXTargetDependency',target=widget,targetProxy=proxy)
embed=obj('PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[obj('PBXBuildFile',fileRef=widgetProduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
app=obj('PBXNativeTarget',buildConfigurationList=configs({**common,'PRODUCT_BUNDLE_IDENTIFIER':'com.arize.iris.iphone','PRODUCT_NAME':'Iris','INFOPLIST_FILE':'App/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]':'App/Simulator.entitlements','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SKIP_INSTALL':'NO'}),buildPhases=[phase('PBXSourcesBuildPhase',[p for p in files if not p.startswith('Island/')]),obj('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[obj('PBXBuildFile',fileRef=assets),obj('PBXBuildFile',fileRef=shortcut)],runOnlyForDeploymentPostprocessing=0),obj('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),embed],buildRules=[],dependencies=[dep],name='Iris',productName='Iris',productReference=appProduct,productType='com.apple.product-type.application')
objects[projectID]={'isa':'PBXProject','attributes':{'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2720'},'buildConfigurationList':configs(common),'compatibilityVersion':'Xcode 14.0','developmentRegion':'en','hasScannedForEncodings':0,'knownRegions':['en','Base'],'mainGroup':group,'productRefGroup':products,'projectDirPath':'','projectRoot':'','targets':[app,widget]}
import json
# JSON property lists are accepted for project.pbxproj after conversion to OpenStep through plutil.
def emit(value):
 if isinstance(value,dict):return '{ '+ ' '.join(json.dumps(str(k))+' = '+emit(v)+';' for k,v in value.items())+' }'
 if isinstance(value,list):return '( '+', '.join(emit(v) for v in value)+' )'
 return json.dumps(str(value))
(root/'Iris.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+emit({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':projectID}))
scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2720" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Iris.app" BlueprintName="Iris" ReferencedContainer="container:Iris.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Iris.app" BlueprintName="Iris" ReferencedContainer="container:Iris.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'Iris.xcodeproj/xcshareddata/xcschemes/Iris.xcscheme').write_text(scheme)
print('Generated Iris iPhone project')
