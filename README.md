# Exemusic Recorder

![A pretty picture of exemusic recorder](http://i.imgur.com/iQTempz.png)

Binaries available here: https://github.com/reddor/emr/files/1133860/emr-v01010220.zip

## WHAT? 

Exemusic Recorder is a tool originally written to record music from certain programs, such as EXEMUSIC or 4/8/16/32/64 kB intros, a common trait found in the demoscene. It has some extra features that might or might not be helpful when analyzing programs (intros). If you have no idea what I'm talking about, this tool is not for you.
 
## USAGE

I really hope the UI is self explanatory. Select executable, arguments & output directory, choose options, press start.
 
Most functions are just added for fun and curiosity - you can use this to find out what certain intros do, what files and DLLs they load, how they call certain APIs... It might have been used to analyze malware, too - but don't take my word for it, and always make sure to run those things in a VM.

## TROUBLESHOOTING 

If the target application crashes, try if it's related to certain options. If the binary has relocation info, remove it using stripreloc. If all fails, click the "Executable"-label a couple of times until the "Experimental" options show up. Toggle "Simple Injector" for a slightly different injection method. 

"Double Speed" might cause problems if your CPU is too slow (or your soundcard does not support twice the samplerate). Use "Half speed" instead.

If all of the above hints are stupid and didn't help, you're out of luck. You can file a bug here.

## CREDITS 

 This project uses several things that shall be credited accordingly:

 Delphi Detours: https://github.com/mahdisafsafi/delphi-detours-library
 
 DirectX Headers: http://www.clootie.ru/delphi/index.html
 
 Delphi JEDI: http://www.delphi-jedi.org
 
 SuperFastHash: http://www.azillionmonkeys.com/qed/hash.html
 
 afxCodeHook by Aphex (no url) 
 
 Icon: http://www.iconarchive.com/show/cold-fusion-hd-icons-by-chrisbanks2/sound-recorder-alt-icon.htm

 ...and of course the awesome http://www.lazarus-ide.org/ & http://freepascal.org

## LICENSE
 
 as is. no refunds.
