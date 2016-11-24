# unfinished-chos-release-sigspoof-patcher

This repo contains a failed attempt to patch signature spoofing (as needed by microg) to CopperheadOS releases.
Maybe this helps someone, who intends to do a proper implementation (if you can make it work, I recommend rewriting everything as sane code and extending mission-improbable with it).


*USE AT YOUR OWN RISK!* (or rather, read the code and write a proper implementation)

The code is based on [mission-improbable](https://github.com/mikeperry-tor/mission-improbable) and [tingle](https://github.com/ale5000-git/tingle).

It might also be, that the whole approach is flawed. What the script does is basically extract/disassemble the PackageParser.smali file from all layers of the release zip file, patch it (patch applies cleanly!), and try to reconstruct the release so it can be flashed. CopperheadOS ships a natively compiled `boot-framework.oat` instead of a `framework.jar`, so the script deletes the oat file (both for arm and arm64) and creates a new framework.jar. The assumption is, that Android will load the framework.jar file then, and everything will work out (which it did not in practice, the boot screen ran forever and nothing happened). If you have more knowledge regarding this, please file a bug report (though I won't patch the code further as I'm using stock CopperheadOS now).

The main script is sigspoof.sh, and it has the following dependencies, which are not included in the code tree:
* [smali](https://github.com/JesusFreke/smali) for disassembling `boot-framework.oat` and assembling it again (not natively compiled). Use the latest (beta) version.
* [super-bootimg](https://github.com/mikeperry-tor/super-bootimg)
* various stuff from mission-improbable's [extra](https://github.com/mikeperry-tor/mission-improbable/tree/master/extras) folder (some of them are blobs)
