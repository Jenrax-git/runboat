# Digital Ocean Container Registry Setup and Tag Management

This document explains how to configure Docker build automation to push images to Digital Ocean Container Registry and how to manage automatic tags.

## Prerequisites

1. A Digital Ocean account
2. A GitHub repository (fork of the original repository)
3. Access to repository secrets
4. Work on the `main-jenrax` branch to keep the fork separate

## Container Registry Setup

### Step 1: Create Container Registry in Digital Ocean

1. Go to [Digital Ocean Container Registry](https://cloud.digitalocean.com/registry)
2. Click "Create Registry"
3. Choose a region close to your location
4. Give it a name (e.g., `jenrax-registry`)
5. Select the plan you need
6. Click "Create Registry"

### Step 2: Create Access Token in Digital Ocean

1. Go to [Digital Ocean API Tokens](https://cloud.digitalocean.com/account/api/tokens)
2. Click "Generate New Token"
3. Give it a descriptive name (e.g., "GitHub Actions Registry Access")
4. Make sure it has write permissions
5. Copy the generated token (you'll need it in the next step)

### Step 3: Configure Secrets in GitHub

In your GitHub repository, go to **Settings > Secrets and variables > Actions** and add the following secrets:

#### `DO_ACCESS_TOKEN`
The access token you created in Digital Ocean.

#### `DO_REGISTRY_NAME`
The name of your registry (without the domain). For example, if your registry is called `jenrax-registry`, this value would be `jenrax-registry`.

### Step 4: Configure the Workflow

You already have a configured workflow (`docker-build-do.yml`) that includes:

- Automatic tag management
- Build cache for faster builds
- Semantic versioning support
- Advanced and flexible configuration

### Step 5: Activate the Workflow

1. Commit and push the workflow files to your repository
2. The workflow will run automatically on:
   - Push to the `main-jenrax` branch
   - Pull requests to `main-jenrax`
   - Tags starting with `v`

## Automatic Tag System

The `docker-build-do.yml` workflow automatically generates different types of tags based on the event that triggers it:

### 1. **Branch Tags**
```yaml
type=ref,event=branch
```
- **Format**: `{branch-name}`
- **Example**: `main-jenrax`
- **When generated**: Push to any branch
- **Use**: Identify builds from specific branches

### 2. **Pull Request Tags**
```yaml
type=ref,event=pr
```
- **Format**: `pr-{pr-number}`
- **Example**: `pr-123`
- **When generated**: PR creation or updates
- **Use**: PR testing without affecting main tags

### 3. **Semantic Version Tags**
```yaml
type=semver,pattern={{version}}
type=semver,pattern={{major}}.{{minor}}
```
- **Format**: 
  - `{major}.{minor}.{patch}` (e.g., `1.0.0`)
  - `{major}.{minor}` (e.g., `1.0`)
- **When generated**: Push of tags starting with `v`
- **Use**: Official releases and stable versions

### 4. **Commit SHA Tags**
```yaml
type=sha,prefix=sha-
```
- **Format**: `sha-{short-sha}`
- **Example**: `sha-d9bd5e1`
- **When generated**: All pushes
- **Use**: Exact code traceability

### 5. **Latest Tag**
```yaml
type=raw,value=latest,enable={{is_default_branch}}
```
- **Format**: `latest`
- **When generated**: Only on the main branch
- **Use**: Most recent version for development

## How to Create Version Tags

### **Option 1: Local Tag (Recommended)**
```bash
# Create annotated tag (recommended)
git tag -a v1.0.0 -m "Release version 1.0.0"

# Create simple tag
git tag v1.0.0

# Push the tag
git push origin v1.0.0
```

### **Option 2: Tag from GitHub**
1. Go to your repository on GitHub
2. Click "Releases" in the right panel
3. Click "Create a new release"
4. Write the tag (e.g., `v1.0.0`)
5. Add title and description
6. Publish the release

### **Option 3: Tag with Specific Commit**
```bash
git tag -a v1.0.0 <commit-hash> -m "Release version 1.0.0"
git push origin v1.0.0
```

## Versioning Conventions

### **Semantic Versioning (SemVer)**
- **MAJOR.MINOR.PATCH** (e.g., `1.0.0`)
- **MAJOR**: Incompatible changes with previous versions
- **MINOR**: New backward-compatible features
- **PATCH**: Backward-compatible bug fixes

### **Tag Examples**
```bash
# First stable version
git tag v1.0.0

# Bug fix
git tag v1.0.1

# New feature
git tag v1.1.0

# Major change (breaking changes)
git tag v2.0.0
```

## Using Images in Kubernetes

### **For Development**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runboat-app-dev
spec:
  template:
    spec:
      containers:
      - name: runboat-app
        image: registry.digitalocean.com/jenrax-registry/runboat-app:latest
```

### **For Staging**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runboat-app-staging
spec:
  template:
    spec:
      containers:
      - name: runboat-app
        image: registry.digitalocean.com/jenrax-registry/runboat-app:main-jenrax
```

### **For Production**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runboat-app-prod
spec:
  template:
    spec:
      containers:
      - name: runboat-app
        image: registry.digitalocean.com/jenrax-registry/runboat-app:1.0.0
```

## Useful Commands

### **List Available Tags**
```bash
# View all repositories
doctl registry repository list

# View tags for a specific repository
doctl registry repository list-tags runboat-app
```

### **Pull Images Locally**
```bash
# Pull latest
docker pull registry.digitalocean.com/jenrax-registry/runboat-app:latest

# Pull specific version
docker pull registry.digitalocean.com/jenrax-registry/runboat-app:1.0.0

# Pull branch tag
docker pull registry.digitalocean.com/jenrax-registry/runboat-app:main-jenrax
```

### **Delete Tags (if needed)**
```bash
# Delete local tag
git tag -d v1.0.0

# Delete remote tag
git push origin --delete v1.0.0
```

## Deployment Strategies

### **Blue-Green Deployment**
```yaml
# Blue (current version)
image: registry.digitalocean.com/jenrax-registry/runboat-app:1.0.0

# Green (new version)
image: registry.digitalocean.com/jenrax-registry/runboat-app:1.1.0
```

### **Rolling Update**
```bash
# Update gradually
kubectl set image deployment/runboat-app runboat-app=registry.digitalocean.com/jenrax-registry/runboat-app:1.1.0
```

### **Rollback**
```bash
# Rollback to previous version
kubectl rollout undo deployment/runboat-app
```

## Release Workflow

1. **Development** on `main-jenrax` branch
2. **Testing** with PR tags
3. **Staging** with branch tag
4. **Release** with semantic tag
5. **Production** with specific version tag

## Complete Example

```bash
# 1. Develop on branch
git checkout main-jenrax
git pull origin main-jenrax

# 2. Make changes and commit
git add .
git commit -m "Add new feature X"
git push origin main-jenrax

# 3. Create PR (optional)
# Workflow will generate pr-123 tag

# 4. Merge to main-jenrax
# Workflow will generate main-jenrax and latest tags

# 5. Create release
git tag -a v1.1.0 -m "Release version 1.1.0 with feature X"
git push origin v1.1.0

# 6. Workflow will generate 1.1.0 and 1.1 tags

# 7. Update production
kubectl set image deployment/runboat-app runboat-app=registry.digitalocean.com/jenrax-registry/runboat-app:1.1.0
```

## Troubleshooting

### **Authentication Error**
- Verify that `DO_ACCESS_TOKEN` is correct
- Make sure the token has write permissions

### **Registry Not Found Error**
- Verify that `DO_REGISTRY_NAME` is correct
- Confirm the registry exists in Digital Ocean

### **Build Fails**
- Check workflow logs in GitHub Actions
- Verify the Dockerfile is valid

### **Tag Not Found**
```bash
# Verify tag exists
doctl registry repository list-tags runboat-app

# Check workflow in GitHub Actions
# Go to Actions > Build and Push to Digital Ocean Registry
```

### **Image Not Updating**
```bash
# Force image pull
kubectl patch deployment runboat-app -p '{"spec":{"template":{"metadata":{"annotations":{"date":"'$(date +%s)'"}}}}}'
```

### **Invalid Tag**
- Verify tag follows format `v{major}.{minor}.{patch}`
- Ensure workflow ran successfully

## Best Practices

1. **Use annotated tags** for important releases
2. **Follow Semantic Versioning** strictly
3. **Document changes** in tag messages
4. **Test in staging** before production
5. **Keep tags clean** by removing obsolete versions
6. **Use specific tags** in production, not `latest`

## Costs

- Digital Ocean Container Registry has a monthly cost based on storage
- GitHub Actions builds are free for public repositories
- For private repositories, GitHub Actions has free monthly limits
