# Automated Gem Release Guide

Complete guide to setting up automated Ruby gem releases using GitHub Actions and git tags.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [GitHub Actions Workflow](#github-actions-workflow)
5. [RubyGems Authentication](#rubygems-authentication)
6. [Release Process](#release-process)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Overview

This guide shows how to automate gem releases so that:
- **Pushing a git tag** (e.g., `v1.2.3`) triggers an automated release
- **GitHub Actions** validates, builds, and publishes the gem
- **No manual `gem push`** required

### Benefits

✅ **Consistent releases** - Same process every time
✅ **Version validation** - Tag must match gem version
✅ **CI/CD integration** - Tests run before release
✅ **Security** - API keys stored in GitHub Secrets
✅ **Audit trail** - All releases tracked in GitHub

## Prerequisites

### 1. RubyGems Account

Create an account at https://rubygems.org if you don't have one.

### 2. Gem Ownership

You must own the gem name or it must be available:

```bash
# Check if name is available
gem search ^your-gem-name$ --remote

# If gem exists, check ownership
gem owner your-gem-name

# Request ownership (if gem is abandoned)
# Visit: https://rubygems.org/gems/your-gem-name
```

### 3. Gem Structure

Your gem should have:

```
your-gem/
├── .github/
│   └── workflows/
│       └── release.yml       # ← We'll create this
├── lib/
│   └── your_gem/
│       └── version.rb         # ← Must have VERSION constant
├── your-gem.gemspec           # ← Gem specification
├── Gemfile
└── README.md
```

## Initial Setup

### Step 1: Version File

Create `lib/your_gem/version.rb`:

```ruby
# frozen_string_literal: true

module YourGem
  VERSION = "0.1.0"
end
```

### Step 2: Gemspec File

Create `your-gem.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/your_gem/version"

Gem::Specification.new do |spec|
  spec.name = "your-gem"
  spec.version = YourGem::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]

  spec.summary = "Brief description"
  spec.description = "Longer description"
  spec.homepage = "https://github.com/yourusername/your-gem"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released
  spec.files = Dir.glob(%w[
    lib/**/*.rb
    lib/**/*.json
    sig/**/*.rbs
    *.md
    LICENSE.txt
  ]).reject { |f| File.directory?(f) }

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  # spec.add_dependency "example-gem", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
end
```

### Step 3: Test Local Build

```bash
# Build the gem locally
gem build your-gem.gemspec

# Test installation
gem install ./your-gem-0.1.0.gem

# Clean up
rm your-gem-0.1.0.gem
```

## GitHub Actions Workflow

### Create Workflow File

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3.4"  # Use your Ruby version
          bundler-cache: true

      - name: Validate tag matches gem version
        run: |
          set -euo pipefail
          tag="${GITHUB_REF#refs/tags/}"
          tag_version="${tag#v}"
          gem_version=$(ruby -e "require_relative 'lib/your_gem/version'; puts YourGem::VERSION")
          if [ "$tag_version" != "$gem_version" ]; then
            echo "❌ Tag version ($tag_version) does not match gem version ($gem_version)"
            exit 1
          fi
          echo "✅ Tag v$tag_version matches gem version $gem_version"

      - name: Build gem
        run: gem build your-gem.gemspec

      - name: Publish gem
        env:
          GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }}
        run: |
          set -euo pipefail
          gem_version=$(ruby -e "require_relative 'lib/your_gem/version'; puts YourGem::VERSION")
          gem_file="your-gem-${gem_version}.gem"
          if [ ! -f "$gem_file" ]; then
            echo "❌ Gem file not found: $gem_file"
            exit 1
          fi
          echo "📦 Publishing $gem_file to RubyGems..."
          gem push "$gem_file"
          echo "✅ Published successfully!"
```

**Important:** Replace:
- `your_gem` with your gem's module name
- `YourGem` with your module constant
- `your-gem` with your gem's name

### Optional: Add Testing Before Release

Add a test job that runs before release:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  # Run tests first
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3.4"
          bundler-cache: true
      - name: Run tests
        run: bundle exec rake spec
      - name: Run RuboCop
        run: bundle exec rubocop

  # Release only if tests pass
  release:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      # ... (release steps as above)
```

## RubyGems Authentication

### Step 1: Get RubyGems API Key

1. **Login to RubyGems:**
   - Visit: https://rubygems.org/sign_in

2. **Create API Key:**
   - Go to: https://rubygems.org/profile/edit
   - Scroll to "API Keys" section
   - Click **"New API Key"**

3. **Configure Key:**
   - **Name:** `GitHub Actions - your-gem` (descriptive name)
   - **Scopes:** Select **"Push rubygems"** only (principle of least privilege)
   - Click **"Create"**

4. **Copy Key:**
   - Copy the generated key (you won't see it again!)
   - Format: `rubygems_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Step 2: Add to GitHub Secrets

1. **Navigate to Secrets:**
   - Go to your GitHub repo
   - Click **Settings** → **Secrets and variables** → **Actions**
   - Or visit: `https://github.com/USERNAME/REPO/settings/secrets/actions`

2. **Create Secret:**
   - Click **"New repository secret"**
   - **Name:** `RUBYGEMS_API_KEY` (must match workflow file)
   - **Value:** Paste your RubyGems API key
   - Click **"Add secret"**

3. **Verify:**
   - You should see `RUBYGEMS_API_KEY` in the list
   - The value will be hidden (shows as `***`)

### Step 3: Test Authentication (Optional)

Test locally before using in CI:

```bash
# Set up credentials file
mkdir -p ~/.gem
echo "---
:rubygems_api_key: your_api_key_here" > ~/.gem/credentials
chmod 600 ~/.gem/credentials

# Build and push manually to test
gem build your-gem.gemspec
gem push your-gem-0.1.0.gem

# Clean up
rm your-gem-0.1.0.gem
```

## Release Process

### Standard Release Workflow

#### 1. Update Version

Edit `lib/your_gem/version.rb`:

```ruby
module YourGem
  VERSION = "1.2.3"  # Bump version
end
```

#### 2. Update Changelog

Edit `CHANGELOG.md`:

```markdown
## [1.2.3] - 2026-01-17

### Added
- New feature X
- New feature Y

### Fixed
- Bug fix A
- Bug fix B

### Changed
- Improvement C
```

#### 3. Commit Changes

```bash
git add lib/your_gem/version.rb CHANGELOG.md
git commit -m "Bump version to 1.2.3"
git push origin main
```

#### 4. Create and Push Tag

**Option A: Annotated Tag (Recommended)**

```bash
# Create annotated tag with message
git tag -a v1.2.3 -m "Release v1.2.3

- New feature X
- Bug fix A
- Improvement C"

# Push the tag
git push origin v1.2.3
```

**Option B: Lightweight Tag**

```bash
# Create simple tag
git tag v1.2.3

# Push it
git push origin v1.2.3
```

#### 5. Monitor Release

1. **Check GitHub Actions:**
   - Go to: `https://github.com/USERNAME/REPO/actions`
   - Watch the "Release" workflow run
   - Should show: ✅ Validate → ✅ Build → ✅ Publish

2. **Verify on RubyGems:**
   - Visit: `https://rubygems.org/gems/your-gem`
   - Confirm version 1.2.3 is published
   - Check download stats

3. **Test Installation:**
   ```bash
   gem install your-gem
   # Or with version
   gem install your-gem -v 1.2.3
   ```

### Quick Release Script

Create `bin/release.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Usage: ./bin/release.sh 1.2.3

VERSION=$1
TAG="v${VERSION}"

echo "🚀 Releasing version ${VERSION}"

# Verify version in version.rb matches
CURRENT_VERSION=$(ruby -e "require_relative 'lib/your_gem/version'; puts YourGem::VERSION")
if [ "$CURRENT_VERSION" != "$VERSION" ]; then
  echo "❌ Version mismatch!"
  echo "   lib/your_gem/version.rb: $CURRENT_VERSION"
  echo "   Requested: $VERSION"
  exit 1
fi

# Verify clean working directory
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Working directory not clean. Commit or stash changes first."
  exit 1
fi

# Verify on main branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "⚠️  Not on main branch (currently on: $BRANCH)"
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Create and push tag
echo "📝 Creating tag $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo "⬆️  Pushing tag to origin"
git push origin "$TAG"

echo "✅ Tag pushed! GitHub Actions will publish the gem."
echo "📊 Monitor: https://github.com/USERNAME/REPO/actions"
echo "📦 Once published: https://rubygems.org/gems/your-gem"
```

Make it executable:

```bash
chmod +x bin/release.sh
```

Use it:

```bash
# Update version in lib/your_gem/version.rb first
# Update CHANGELOG.md
# Commit changes
git add -A
git commit -m "Bump version to 1.2.3"
git push

# Run release script
./bin/release.sh 1.2.3
```

## Troubleshooting

### Common Issues

#### 1. "Access Denied" Error

```
Pushing gem to https://rubygems.org...
Access Denied. Please sign up for an account
```

**Solution:**
- Verify `RUBYGEMS_API_KEY` secret is set in GitHub
- Check API key has "Push rubygems" scope
- Ensure you own the gem name

#### 2. "Gem name already taken"

```
There was a problem saving your gem: Name 'your-gem' is already taken
```

**Solution:**
```bash
# Check ownership
gem owner your-gem

# If you own it - check credentials
# If you don't - choose a different name or request ownership
```

#### 3. Version Mismatch Error

```
❌ Tag version (1.2.3) does not match gem version (1.2.2)
```

**Solution:**
```bash
# Update version in lib/your_gem/version.rb
# Delete incorrect tag
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3

# Create correct tag
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

#### 4. "Gem file not found"

```
❌ Gem file not found: your-gem-1.2.3.gem
```

**Solution:**
- Check gemspec file is named correctly
- Verify `spec.name` matches gem name
- Test build locally: `gem build your-gem.gemspec`

#### 5. Workflow Not Triggering

**Check:**
```bash
# Verify tag format
git tag -l  # Should show v1.2.3 format

# Check workflow file location
ls -la .github/workflows/release.yml

# Verify tag trigger in workflow
grep "tags:" .github/workflows/release.yml
```

### Debug Failed Releases

#### View Workflow Logs

1. Go to: `https://github.com/USERNAME/REPO/actions`
2. Click on failed "Release" run
3. Expand failed step to see error

#### Re-run Failed Release

```bash
# Delete failed tag locally and remotely
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3

# Fix the issue

# Re-create and push tag
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

#### Manual Release (Emergency)

If GitHub Actions fails, release manually:

```bash
# Build gem
gem build your-gem.gemspec

# Push manually
gem push your-gem-1.2.3.gem

# Tag the commit after successful push
git tag -a v1.2.3 -m "Release v1.2.3 (manual)"
git push origin v1.2.3
```

## Best Practices

### 1. Semantic Versioning

Follow [SemVer](https://semver.org/):

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes
- **MINOR** (1.0.0 → 1.1.0): New features, backward compatible
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, backward compatible

### 2. Changelog Maintenance

Keep `CHANGELOG.md` updated:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Features in development

## [1.2.3] - 2026-01-17

### Added
- New feature X

### Fixed
- Bug Y

### Changed
- Improvement Z

## [1.2.2] - 2026-01-10
...
```

### 3. Pre-Release Checklist

Before tagging a release:

- [ ] Version bumped in `lib/your_gem/version.rb`
- [ ] `CHANGELOG.md` updated with changes
- [ ] All tests passing locally (`bundle exec rake spec`)
- [ ] RuboCop clean (`bundle exec rubocop`)
- [ ] Changes committed and pushed to main
- [ ] Local build works (`gem build your-gem.gemspec`)

### 4. Git Tag Conventions

Use consistent tag format:

✅ **Good:**
- `v1.2.3` (recommended)
- `1.2.3` (acceptable)

❌ **Bad:**
- `version-1.2.3`
- `release-1.2.3`
- `v1.2.3-final`

### 5. Security

**API Key Security:**
- ✅ Store in GitHub Secrets only
- ✅ Use "Push rubygems" scope only
- ✅ Rotate keys periodically (every 6-12 months)
- ✅ Delete keys for deprecated projects
- ❌ Never commit API keys to git
- ❌ Never share API keys in chat/email

**Gem File Security:**
- Include only necessary files in gem
- Use `spec.files` to explicitly list included files
- Exclude sensitive files (`.env`, credentials, etc.)

### 6. Release Notes

Create GitHub releases for major versions:

```bash
# Using gh CLI
gh release create v1.2.3 \
  --title "v1.2.3 - Feature Name" \
  --notes "## Highlights

- New feature X
- Bug fix Y

See [CHANGELOG.md](CHANGELOG.md) for details."
```

### 7. Testing

Always test gems before public release:

```bash
# Build gem
gem build your-gem.gemspec

# Install locally
gem install ./your-gem-1.2.3.gem

# Test in a sample project
cd ~/tmp/test-project
bundle init
echo 'gem "your-gem", path: "/path/to/your-gem"' >> Gemfile
bundle install

# Test functionality
ruby -e "require 'your_gem'; puts YourGem::VERSION"
```

## Example: Complete Release Flow

Here's a complete example from start to finish:

```bash
# 1. Create new feature branch
git checkout -b feature/add-cool-feature

# 2. Implement feature
# ... code changes ...

# 3. Test locally
bundle exec rspec
bundle exec rubocop

# 4. Commit and push
git add -A
git commit -m "Add cool feature"
git push origin feature/add-cool-feature

# 5. Create PR and merge to main
gh pr create --title "Add cool feature"
# ... review and merge ...

# 6. Pull latest main
git checkout main
git pull origin main

# 7. Bump version
# Edit lib/your_gem/version.rb: VERSION = "1.3.0"
# Edit CHANGELOG.md: Add [1.3.0] section

# 8. Commit version bump
git add lib/your_gem/version.rb CHANGELOG.md
git commit -m "Bump version to 1.3.0"
git push origin main

# 9. Create and push tag
git tag -a v1.3.0 -m "Release v1.3.0

- Add cool feature
- Fix minor bugs"
git push origin v1.3.0

# 10. Monitor GitHub Actions
# Visit: https://github.com/USERNAME/REPO/actions
# Watch Release workflow complete

# 11. Verify on RubyGems
# Visit: https://rubygems.org/gems/your-gem
# Confirm v1.3.0 is live

# 12. Test installation
gem install your-gem
ruby -e "require 'your_gem'; puts YourGem::VERSION"
# Should output: 1.3.0

# 13. Announce release (optional)
# - Update README badges
# - Post on social media
# - Notify users/community
```

## Additional Resources

### Official Documentation

- **RubyGems Guides:** https://guides.rubygems.org/
- **GitHub Actions:** https://docs.github.com/en/actions
- **Semantic Versioning:** https://semver.org/

### Useful Tools

- **gh CLI:** https://cli.github.com/ - Manage GitHub from command line
- **gem-release:** https://github.com/svenfuchs/gem-release - Automate version bumping
- **bundler:** https://bundler.io/ - Dependency management

### Related Workflows

For more advanced setups, check:
- **Multi-platform testing:** Test on multiple Ruby versions
- **Dependency updates:** Automated dependabot PRs
- **Documentation:** Auto-generate and publish docs
- **Code coverage:** Track test coverage over time

## Conclusion

You now have a complete automated gem release pipeline that:

1. ✅ Validates version matches tag
2. ✅ Builds gem automatically
3. ✅ Publishes to RubyGems
4. ✅ Maintains security with GitHub Secrets
5. ✅ Provides audit trail via git tags

This workflow can be reused for all your Ruby gems with minimal modifications!

---

**Questions or Issues?**

- Check [Troubleshooting](#troubleshooting) section
- Review [GitHub Actions logs](https://github.com/USERNAME/REPO/actions)
- Consult [RubyGems Guides](https://guides.rubygems.org/)
