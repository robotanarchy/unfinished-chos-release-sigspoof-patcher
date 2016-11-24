#!/usr/bin/python3
# License: GPLv3

import sys
import os


if len(sys.argv) != 2:
	print("Syntax: tingle_standalone.py PATH_TO_PackageParser.smali")
	print("This is a standalone version of the patching code from")
	print("tingle: https://github.com/ale5000-git/tingle/main.py")
	sys.exit(1)


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
to_patch = sys.argv[1]

# Do the injection
print(" *** Patching..." + to_patch)
f = open(to_patch, "r")
old_contents = f.readlines()
f.close()

f = open(SCRIPT_DIR+"/patches/fillinsig.smali", "r")
fillinsig = f.readlines()
f.close()

# Add fillinsig method
i = 0
contents = []
already_patched = False
in_function = False
right_line = False
start_of_line = None
done_patching = False
stored_register = "v11"
partially_patched = False

while i < len(old_contents):
	if ";->fillinsig" in old_contents[i]:
		already_patched = True
	if ".method public static fillinsig" in old_contents[i]:
		partially_patched = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[IIJJLjava/util/Set;Landroid/content/pm/PackageUserState;I)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: Android 7.x / Android 6.0.x / CyanogenMod 13-14")
		in_function = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[IIJJLandroid/util/ArraySet;Landroid/content/pm/PackageUserState;I)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: Android 5.x / CyanogenMod 12")
		in_function = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[IIJJLjava/util/HashSet;Landroid/content/pm/PackageUserState;I)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: Android 4.4.x / CyanogenMod 10-11")
		in_function = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[IIJJ)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: CyanogenMod 7-9 - UNTESTED")
		in_function = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[II)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: CyanogenMod 6 - UNTESTED")
		in_function = True
	if ".method public static generatePackageInfo(Landroid/content/pm/PackageParser$Package;[IIJJLjava/util/HashSet;ZII)Landroid/content/pm/PackageInfo;" in old_contents[i]:
		print(" *** Detected: Alien Dalvik (Sailfish OS)")
		in_function = True
	if ".end method" in old_contents[i]:
		in_function = False
	if in_function and ".line" in old_contents[i]:
		start_of_line = i + 1
	if in_function and "arraycopy" in old_contents[i]:
		right_line = True
	if in_function and "Landroid/content/pm/PackageInfo;-><init>()V" in old_contents[i]:
		stored_register = old_contents[i].split("{")[1].split("}")[0]
	if not already_patched and in_function and right_line and not done_patching:
		contents = contents[:start_of_line]
		contents.append("move-object/from16 v0, p0\n")
		contents.append("invoke-static {%s, v0}, Landroid/content/pm/PackageParser;->fillinsig(Landroid/content/pm/PackageInfo;Landroid/content/pm/PackageParser$Package;)V\n" % stored_register)
		done_patching = True
	else:
		contents.append(old_contents[i])
	i = i + 1

if already_patched:
	print(" *** This file has been already patched... Exiting.")
	exit(0)
elif not done_patching:
	print(os.linesep+"ERROR: The function to patch cannot be found, probably your version of Android is NOT supported.")
	exit(89)
elif partially_patched:
	print(" *** Previous failed patch attempt, not including the fillinsig method again...")
else:
	contents.extend(fillinsig)

f = open(to_patch, "w")
contents = "".join(contents)
f.write(contents)
f.close()
print(" *** Patching succeeded.")
