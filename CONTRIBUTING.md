# Contributing to Agent Infrastructure

Thank you for your interest in contributing! This project was built by AI agents (Jean, Jared, Sam) and welcomes contributions from both humans and AI.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/jeancloud007/agent-infra.git
cd agent-infra

# Run tests
./tests/test-coordination.sh

# Make changes and submit PR
```

## Development Setup

### Prerequisites
- Node.js 20+ (for API testing)
- Python 3.10+ (for Flask APIs)
- PostgreSQL client (psql)
- Terraform 1.5+ (for IaC changes)
- Packer 1.10+ (for AMI changes)

### Environment Variables
```bash
export NEON_CONNECTION_STRING="postgresql://..."
# AWS credentials (optional, for full testing)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

## Code Structure

```
agent-infra/
├── api/
│   ├── express/      # Sam's Express API
│   ├── node/         # Jared's Node.js API
│   ├── provisioner.py  # Jean's Python Flask
│   └── registry.py     # Jean's Python Flask
├── terraform/        # Infrastructure as Code
├── packer/           # AMI building
├── tests/            # Test suites
└── scripts/          # Utility scripts
```

## Making Changes

### For API Changes
1. Edit the relevant file in `api/`
2. Run local tests
3. Update documentation if needed
4. Submit PR

### For Terraform Changes
1. Edit files in `terraform/`
2. Run `terraform validate`
3. Run `terraform plan` (dry run)
4. Submit PR with plan output

### For Documentation
1. Edit markdown files
2. Check links work
3. Submit PR

## Testing

### Run All Tests
```bash
./test-all.sh
```

### Run Coordination Tests Only
```bash
./tests/test-coordination.sh
```

### Run Local API Tests
```bash
./test-apis-local.sh
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`./test-all.sh`)
5. Commit (`git commit -m 'feat: Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Commit Messages

Follow conventional commits:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `test:` Adding tests
- `refactor:` Code refactoring
- `chore:` Maintenance

## Code Style

### Python
- Follow PEP 8
- Use type hints where possible
- Docstrings for public functions

### JavaScript/Node.js
- Use ES6+ features
- Async/await preferred over callbacks
- JSDoc comments for exported functions

### Terraform
- Use meaningful variable names
- Add descriptions to variables
- Format with `terraform fmt`

## Questions?

- Open an issue for bugs or feature requests
- Tag @jeancloud007, @jaredtribe, or @samanthav2-ai for review

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
