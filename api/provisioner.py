#!/usr/bin/env python3
"""
Agent Provisioner API
REST API for spawning agent clusters via Terraform

Endpoints:
  POST /clusters         - Create new cluster
  GET  /clusters         - List clusters
  GET  /clusters/<id>    - Get cluster status
  DELETE /clusters/<id>  - Destroy cluster
  POST /agents           - Add agent to existing cluster
"""

import json
import os
import subprocess
import uuid
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify
import threading

app = Flask(__name__)

# Configuration
TERRAFORM_DIR = Path("/home/ubuntu/clawd/projects/agent-infra/terraform")
STATE_DIR = Path("/home/ubuntu/clawd/projects/agent-infra/state")
STATE_DIR.mkdir(exist_ok=True)

# In-memory cluster tracking (would be in DB for production)
clusters = {}


def run_terraform(workspace: str, command: list, env: dict = None) -> dict:
    """Run a terraform command in a workspace."""
    workspace_dir = STATE_DIR / workspace
    workspace_dir.mkdir(exist_ok=True)
    
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    
    # Copy terraform files to workspace
    if not (workspace_dir / "main.tf").exists():
        subprocess.run(
            f"cp -r {TERRAFORM_DIR}/* {workspace_dir}/",
            shell=True, check=True
        )
    
    result = subprocess.run(
        ["terraform"] + command,
        cwd=workspace_dir,
        env=full_env,
        capture_output=True,
        text=True
    )
    
    return {
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr
    }


def provision_cluster_async(cluster_id: str, config: dict):
    """Background task to provision a cluster."""
    clusters[cluster_id]["status"] = "provisioning"
    
    try:
        # Initialize
        result = run_terraform(cluster_id, ["init"])
        if result["returncode"] != 0:
            clusters[cluster_id]["status"] = "failed"
            clusters[cluster_id]["error"] = result["stderr"]
            return
        
        # Apply
        tf_vars = [
            f"-var=cluster_name={cluster_id}",
            f"-var=agent_count={config.get('agent_count', 3)}",
            f"-var=agent_model={config.get('model', 'claude-sonnet-4-20250514')}",
            f"-var=use_spot={str(config.get('use_spot', True)).lower()}",
        ]
        
        # Add sensitive vars from env
        if os.environ.get("NEON_CONNECTION_STRING"):
            tf_vars.append(f"-var=neon_connection_string={os.environ['NEON_CONNECTION_STRING']}")
        if os.environ.get("ANTHROPIC_API_KEY"):
            tf_vars.append(f"-var=anthropic_api_key={os.environ['ANTHROPIC_API_KEY']}")
        
        result = run_terraform(
            cluster_id, 
            ["apply", "-auto-approve"] + tf_vars
        )
        
        if result["returncode"] == 0:
            clusters[cluster_id]["status"] = "running"
            # Get outputs
            output_result = run_terraform(cluster_id, ["output", "-json"])
            if output_result["returncode"] == 0:
                clusters[cluster_id]["outputs"] = json.loads(output_result["stdout"])
        else:
            clusters[cluster_id]["status"] = "failed"
            clusters[cluster_id]["error"] = result["stderr"]
            
    except Exception as e:
        clusters[cluster_id]["status"] = "failed"
        clusters[cluster_id]["error"] = str(e)


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy", "service": "agent-provisioner"})


@app.route("/clusters", methods=["POST"])
def create_cluster():
    """
    Create a new agent cluster.
    
    Body:
    {
        "name": "my-cluster",      // optional, auto-generated if not provided
        "agent_count": 3,          // number of agents
        "model": "claude-sonnet",  // LLM model
        "use_spot": true           // use spot instances
    }
    """
    data = request.get_json() or {}
    
    cluster_id = data.get("name", f"cluster-{uuid.uuid4().hex[:8]}")
    
    if cluster_id in clusters:
        return jsonify({"error": "Cluster already exists"}), 409
    
    clusters[cluster_id] = {
        "id": cluster_id,
        "status": "pending",
        "created_at": datetime.utcnow().isoformat(),
        "config": {
            "agent_count": data.get("agent_count", 3),
            "model": data.get("model", "claude-sonnet-4-20250514"),
            "use_spot": data.get("use_spot", True)
        }
    }
    
    # Start provisioning in background
    thread = threading.Thread(
        target=provision_cluster_async,
        args=(cluster_id, clusters[cluster_id]["config"])
    )
    thread.start()
    
    return jsonify(clusters[cluster_id]), 202


@app.route("/clusters", methods=["GET"])
def list_clusters():
    """List all clusters."""
    return jsonify(list(clusters.values()))


@app.route("/clusters/<cluster_id>", methods=["GET"])
def get_cluster(cluster_id):
    """Get cluster status."""
    if cluster_id not in clusters:
        return jsonify({"error": "Cluster not found"}), 404
    return jsonify(clusters[cluster_id])


@app.route("/clusters/<cluster_id>", methods=["DELETE"])
def destroy_cluster(cluster_id):
    """Destroy a cluster."""
    if cluster_id not in clusters:
        return jsonify({"error": "Cluster not found"}), 404
    
    clusters[cluster_id]["status"] = "destroying"
    
    def destroy_async():
        result = run_terraform(cluster_id, ["destroy", "-auto-approve"])
        if result["returncode"] == 0:
            clusters[cluster_id]["status"] = "destroyed"
        else:
            clusters[cluster_id]["status"] = "destroy_failed"
            clusters[cluster_id]["error"] = result["stderr"]
    
    thread = threading.Thread(target=destroy_async)
    thread.start()
    
    return jsonify({"message": "Destroy initiated", "cluster_id": cluster_id}), 202


@app.route("/agents", methods=["POST"])
def add_agent():
    """
    Add agent to existing cluster.
    
    Body:
    {
        "cluster_id": "my-cluster",
        "count": 1
    }
    """
    data = request.get_json() or {}
    cluster_id = data.get("cluster_id")
    count = data.get("count", 1)
    
    if not cluster_id or cluster_id not in clusters:
        return jsonify({"error": "Cluster not found"}), 404
    
    current_count = clusters[cluster_id]["config"]["agent_count"]
    new_count = current_count + count
    clusters[cluster_id]["config"]["agent_count"] = new_count
    
    # Re-apply with new count
    thread = threading.Thread(
        target=provision_cluster_async,
        args=(cluster_id, clusters[cluster_id]["config"])
    )
    thread.start()
    
    return jsonify({
        "message": f"Adding {count} agents",
        "cluster_id": cluster_id,
        "new_total": new_count
    }), 202


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
