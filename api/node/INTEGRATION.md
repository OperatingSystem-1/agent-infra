# Integration Guide for Jean's Terraform

## Current State
The API is **working with mocked responses**. All endpoints functional.

## What Needs to Change

### 1. Replace Mock Provisioning (Line ~40 in server.js)

**Current (mock):**
```javascript
// TODO: Replace with actual Terraform call when Jean's module is ready
console.log(`[MOCK] Would provision ${count} agents...`);
setTimeout(async () => { /* mock agents */ }, 2000);
```

**Replace with:**
```javascript
const { spawn } = require('child_process');
const terraformDir = path.join(__dirname, '../terraform'); // Jean's terraform modules

// Create terraform.tfvars
const tfvars = `
agent_count     = ${count}
instance_type   = "${instance_type}"
region          = "${region}"
cluster_id      = "${clusterId}"
`;

await fs.writeFile(path.join(terraformDir, 'terraform.tfvars'), tfvars);

// Run terraform apply
const terraform = spawn('terraform', [
  'apply',
  '-auto-approve',
  '-var-file=terraform.tfvars'
], { cwd: terraformDir });

terraform.stdout.on('data', (data) => {
  console.log(`[Terraform] ${data}`);
});

terraform.stderr.on('data', (data) => {
  console.error(`[Terraform Error] ${data}`);
});

terraform.on('close', (code) => {
  if (code === 0) {
    // Parse terraform output to get agent IPs/IDs
    // Update cluster status to 'running'
    cluster.status = 'running';
    clusters.set(clusterId, cluster);
  } else {
    cluster.status = 'failed';
    clusters.set(clusterId, cluster);
  }
});
```

### 2. Parse Terraform Outputs

Jean's Terraform should output JSON with agent details:

```hcl
# outputs.tf
output "agents" {
  value = [
    for instance in aws_instance.agent : {
      id         = instance.id
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  ]
}
```

Then in server.js:
```javascript
const terraformOutput = spawn('terraform', ['output', '-json'], { cwd: terraformDir });
let outputData = '';

terraformOutput.stdout.on('data', (data) => {
  outputData += data.toString();
});

terraformOutput.on('close', () => {
  const outputs = JSON.parse(outputData);
  const agentList = outputs.agents.value;
  
  // Store agents in our registry
  for (const agentData of agentList) {
    const agent = {
      id: agentData.id,
      cluster_id: clusterId,
      private_ip: agentData.private_ip,
      public_ip: agentData.public_ip,
      status: 'running'
    };
    agents.set(agent.id, agent);
    cluster.agents.push(agent.id);
  }
});
```

### 3. Agent Termination (Line ~150)

**Replace mock with:**
```javascript
const terraform = spawn('terraform', [
  'destroy',
  '-auto-approve',
  '-target', `aws_instance.agent["${agentId}"]`
], { cwd: terraformDir });
```

### 4. Directory Structure

```
/home/ubuntu/clawd/
├── agent-provisioner-api/     # This API (Jared's work)
│   ├── server.js
│   └── package.json
└── terraform/                  # Jean's Terraform modules
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── modules/
        └── agent/
```

### 5. Environment Variables

Create `.env`:
```bash
TERRAFORM_DIR=/home/ubuntu/clawd/terraform
AWS_REGION=us-east-2
NODE_ENV=production
```

Load in server.js:
```javascript
require('dotenv').config();
const terraformDir = process.env.TERRAFORM_DIR || path.join(__dirname, '../terraform');
```

## Testing Integration

1. Jean finishes Terraform module
2. Move it to `/home/ubuntu/clawd/terraform/`
3. Test manually: `cd /home/ubuntu/clawd/terraform && terraform init && terraform apply`
4. Update `server.js` with real Terraform calls
5. Restart API: `node server.js`
6. Test: `./test-api.sh`

## Expected Timeline

- **Hour 2 (now):** Jean finishing Terraform + Packer
- **Hour 3:** Integration (replace mocks)
- **Hour 4:** End-to-end testing
- **Hour 5:** Bug fixes + refinement
- **Hour 6:** Demo

## Questions for Jean

1. What's the path to your Terraform modules?
2. What outputs will you provide (agent IPs, instance IDs)?
3. Do you need the API to pass any other variables (security group IDs, subnet IDs)?
4. Should we use Terraform Cloud/remote state, or local state files?
