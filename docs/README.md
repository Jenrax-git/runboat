# Project Documentation

This folder contains the documentation for the runboat-app project.

## Available Documents

### 📋 [DIGITAL_OCEAN_REGISTRY_SETUP.md](./DIGITAL_OCEAN_REGISTRY_SETUP.md)
Complete guide to configure Docker build automation with Digital Ocean Container Registry and GitHub Actions, including tag management.

**Includes:**
- Container Registry Setup
- Access Token Creation
- GitHub Secrets Configuration
- GitHub Actions Workflow
- Automatic Tag System
- Version Management (SemVer)
- Using Images in Kubernetes
- Deployment Strategies
- Troubleshooting

## Development Workflow

1. **Initial Setup**: Follow [DIGITAL_OCEAN_REGISTRY_SETUP.md](./DIGITAL_OCEAN_REGISTRY_SETUP.md)
2. **Daily Development**: Work on the `main-jenrax` branch
3. **Version Management**: Check the tags section in the main document
4. **Deployment**: Use appropriate tags according to environment

## Quick Commands

```bash
# View available tags
doctl registry repository list-tags runboat-app

# Create new version
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# Update deployment
kubectl set image deployment/runboat-app runboat-app=registry.digitalocean.com/jenrax-registry/runboat-app:1.0.0
```

## Useful Links

- [Digital Ocean Container Registry](https://cloud.digitalocean.com/registry)
- [GitHub Actions](https://github.com/features/actions)
- [Semantic Versioning](https://semver.org/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
