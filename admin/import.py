#!/usr/bin/env python3

import requests
import subprocess
import os
import tarfile
import gzip
from sh import gunzip
import re
import shutil
import argparse
import urllib
import ssl
from tqdm import tqdm

parser = argparse.ArgumentParser(
        prog='CCDC Archive Import Tool',
        description='Tool to speed up the Proxmox import process of CCDC archive images')

parser.add_argument('-u', '--url', required=True)
parser.add_argument('-s', '--storage', required=True)
parser.add_argument('-i', '--vmid', required=True)
parser.add_argument('--router', action=argparse.BooleanOptionalAction, required=True,
                    help='For adding network interfaces: Default is True: The negation is --no-router')
args = parser.parse_args()

# Grab filename from URL
content = args.url.split('/')
file_name = content[-1]

response = requests.get(args.url, stream=True)

total_size =int(response.headers.get("content-length", 0))
block_size = 1024

if not os.path.exists(f"/tmp/{file_name}"):
    os.mkdir(f"/tmp/{file_name}")

with tqdm(total=total_size, unit="B", unit_scale=True) as progress_bar:
    with open(f"/tmp/{file_name}/{file_name}", "wb") as f:
        for data in response.iter_content(block_size):
            progress_bar.update(len(data))
            f.write(data)

print(f"[+] Extracting contents of /tmp/{file_name}/{file_name}....\n")
tar = tarfile.open(f"/tmp/{file_name}/{file_name}")
tar.extractall(path=f'/tmp/{file_name}/', filter='data')
tar.close()

found_vmdk = []
count_vmdk = 0
found_ovf = []
available_files = os.listdir(path=f'/tmp/{file_name}/')
for file in available_files:
    if "vmdk.gz" in file:
        found_vmdk.append(file)
        count_vmdk += 1
    if ".ovf" in file:
        found_ovf.append(file)
print(f"[+] Decompressing found vmdk.gz(s) in folder /tmp/{file_name}....\n")
print(f"[+] Found {count_vmdk} vmdk file(s)\n")
for gzip in found_vmdk:
    gunzip(f'/tmp/{file_name}/{gzip}')

print(f"[+] Subsituting .vmdk.gz in the found ovf file with .vmdk....\n")
for ovf in found_ovf:
    with open(f'/tmp/{file_name}/{ovf}', 'r') as f:
        content = f.read()
        content_new = re.sub(r'vmdk\.gz', 'vmdk', content)

    with open(f'/tmp/{file_name}/{ovf}', 'w') as f:
        f.write(content_new)

print(f"[+] Installing VM {file_name} on VMID:{args.vmid} and Storage: {args.storage}....\n")
subprocess.run(
        [
            "qm",
            "importovf",
            args.vmid,
            f"/tmp/{file_name}/{found_ovf[0]}",
            args.storage,
        ]
    )
print(f"[+] Is router: {args.router}. Adding network interfaces....\n")
if args.router:
    subprocess.run(
            [
                "qm",
                "set",
                args.vmid,
                "--net0",
                "model=e1000,bridge=external",
                "--net1",
                "model=e1000,bridge=internal",
            ]
            )
else:
    subprocess.run(
            [
                "qm",
                "set",
                args.vmid,
                "--net0",
                "model=e1000,bridge=internal",
            ]
            )

print(f"[+] Cleaning up....\n")
shutil.rmtree(f'/tmp/{file_name}')
