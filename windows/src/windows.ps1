param([string]$Mode,[string]$Payload)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Speech
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class IrisNative {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
try {
 $p = if($Payload){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json}else{@{}}
 switch($Mode){
 'context' {
  $focus=[Windows.Automation.AutomationElement]::FocusedElement
  $window=[Windows.Automation.AutomationElement]::FromHandle([IrisNative]::GetForegroundWindow())
  $list=New-Object Collections.Generic.List[object]
  $all=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt [Math]::Min(350,$all.Count);$i++){$e=$all[$i];if(!$e.Current.IsPassword -and !$e.Current.IsOffscreen){$list.Add(@{name=$e.Current.Name;type=$e.Current.ControlType.ProgrammaticName;rect=@{x=$e.Current.BoundingRectangle.X;y=$e.Current.BoundingRectangle.Y;width=$e.Current.BoundingRectangle.Width;height=$e.Current.BoundingRectangle.Height}})}}
  $value='';$v=$null;if(!$focus.Current.IsPassword -and $focus.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$v)){$value=$v.Current.Value}
  @{handle=[IrisNative]::GetForegroundWindow().ToInt64();runtime=$focus.GetRuntimeId();password=$focus.Current.IsPassword;name=$focus.Current.Name;value=$value;window=$window.Current.Name;elements=$list} | ConvertTo-Json -Depth 7 -Compress
 }
 'insert' {
  [void][IrisNative]::SetForegroundWindow([IntPtr][long]$p.handle);Start-Sleep -Milliseconds 150
  $f=[Windows.Automation.AutomationElement]::FocusedElement
  if($f.Current.IsPassword -or (($f.GetRuntimeId() -join ',') -ne ($p.runtime -join ','))){throw 'The focused field changed. Copy the draft instead.'}
  [IrisNative]::keybd_event(0x11,0,0,[UIntPtr]::Zero);[IrisNative]::keybd_event(0x56,0,0,[UIntPtr]::Zero);[IrisNative]::keybd_event(0x56,0,2,[UIntPtr]::Zero);[IrisNative]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
  @{ok=$true}|ConvertTo-Json -Compress
 }
 'speak' {$s=[System.Speech.Synthesis.SpeechSynthesizer]::new();$s.Speak([string]$p.text);$s.Dispose();'{"ok":true}'}
 'recognize' {$r=[System.Speech.Recognition.SpeechRecognitionEngine]::new();$r.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new());$r.SetInputToDefaultAudioDevice();$r.EndSilenceTimeout=[TimeSpan]::FromSeconds(1.3);$result=$r.Recognize([TimeSpan]::FromSeconds(30));@{text=if($result){$result.Text}else{''}}|ConvertTo-Json -Compress;$r.Dispose()}
 'click' {[IrisNative]::SetCursorPos([int]$p.x,[int]$p.y)|Out-Null;[IrisNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[IrisNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero);'{"ok":true}'}
 default {throw 'Unknown Windows operation.'}
 }
} catch { @{error=$_.Exception.Message}|ConvertTo-Json -Compress;exit 1 }
