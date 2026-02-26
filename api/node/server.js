const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const { exec } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// In-memory store (replace with database later)
const clusters = new Map();
const agents = new Map();

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'agent-provisioner', timestamp: new Date().toISOString() });
});

// Spawn a new agent cluster
app.post('/clusters', async (req, res) => {
  try {
    const { count = 1, instance_type = 't3.medium', region = 'us-east-2' } = req.body;
    
    const clusterId = uuidv4();
    const cluster = {
      id: clusterId,
      count,
      instance_type,
      region,
      status: 'provisioning',
      created_at: new Date().toISOString(),
      agents: []
    };
    
    clusters.set(clusterId, cluster);
    
    // TODO: Replace with actual Terraform call when Jean's module is ready
    // For now, mock the provisioning
    console.log(`[MOCK] Would provision ${count} agents of type ${instance_type} in ${region}`);
    
    // Simulate async provisioning
    setTimeout(async () => {
      const agentIds = [];
      for (let i = 0; i < count; i++) {
        const agentId = uuidv4();
        const agent = {
          id: agentId,
          cluster_id: clusterId,
          instance_type,
          region,
          status: 'running',
          private_ip: `172.31.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}`,
          public_ip: null,
          created_at: new Date().toISOString()
        };
        agents.set(agentId, agent);
        agentIds.push(agentId);
      }
      
      cluster.agents = agentIds;
      cluster.status = 'running';
      clusters.set(clusterId, cluster);
      
      console.log(`✅ Cluster ${clusterId} provisioned with ${count} agents`);
    }, 2000);
    
    res.status(202).json({
      cluster_id: clusterId,
      status: 'provisioning',
      message: `Provisioning ${count} agent(s)`,
      poll_url: `/clusters/${clusterId}`
    });
    
  } catch (error) {
    console.error('Error spawning cluster:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get cluster status
app.get('/clusters/:id', (req, res) => {
  const cluster = clusters.get(req.params.id);
  
  if (!cluster) {
    return res.status(404).json({ error: 'Cluster not found' });
  }
  
  const agentDetails = cluster.agents.map(aid => agents.get(aid));
  
  res.json({
    ...cluster,
    agents: agentDetails
  });
});

// List all clusters
app.get('/clusters', (req, res) => {
  const allClusters = Array.from(clusters.values()).map(cluster => ({
    ...cluster,
    agent_count: cluster.agents.length
  }));
  
  res.json({ clusters: allClusters });
});

// Get agent details
app.get('/agents/:id', (req, res) => {
  const agent = agents.get(req.params.id);
  
  if (!agent) {
    return res.status(404).json({ error: 'Agent not found' });
  }
  
  res.json(agent);
});

// List all agents
app.get('/agents', (req, res) => {
  const { cluster_id, status } = req.query;
  
  let allAgents = Array.from(agents.values());
  
  if (cluster_id) {
    allAgents = allAgents.filter(a => a.cluster_id === cluster_id);
  }
  
  if (status) {
    allAgents = allAgents.filter(a => a.status === status);
  }
  
  res.json({ agents: allAgents, count: allAgents.length });
});

// Terminate an agent
app.delete('/agents/:id', async (req, res) => {
  const agent = agents.get(req.params.id);
  
  if (!agent) {
    return res.status(404).json({ error: 'Agent not found' });
  }
  
  // TODO: Actual EC2 termination via Terraform/AWS SDK
  console.log(`[MOCK] Would terminate agent ${req.params.id}`);
  
  agent.status = 'terminating';
  agents.set(req.params.id, agent);
  
  setTimeout(() => {
    agents.delete(req.params.id);
    console.log(`✅ Agent ${req.params.id} terminated`);
  }, 1000);
  
  res.json({ message: 'Agent terminating', agent_id: req.params.id });
});

// Terminate a cluster
app.delete('/clusters/:id', async (req, res) => {
  const cluster = clusters.get(req.params.id);
  
  if (!cluster) {
    return res.status(404).json({ error: 'Cluster not found' });
  }
  
  console.log(`[MOCK] Would terminate cluster ${req.params.id} and ${cluster.agents.length} agents`);
  
  cluster.status = 'terminating';
  clusters.set(req.params.id, cluster);
  
  // Terminate all agents in cluster
  for (const agentId of cluster.agents) {
    const agent = agents.get(agentId);
    if (agent) {
      agent.status = 'terminating';
      agents.set(agentId, agent);
    }
  }
  
  setTimeout(() => {
    for (const agentId of cluster.agents) {
      agents.delete(agentId);
    }
    clusters.delete(req.params.id);
    console.log(`✅ Cluster ${req.params.id} terminated`);
  }, 2000);
  
  res.json({ message: 'Cluster terminating', cluster_id: req.params.id });
});

// Integration endpoint for Terraform (called by actual terraform apply)
app.post('/terraform/callback', async (req, res) => {
  try {
    const { cluster_id, agent_id, status, metadata } = req.body;
    
    if (agent_id && agents.has(agent_id)) {
      const agent = agents.get(agent_id);
      Object.assign(agent, metadata, { status });
      agents.set(agent_id, agent);
    }
    
    if (cluster_id && clusters.has(cluster_id)) {
      const cluster = clusters.get(cluster_id);
      if (status) cluster.status = status;
      clusters.set(cluster_id, cluster);
    }
    
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Agent Provisioner API running on port ${PORT}`);
  console.log(`📋 Health: http://localhost:${PORT}/health`);
  console.log(`📊 API Docs:`);
  console.log(`   POST   /clusters        - Spawn agent cluster`);
  console.log(`   GET    /clusters        - List all clusters`);
  console.log(`   GET    /clusters/:id    - Get cluster status`);
  console.log(`   DELETE /clusters/:id    - Terminate cluster`);
  console.log(`   GET    /agents          - List all agents`);
  console.log(`   GET    /agents/:id      - Get agent details`);
  console.log(`   DELETE /agents/:id      - Terminate agent`);
});
