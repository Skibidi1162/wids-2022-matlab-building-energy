#!/usr/bin/env python3
"""Portable NSCC preparation and aggregation. Python >=3.8; stdlib only.

This program NEVER calls qsub. Rendered commands are for explicit user launch.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def read_json(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(obj, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(root=ROOT):
    checksum = root / "SHA256SUMS"
    lines = checksum.read_text(encoding="utf-8").splitlines()
    if not lines:
        raise ValueError("Empty checksum manifest")
    seen = set()
    for line in lines:
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", line)
        if not match:
            raise ValueError("Invalid checksum record")
        relative = match[2]
        path = (root / relative).resolve()
        if root.resolve() not in path.parents or relative in seen:
            raise ValueError("Unsafe or duplicate checksum path: " + relative)
        seen.add(relative)
        if not path.is_file() or sha256(path) != match[1]:
            raise ValueError("Checksum mismatch: " + relative)
    required = {"nscc.py", "data/train_y1_y5.csv", "manifests/protocol.json",
                "manifests/configurations.json", "manifests/jobs.json",
                "reference/wids_clean_split.m", "reference/wids_selected_baseline_features.csv"}
    required.update(p.relative_to(root).as_posix() for p in (root / "matlab").glob("*.m"))
    if not required <= seen:
        raise ValueError("Checksum manifest omits required payloads")
    return sha256(checksum)


def safe_tag(tag):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", tag):
        raise ValueError("run_tag must contain only letters, digits, _ or -")
    return tag


def manifests(root=ROOT):
    return (read_json(root / "manifests/configurations.json"),
            read_json(root / "manifests/jobs.json"),
            read_json(root / "manifests/protocol.json"))


def load_profile(path):
    profile = read_json(path)
    if profile.get("scheduler") != "PBS_PRO" or profile.get("allocation_confirmed") is not True:
        raise ValueError("Confirm the real PBS Pro environment and allocation in the profile first")
    if not profile.get("system", "").strip():
        raise ValueError("Set the confirmed system/hostname")
    for key in ("project", "queue"):
        value = profile.get(key, "")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", value) or re.search(r"replace|todo|example", value, re.I):
            raise ValueError("Set a real " + key)
    for key in ("cpus", "memory_gb", "max_threads"):
        if type(profile.get(key)) is not int or profile[key] < 1:
            raise ValueError("Positive integer required: " + key)
    if profile["max_threads"] > profile["cpus"]:
        raise ValueError("max_threads exceeds allocated cpus")
    if not re.fullmatch(r"[0-9]{2,3}:[0-5][0-9]:[0-5][0-9]", profile.get("walltime", "")):
        raise ValueError("walltime must use HH:MM:SS")
    if profile["walltime"] == "00:00:00":
        raise ValueError("walltime must be positive")
    if not isinstance(profile.get("modules"), list) or not all(isinstance(m, str) and m for m in profile["modules"]):
        raise ValueError("modules must be an array of exact module names")
    if any("runtime" in m.lower() for m in profile["modules"]):
        raise ValueError("MATLAB Runtime cannot execute these .m training scripts; identify full MATLAB")
    if not isinstance(profile.get("matlab_executable"), str) or not profile["matlab_executable"]:
        raise ValueError("Set matlab_executable to an executable name or absolute path")
    safe_tag(profile.get("run_tag", ""))
    for value in (profile["matlab_executable"], profile.get("modules_init", ""), *profile["modules"]):
        if "\n" in value or "\r" in value or "\x00" in value:
            raise ValueError("Newlines and NULs are not permitted in profile values")
    return profile


def expected_validation(root=ROOT):
    truths = {1: [], 2: []}
    counts = {year: 0 for year in range(1, 6)}
    seen = set()
    with (root / "data/train_y1_y5.csv").open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            year = int(row["Year_Factor"])
            if year not in counts:
                raise ValueError("Reserved year or unknown year in historical extract")
            counts[year] += 1
            identifier = int(row["id"])
            if identifier in seen:
                raise ValueError("Duplicate source ID")
            seen.add(identifier)
            if year in (4, 5):
                y = float(row["site_eui"])
                if not math.isfinite(y):
                    raise ValueError("Nonfinite validation target")
                truths[year - 3].append((identifier, y))
    if sum(counts.values()) != 53308 or sum(counts[y] for y in (1, 2, 3)) != 22054 or counts[4] != 12946 or counts[5] != 18308:
        raise ValueError("Historical row counts differ from frozen folds")
    return truths


def checked_result(root, run_root, job, config, context, truth):
    directory = run_root / "jobs" / ("job_%04d" % job["JobID"])
    marker = directory / "result.json"
    if not marker.is_file():
        return None, "missing"
    try:
        result = read_json(marker)
        identity = result["Identity"]
        if result["Status"] != "complete" or identity != {"Context": context, "Job": job, "Config": config}:
            raise ValueError("completion identity mismatch")
        predictions = directory / "predictions.csv"
        if result["PredictionsSHA256"] != sha256(predictions):
            raise ValueError("prediction checksum mismatch")
        squared, absolute = [], []
        with predictions.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != ["id", "site_eui", "prediction"]:
                raise ValueError("prediction schema mismatch")
            for index, row in enumerate(reader):
                if index >= len(truth):
                    raise ValueError("extra validation rows")
                identifier, target = truth[index]
                actual = float(row["site_eui"])
                prediction = float(row["prediction"])
                if int(row["id"]) != identifier or not math.isclose(actual, target, rel_tol=1e-13, abs_tol=1e-12):
                    raise ValueError("validation ID/order/target mismatch")
                if not math.isfinite(prediction):
                    raise ValueError("nonfinite prediction")
                error = prediction - target
                squared.append(error * error)
                absolute.append(abs(error))
        if len(squared) != len(truth):
            raise ValueError("missing validation rows")
        n, sse, sae = len(truth), math.fsum(squared), math.fsum(absolute)
        if result["N"] != n or result["NFit"] != (22054 if job["FoldIndex"] == 1 else 35000):
            raise ValueError("sample counts mismatch")
        if not isinstance(result.get("FitSeconds"), (int, float)) or not math.isfinite(result["FitSeconds"]) or result["FitSeconds"] < 0:
            raise ValueError("invalid fit duration")
        for key, expected in (("SSE", sse), ("SAE", sae), ("RMSE", math.sqrt(sse/n)), ("MAE", sae/n)):
            actual = result[key]
            if isinstance(actual, bool) or not isinstance(actual, (int, float)) or not math.isfinite(actual) or not math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-8):
                raise ValueError("metric mismatch: " + key)
        return result, "complete"
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as error:
        return None, "invalid: " + str(error)


def write_csv(path, rows, fields):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fields)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def aggregate(root=ROOT, tag="cpu_pilot_01", write=True):
    fingerprint = verify(root)
    configs, jobs, _ = manifests(root)
    run_root = root / "results" / safe_tag(tag)
    probe = read_json(run_root / "probe.json")
    context = probe["Context"]
    if not probe.get("Ready") or context.get("PackageSHA256") != fingerprint or context.get("RunTag") != tag:
        raise ValueError("Successful matching probe not found")
    truth = expected_validation(root)
    rows, details = [], []
    for config in configs:
        selected = [j for j in jobs if j["ConfigID"] == config["ID"]]
        if len(selected) != 2 or sorted(j["FoldIndex"] for j in selected) != [1, 2]:
            raise ValueError("Configuration must have exactly two temporal jobs")
        results = []
        for job in sorted(selected, key=lambda j: j["FoldIndex"]):
            result, status = checked_result(root, run_root, job, config, context, truth[job["FoldIndex"]])
            details.append({"JobID": job["JobID"], "ConfigID": config["ID"], "FoldIndex": job["FoldIndex"], "Status": status})
            if result is not None:
                results.append(result)
        row = {"ConfigID": config["ID"], "Stage": config["Stage"], "Family": config["Family"],
               "CompletedFolds": len(results), "Status": "complete" if len(results) == 2 else "incomplete"}
        if len(results) == 2:
            n = sum(r["N"] for r in results)
            sse, sae = math.fsum(r["SSE"] for r in results), math.fsum(r["SAE"] for r in results)
            row.update(N=n, SSE=sse, SAE=sae, PooledRMSE=math.sqrt(sse/n), PooledMAE=sae/n,
                       Year4RMSE=results[0]["RMSE"], Year5RMSE=results[1]["RMSE"],
                       FitSeconds=sum(r["FitSeconds"] for r in results))
        rows.append(row)
    if write:
        fields = ["ConfigID", "Stage", "Family", "CompletedFolds", "Status", "N", "SSE", "SAE", "PooledRMSE", "PooledMAE", "Year4RMSE", "Year5RMSE", "FitSeconds"]
        write_csv(run_root / "all_configurations.csv", rows, fields)
        write_csv(run_root / "job_status.csv", details, ["JobID", "ConfigID", "FoldIndex", "Status"])
        for stage, filename in (("compare", "leaderboard.csv"), ("pilot", "pilot_leaderboard.csv")):
            ranked = sorted((r for r in rows if r["Status"] == "complete" and r["Stage"] == stage),
                            key=lambda r: (r["PooledRMSE"], r["PooledMAE"], r["ConfigID"]))
            write_csv(run_root / filename, ranked, fields)
        complete = sum(r["Status"] == "complete" for r in rows)
        write_json(run_root / "aggregation_status.json", {
            "Context": context, "CompleteConfigurations": complete, "ExpectedConfigurations": len(configs),
            "ComparisonComplete": all(r["Status"] == "complete" for r in rows if r["Stage"] == "compare"),
            "RankingScope": "Only configurations with both verified folds; provisional until comparison complete",
            "Metrics": "sqrt(sum(SSE)/sum(N)); sum(SAE)/sum(N); original site_eui units",
            "IndependentTest": False})
    return rows, details


def pbs_text(profile, root_text, fingerprint, job):
    """Build a single-node CPU PBS script; no scheduler calls."""
    root_text = str(root_text)
    if not root_text.startswith('/') or re.search(r"[\s#'\"\\]", root_text):
        raise ValueError("Upload into an absolute Linux path without spaces, quotes, #, or backslashes")
    scheduler_logs = root_text + '/results/' + profile['run_tag'] + '/scheduler'
    label = "probe" if job is None else "job_%04d" % job["JobID"]
    function = "nscc_probe" if job is None else "nscc_run_job"
    thread_count = str(profile["max_threads"])
    lines = ["#!/bin/bash -l", "#PBS -N wids_" + label, "#PBS -P " + profile["project"],
             "#PBS -q " + profile["queue"],
             "#PBS -l select=1:ncpus=%d:mem=%dgb" % (profile["cpus"], profile["memory_gb"]),
             "#PBS -l walltime=" + profile["walltime"], "#PBS -j oe",
             "#PBS -o " + scheduler_logs + '/' + label + '.log', "", "set -euo pipefail",
             "cd -- " + shlex.quote(root_text),
             "test -n \"${PBS_JOBID:-}\" || { echo 'Run through PBS on a compute node'; exit 2; }"]
    if profile.get("modules_init"):
        lines.append("source " + shlex.quote(profile["modules_init"]))
    if profile["modules"]:
        lines.extend(["type module >/dev/null 2>&1 || { echo 'Initialize the site module command'; exit 2; }",
                      "module load " + " ".join(shlex.quote(m) for m in profile["modules"]), "module list 2>&1"])
    lines += ["export WIDS_RUN_TAG=" + shlex.quote(profile["run_tag"]),
              "export WIDS_MAX_THREADS=" + thread_count, "export WIDS_EXPECTED_PACKAGE=" + fingerprint,
              "export OMP_NUM_THREADS=" + thread_count, "export MKL_NUM_THREADS=" + thread_count,
              "export OPENBLAS_NUM_THREADS=" + thread_count,
              "export WIDS_JOB_ID=" + (str(job["JobID"]) if job else "0"),
              "command -v " + shlex.quote(profile["matlab_executable"]) + " >/dev/null || { echo 'Full MATLAB executable not found; Runtime is insufficient'; exit 2; }",
              "hostname", "date -u", "ulimit -a"]
    matlab_command = shlex.quote(profile["matlab_executable"]) + " -batch " + shlex.quote("addpath('matlab'); " + function)
    lines += ["if test -x /usr/bin/time; then",
              "  /usr/bin/time -v -o " + shlex.quote(scheduler_logs + '/' + label + '.time.txt') + " " + matlab_command,
              "else", "  " + matlab_command, "fi", ""]
    return '\n'.join(lines)


def render(profile_path, kind, job_id=None, root=ROOT):
    fingerprint = verify(root)
    profile = load_profile(profile_path)
    # PBS directive paths are parsed differently across installations; avoid ambiguity.
    if not str(root).startswith('/') or re.search(r"[\s#'\"\\]", str(root)):
        raise ValueError("Upload into a Linux path without spaces, quotes, #, or backslashes before rendering PBS jobs")
    configs, jobs, _ = manifests(root)
    config_by_id = {c["ID"]: c for c in configs}
    run_root = root / "results" / profile["run_tag"]
    if kind != "probe":
        probe = read_json(run_root / "probe.json")
        if (not probe.get("Ready") or probe["Context"]["PackageSHA256"] != fingerprint
                or probe["Context"]["Threads"] != profile["max_threads"]
                or probe["Context"]["RunTag"] != profile["run_tag"]):
            raise ValueError("Run and inspect a matching successful compute-node probe first")
    if kind == "compare":
        rows, _ = aggregate(root, profile["run_tag"], write=False)
        if any(r["Status"] != "complete" for r in rows if r["Stage"] == "pilot"):
            raise ValueError("Complete both folds of all four CPU pilots before rendering comparison jobs")
    selected = [None] if kind == "probe" else [j for j in jobs if config_by_id[j["ConfigID"]]["Stage"] == kind]
    if job_id is not None:
        selected = [j for j in selected if j and j["JobID"] == job_id]
        if not selected:
            raise ValueError("Requested job ID does not belong to this stage")
    output = root / "generated" / profile["run_tag"] / kind
    output.mkdir(parents=True, exist_ok=True)
    scheduler_logs = run_root / "scheduler"
    scheduler_logs.mkdir(parents=True, exist_ok=True)
    commands = []
    for job in selected:
        label = "probe" if job is None else "job_%04d" % job["JobID"]
        path = output / (label + ".pbs")
        with path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(pbs_text(profile,str(root),fingerprint,job))
        commands.append("qsub " + shlex.quote(str(path)))
    (output / "COMMANDS.txt").write_text("\n".join(commands) + "\n", encoding="utf-8")
    write_json(output / "render_context.json", {"Profile": profile, "PackageSHA256": fingerprint, "Kind": kind})
    return commands


def discover(root=ROOT):
    # Login-node metadata only. No MATLAB, model training, job submission, or GPU initialization.
    records = ["NSCC read-only discovery", "Hostname: " + socket.getfqdn(), "Platform: " + sys.platform,
               "Python: " + sys.version.split()[0]]
    commands = [["uname", "-a"], ["qstat", "-Bf"], ["qstat", "-Q"],
                ["bash", "-lc", "type module; module list 2>&1; module avail matlab 2>&1; command -v matlab"]]
    for command in commands:
        records.append("\n$ " + " ".join(shlex.quote(s) for s in command))
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=20, check=False)
            records.append(result.stdout + result.stderr + "\nexit=" + str(result.returncode))
        except (OSError, subprocess.TimeoutExpired) as error:
            records.append(str(error))
    directory = root / "results" / "discovery"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".txt")
    path.write_text("\n".join(records) + "\n", encoding="utf-8")
    print(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("verify", help="Check frozen code/data hashes")
    sub.add_parser("discover", help="Read-only remote login-node metadata; no MATLAB")
    p = sub.add_parser("render", help="Write PBS scripts and commands; NEVER submits")
    p.add_argument("--profile", type=Path, required=True)
    p.add_argument("--kind", choices=("probe", "pilot", "compare"), required=True)
    p.add_argument("--job", type=int)
    p = sub.add_parser("aggregate", help="Validate prediction rows and pool complete two-fold configurations")
    p.add_argument("--run-tag", required=True)
    args = parser.parse_args()
    try:
        if args.action == "verify":
            print("Verified package SHA256: " + verify())
        elif args.action == "discover":
            discover()
        elif args.action == "render":
            print("Rendered only; review before launching one command at a time:\n" + "\n".join(render(args.profile, args.kind, args.job)))
        else:
            rows, details = aggregate(tag=args.run_tag)
            complete = [r for r in rows if r["Status"] == "complete"]
            print("Verified complete configurations: %d/%d; validation rows per complete configuration: 31254" % (len(complete), len(rows)))
            print("Results: " + str(ROOT / "results" / args.run_tag))
            invalid = [d for d in details if d["Status"].startswith("invalid")]
            if invalid:
                print("Invalid jobs excluded: " + ", ".join(str(d["JobID"]) for d in invalid))
                return 2
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("STOP: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
