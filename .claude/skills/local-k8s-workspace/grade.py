#!/usr/bin/env python3
"""Grade eval outputs against assertions."""
import os, json, glob, re

WS = os.path.dirname(os.path.abspath(__file__)) + "/iteration-1"

def read_dir(path):
    """Read all text files in a directory recursively, return concatenated content."""
    content = ""
    for root, _, files in os.walk(path):
        for f in sorted(files):
            fpath = os.path.join(root, f)
            try:
                with open(fpath) as fp:
                    content += f"\n### FILE: {f} ###\n" + fp.read()
            except Exception:
                pass
    return content

def check(content, pattern, flags=re.IGNORECASE):
    return bool(re.search(pattern, content, flags))

def grade_node_postgres(content, variant):
    assertions = [
        ("secret_manifest_present",
         check(content, r"kind:\s*Secret") and check(content, r"(DB_PASSWORD|POSTGRES_PASSWORD)"),
         "Kind: Secret + password key found" if check(content, r"kind:\s*Secret") else "No Secret manifest found"),

        ("pvc_manifest_present",
         check(content, r"kind:\s*PersistentVolumeClaim"),
         "PVC manifest found" if check(content, r"kind:\s*PersistentVolumeClaim") else "No PVC found"),

        ("two_deployments_present",
         len(re.findall(r"kind:\s*Deployment", content)) >= 2,
         f"Found {len(re.findall(r'kind.*Deployment', content))} Deployment(s)"),

        ("loadbalancer_service_type",
         check(content, r"type:\s*LoadBalancer"),
         "LoadBalancer found" if check(content, r"type:\s*LoadBalancer") else "No LoadBalancer service"),

        ("readiness_probe_uses_ready_endpoint",
         check(content, r"path:\s*/ready"),
         "/ready probe found" if check(content, r"path:\s*/ready") else "Missing /ready — check readinessProbe path"),

        ("imagepullpolicy_never",
         check(content, r"imagePullPolicy:\s*Never"),
         "imagePullPolicy: Never found" if check(content, r"imagePullPolicy:\s*Never") else "imagePullPolicy: Never missing"),

        ("credentials_via_secretkeyref",
         check(content, r"secretKeyRef"),
         "secretKeyRef found" if check(content, r"secretKeyRef") else "No secretKeyRef — credentials may be hardcoded"),

        ("setup_sh_ipv4_filter",
         check(content, r"grep\s+-v\s+['\"]?:"),
         "IPv4 filter (grep -v ':') found in setup.sh" if check(content, r"grep\s+-v\s+['\"]?:") else "No IPv4 filter — MetalLB may get IPv6 subnet"),

        ("setup_sh_metallb_installed",
         check(content, r"metallb"),
         "MetalLB reference found" if check(content, r"metallb") else "MetalLB not mentioned in setup.sh"),

        ("setup_sh_kind_load",
         check(content, r"kind\s+load\s+docker-image"),
         "kind load docker-image found" if check(content, r"kind\s+load\s+docker-image") else "kind load missing"),
    ]
    return assertions

def grade_flask_redis(content, variant):
    assertions = [
        ("flask_app_deployment",
         len(re.findall(r"kind:\s*Deployment", content)) >= 1,
         "Deployment found"),

        ("redis_deployment",
         check(content, r"redis.*alpine|image:.*redis", re.IGNORECASE),
         "Redis image found" if check(content, r"redis.*alpine|image:.*redis") else "No Redis deployment"),

        ("loadbalancer_for_flask",
         check(content, r"type:\s*LoadBalancer"),
         "LoadBalancer found" if check(content, r"type:\s*LoadBalancer") else "No LoadBalancer"),

        ("clusterip_for_redis",
         check(content, r"type:\s*ClusterIP") or not check(content, r"type:\s*LoadBalancer.*6379", re.DOTALL),
         "ClusterIP for Redis (correct)" if check(content, r"type:\s*ClusterIP") else "ClusterIP not explicitly set"),

        ("redis_url_env_var",
         check(content, r"redis://redis:6379|REDIS_URL.*redis.*6379"),
         "REDIS_URL pointing to redis service found" if check(content, r"redis://redis:6379|REDIS_URL.*redis.*6379") else "REDIS_URL not found or wrong"),

        ("readiness_probe_uses_ping",
         check(content, r"path:\s*/ping"),
         "/ping probe found" if check(content, r"path:\s*/ping") else "/ping probe missing"),

        ("imagepullpolicy_never",
         check(content, r"imagePullPolicy:\s*Never"),
         "imagePullPolicy: Never found" if check(content, r"imagePullPolicy:\s*Never") else "Missing imagePullPolicy: Never"),

        ("setup_sh_metallb_installed",
         check(content, r"metallb"),
         "MetalLB found" if check(content, r"metallb") else "MetalLB not mentioned"),

        ("setup_sh_ipv4_filter",
         check(content, r"grep\s+-v\s+['\"]?:"),
         "IPv4 filter found" if check(content, r"grep\s+-v\s+['\"]?:") else "No IPv4 filter"),
    ]
    return assertions

def grade_first_time(content, variant):
    assertions = [
        ("mentions_kind_installation",
         check(content, r"kind.*install|install.*kind|curl.*kind|kind.*download|kind.*bin"),
         "kind installation mentioned" if check(content, r"kind.*install|install.*kind|curl.*kind|kind.*download|kind.*bin") else "kind installation not mentioned"),

        ("mentions_kubectl_installation",
         check(content, r"kubectl.*install|install.*kubectl|curl.*kubectl|kubectl.*download"),
         "kubectl installation mentioned" if check(content, r"kubectl.*install|install.*kubectl|curl.*kubectl|kubectl.*download") else "kubectl installation not mentioned"),

        ("generates_k8s_manifests",
         check(content, r"kind:\s*Deployment") and check(content, r"kind:\s*Service"),
         "Deployment + Service manifests found" if check(content, r"kind:\s*Deployment") else "No K8s manifests generated"),

        ("uses_loadbalancer_service",
         check(content, r"type:\s*LoadBalancer|NodePort"),
         "LoadBalancer or NodePort found" if check(content, r"type:\s*LoadBalancer|NodePort") else "No external access service found"),

        ("generates_setup_script",
         check(content, r"kind create cluster|setup\.sh|#!/bin/bash"),
         "setup.sh or automation script found" if check(content, r"kind create cluster|setup\.sh|#!/bin/bash") else "No setup script found"),

        ("mentions_metallb_for_loadbalancer",
         check(content, r"metallb|metal\s*lb"),
         "MetalLB mentioned" if check(content, r"metallb") else "MetalLB not mentioned"),

        ("imagepullpolicy_never_present",
         check(content, r"imagePullPolicy:\s*Never"),
         "imagePullPolicy: Never found" if check(content, r"imagePullPolicy:\s*Never") else "imagePullPolicy: Never missing"),
    ]
    return assertions

evals = [
    ("node-postgres-loadbalancer", grade_node_postgres),
    ("python-flask-redis", grade_flask_redis),
    ("first-time-k8s", grade_first_time),
]

for eval_name, grade_fn in evals:
    for variant in ["with_skill", "without_skill"]:
        outputs_dir = f"{WS}/{eval_name}/{variant}/outputs"
        content = read_dir(outputs_dir)
        assertions_raw = grade_fn(content, variant)

        expectations = []
        passed = 0
        for name, result, evidence in assertions_raw:
            expectations.append({"text": name, "passed": result, "evidence": evidence})
            if result:
                passed += 1

        grading = {
            "eval_name": eval_name,
            "variant": variant,
            "pass_rate": round(passed / len(expectations), 2),
            "passed": passed,
            "total": len(expectations),
            "expectations": expectations
        }

        out_path = f"{WS}/{eval_name}/{variant}/grading.json"
        with open(out_path, "w") as f:
            json.dump(grading, f, indent=2)

        print(f"{eval_name}/{variant}: {passed}/{len(expectations)} ({grading['pass_rate']*100:.0f}%)")
