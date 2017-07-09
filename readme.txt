       ____________________________
      /                     ___    /\
     /  ________________   /__/   /  \
    /      /\__________/    _____/   /
   /  ____/ /         /       \  \  /
  /      / /         /   /\    \__\/ 
 /______/ /   /   / /___/  \____\ 
 \      \/___/___/__\   \  /\    \ 
  \______\   \   \   \___\/  \____\
        \_____\___\____\/ 

  E X E M U S I C R E C O R D E R

  https://github.com/reddor/emr/

 === WHAT? ===

 Exemusic Recorder is a tool originally written to record music from certain programs, such as EXEMUSIC or 4/8/16/32/64 kB intros, a common
 trait found in the demoscene. It has some extra features that might or might not be helpful when analyzing programs (intros). If you have
 no idea what I'm talking about, this tool is not for you.

 === USAGE ===

 I really hope the UI is self explanatory. Select executable, arguments & output directory, choose options, press start.
 
 Most functions are just added for fun and curiosity - you can use this to find out what certain intros do, what files and DLLs they load,
 how they call certain APIs... It might have been used to analyze malware, too - but don't take my word for it, and always make sure to run
 those things in a VM.

 === TROUBLESHOOTING ===

 If the target application crashes, try if it's related to certain options. If the binary has relocation info, remove it using stripreloc. 
 If all fails, click the "Executable"-label a couple of times until the "Experimental" options show up. 

 * Simple Injector: enabled by default, disabling it will use a more complicated (and potentially more troublesome) injection method 
   that should ensure injection before anything else from the target binary is executed. Then again, so should the simple injection method.

 * Slow Wave Writing: enabled by default. Writes large chunks of audio buffers to disk as it if were playing in real-time. This is basically
   a fix for 4klang when a single large buffer is allocated, passed to the audio api and then filled - this option might cause problems in other 
   scenarios.

 * Hook into spawned processes: Use this when encountering droppers that spawns a new process. e.g. obscure packers.

 "Double Speed" might cause problems if your CPU is too slow (or your soundcard does not support twice the samplerate). Use "Half speed" instead.

 If all of the above hints are stupid and didn't help, you're fucked. You can file a bug at the github repo.

 === COMMANDLINE VERSION ===
 
 Instead of using the UI you can use parameters to do the same thing. Usage:

 emr.exe <parameters> [target] [target parameters]

 parameters:
  -record    - record audio
  -acmdump*  - dump acm samples
  -shader    - dump shaders
  -windowed  - prevent fullscreen
  -cursor    - don't hide cursor
  -logfile*  - log file access
  -nowrite   - prevent writing to file
  -logcp*    - log process creation
  -nocp      - prevent process creation
  -proc      - log GetProcAddress
  -nosocket  - prevent network access
  -wgl       - log wglGetProcAddress
  -inject    - inject previously dumped shaders
  -trace     - log all DLL calls
  -nolog     - don't create log file

 === CREDITS ===

 This project uses several things that shall be credited accordingly:

 Delphi Detours: https://github.com/mahdisafsafi/delphi-detours-library
 DirectX Headers: http://www.clootie.ru/delphi/index.html
 Delphi JEDI: http://www.delphi-jedi.org
 SuperFastHash: http://www.azillionmonkeys.com/qed/hash.html
 afxCodeHook by Aphex (no url) 
 Icon: http://www.iconarchive.com/show/cold-fusion-hd-icons-by-chrisbanks2/sound-recorder-alt-icon.html

 ...and of course the awesome http://www.lazarus-ide.org/ & http://freepascal.org

 === LICENSE ===
 
 as is. no refunds.