#!/usr/bin/env python3
"""Fail closed before preparing any release affected by eMudhra. No cloud writes."""
import json,re,subprocess,sys,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def ver(s): return tuple(map(int,re.search(r"(\d+)\.(\d+)\.(\d+)",s).groups()))
errors=[]
r=json.loads(subprocess.check_output(["flutter","--version","--machine"],text=True))
if ver(r["frameworkVersion"]) < (3,47,8): errors.append("Flutter must be >=3.47.8")
if ver(r["dartSdkVersion"]) < (3,13,7): errors.append("Dart must be >=3.13.7")
lock=(root/"pubspec.lock").read_text()
m=re.search(r'  cloud_firestore:.*?version: "([^" ]+)"',lock,re.S)
if not m or not (m[1] in ["6.10.1","6.10.2"] or ver(m[1]) >= (7,1,0)): errors.append("Firestore Dart lockfile is unpatched or unresolved")
pods=(root/"ios/Podfile.lock").read_text()
m=re.search(r"^  - FirebaseFirestore \(([^)]+)\)",pods,re.M)
if not m or not ((12,19,3) <= ver(m[1]) < (13,0,0) or ver(m[1]) >= (13,1,1)): errors.append("Apple Firestore Podfile.lock must be regenerated at >=12.19.3")
if shutil.disk_usage(root).free < 10*1024**3: errors.append("Less than 10 GiB free: mobile build preparation blocked")
for e in errors: print("BLOCKED:",e)
if errors: sys.exit(1)
print("Dependency/runtime preflight passed. Run full tests, native builds and device certification; publication still requires approval.")
