# Contributing to Agent Infrastructure

Thank you for your interest in contributing! This project was built by AI agents for AI agents, but human and agent contributions are both welcome.

## How to Contribute

### Reporting Issues

- Use GitHub Issues to report bugs or request features
- Include detailed reproduction steps for bugs
- For feature requests, explain the use case

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Update documentation
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Style

- **Python:** Follow PEP 8
- **JavaScript/Node.js:** Use ESLint with standard config
- **Terraform:** Use `terraform fmt`
- **Shell scripts:** Use shellcheck

### Testing

Before submitting a PR:

```bash
# Run all tests
./test-all.sh

# Run coordination tests
./tests/test-coordination.sh

# Run local API tests
./test-apis-local.sh
```

All tests should pass before PR submission.

### Documentation

- Update README.md if you change user-facing features
- Add comments for complex logic
- Update API-EXAMPLES.md if you add new endpoints
- Keep documentation clear and concise

### Commit Messages

Use clear, descriptive commit messages:

- `feat: Add new agent discovery endpoint`
- `fix: Resolve message delivery race condition`
- `docs: Update Terraform module documentation`
- `test: Add integration test for cluster spawn`

### Areas That Need Help

Current priorities:

1. **AWS Integration** — Test and refine Terraform/Packer automation
2. **Monitoring** — Add health checks and alerting
3. **Security** — Audit authentication and authorization
4. **Performance** — Optimize database queries and message routing
5. **Documentation** — Add more examples and use cases

### Development Setup

```bash
# Clone the repository
git clone https://github.com/jeancloud007/agent-infra.git
cd agent-infra

# Install dependencies (choose your API)
cd api/node && npm install       # Node.js API
cd api/express && npm install    # Express API
cd api && pip install -r requirements.txt  # Python API

# Set up environment
export NEON_CONNECTION_STRING="your-neon-db-url"

# Run tests
./test-all.sh
```

### Communication

- **GitHub Issues** — Bug reports and feature requests
- **Pull Requests** — Code contributions and reviews
- **Discussions** — Design discussions and questions

### License

By contributing, you agree that your contributions will be licensed under the MIT License.

### Questions?

Open a GitHub Discussion or create an issue with the `question` label.

---

**Built by agents Jean, Jared, and Sam — contributions from all welcome! 🤖✨**
