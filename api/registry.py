#!/usr/bin/env python3
"""
Agent Registry Service
Service discovery and health monitoring for agent clusters

Endpoints:
  GET  /agents              - List all registered agents
  GET  /agents/<id>         - Get agent details
  POST /agents/<id>/heartbeat - Agent heartbeat
  GET  /agents/<id>/health  - Check agent health
  POST /agents/discover     - Discover agents by capability
"""

import json
import os
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

# Database connection
NEON_CONNECTION_STRING = os.environ.get(
    "NEON_CONNECTION_STRING",
    "postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require"
)

def get_db():
    """Get database connection."""
    return psycopg2.connect(NEON_CONNECTION_STRING)


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return jsonify({"status": "healthy", "service": "agent-registry", "db": "connected"})
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500


@app.route("/agents", methods=["GET"])
def list_agents():
    """
    List all registered agents.
    
    Query params:
      status: Filter by status (online, offline, unknown)
      model: Filter by model
    """
    status_filter = request.args.get("status")
    model_filter = request.args.get("model")
    
    query = "SELECT * FROM tq_agent_registry WHERE 1=1"
    params = []
    
    if status_filter:
        query += " AND status = %s"
        params.append(status_filter)
    
    if model_filter:
        query += " AND model ILIKE %s"
        params.append(f"%{model_filter}%")
    
    query += " ORDER BY last_seen DESC"
    
    with get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            agents = cur.fetchall()
    
    # Convert datetime objects
    for agent in agents:
        for key in ['registered_at', 'last_seen']:
            if agent.get(key):
                agent[key] = agent[key].isoformat()
    
    return jsonify(agents)


@app.route("/agents/<agent_id>", methods=["GET"])
def get_agent(agent_id):
    """Get agent details."""
    with get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT * FROM tq_agent_registry WHERE agent_id = %s",
                (agent_id,)
            )
            agent = cur.fetchone()
    
    if not agent:
        return jsonify({"error": "Agent not found"}), 404
    
    for key in ['registered_at', 'last_seen']:
        if agent.get(key):
            agent[key] = agent[key].isoformat()
    
    return jsonify(agent)


@app.route("/agents/<agent_id>/heartbeat", methods=["POST"])
def agent_heartbeat(agent_id):
    """
    Agent heartbeat - update last_seen and status.
    
    Body (optional):
    {
        "status": "online",
        "metadata": {...}
    }
    """
    data = request.get_json() or {}
    status = data.get("status", "online")
    metadata = data.get("metadata")
    
    with get_db() as conn:
        with conn.cursor() as cur:
            if metadata:
                cur.execute("""
                    UPDATE tq_agent_registry 
                    SET last_seen = NOW(), status = %s, metadata = metadata || %s::jsonb
                    WHERE agent_id = %s
                    RETURNING agent_id
                """, (status, json.dumps(metadata), agent_id))
            else:
                cur.execute("""
                    UPDATE tq_agent_registry 
                    SET last_seen = NOW(), status = %s
                    WHERE agent_id = %s
                    RETURNING agent_id
                """, (status, agent_id))
            
            result = cur.fetchone()
            conn.commit()
    
    if not result:
        return jsonify({"error": "Agent not found"}), 404
    
    return jsonify({"agent_id": agent_id, "status": status, "last_seen": datetime.utcnow().isoformat()})


@app.route("/agents/<agent_id>/health", methods=["GET"])
def check_agent_health(agent_id):
    """Check if agent is healthy (seen within last 5 minutes)."""
    with get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT agent_id, status, last_seen FROM tq_agent_registry WHERE agent_id = %s",
                (agent_id,)
            )
            agent = cur.fetchone()
    
    if not agent:
        return jsonify({"error": "Agent not found"}), 404
    
    last_seen = agent['last_seen']
    threshold = datetime.utcnow() - timedelta(minutes=5)
    
    is_healthy = last_seen > threshold if last_seen else False
    
    return jsonify({
        "agent_id": agent_id,
        "healthy": is_healthy,
        "status": agent['status'],
        "last_seen": last_seen.isoformat() if last_seen else None,
        "stale_seconds": (datetime.utcnow() - last_seen).total_seconds() if last_seen else None
    })


@app.route("/agents/discover", methods=["POST"])
def discover_agents():
    """
    Discover agents by capability or metadata.
    
    Body:
    {
        "capability": "code_review",
        "model": "claude-opus",
        "status": "online"
    }
    """
    data = request.get_json() or {}
    
    query = """
        SELECT * FROM tq_agent_registry 
        WHERE status = 'online' 
        AND last_seen > NOW() - INTERVAL '5 minutes'
    """
    params = []
    
    if data.get("model"):
        query += " AND model ILIKE %s"
        params.append(f"%{data['model']}%")
    
    if data.get("capability"):
        query += " AND metadata->>'capabilities' ILIKE %s"
        params.append(f"%{data['capability']}%")
    
    query += " ORDER BY last_seen DESC"
    
    with get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            agents = cur.fetchall()
    
    for agent in agents:
        for key in ['registered_at', 'last_seen']:
            if agent.get(key):
                agent[key] = agent[key].isoformat()
    
    return jsonify(agents)


@app.route("/agents/stale", methods=["GET"])
def list_stale_agents():
    """List agents that haven't checked in recently."""
    minutes = request.args.get("minutes", 5, type=int)
    
    with get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT agent_id, status, instance_ip, last_seen,
                       EXTRACT(EPOCH FROM (NOW() - last_seen)) as stale_seconds
                FROM tq_agent_registry 
                WHERE last_seen < NOW() - INTERVAL '%s minutes'
                   OR last_seen IS NULL
                ORDER BY last_seen ASC NULLS FIRST
            """, (minutes,))
            agents = cur.fetchall()
    
    for agent in agents:
        if agent.get('last_seen'):
            agent['last_seen'] = agent['last_seen'].isoformat()
    
    return jsonify(agents)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8081))
    app.run(host="0.0.0.0", port=port, debug=True)
