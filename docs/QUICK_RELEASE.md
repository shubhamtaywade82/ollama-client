# Quick Release Reference

Quick reference for releasing gems via GitHub Actions. See [GEM_RELEASE_GUIDE.md](GEM_RELEASE_GUIDE.md) for full details.

## One-Time Setup

### 1. RubyGems API Key
1. Visit: https://rubygems.org/profile/edit
2. Create API key with "Push rubygems" scope
3. Copy the key

### 2. GitHub Secret
1. Go to: `https://github.com/USERNAME/REPO/settings/secrets/actions`
2. Add secret: `RUBYGEMS_API_KEY`
3. Paste your RubyGems API key

### 3. Workflow File
Create `.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3.4"
          bundler-cache: true
      - name: Validate version
        run: |
          tag_version="${GITHUB_REF#refs/tags/v}"
          gem_version=$(ruby -e "require_relative 'lib/your_gem/version'; puts YourGem::VERSION")
          [ "$tag_version" = "$gem_version" ] || exit 1
      - name: Build and publish
        env:
          GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }}
        run: |
          gem build your-gem.gemspec
          gem push your-gem-*.gem
```

## Release Process

### Every Release

```bash
# 1. Update version
# Edit: lib/your_gem/version.rb
VERSION = "1.2.3"

# 2. Update changelog
# Edit: CHANGELOG.md

# 3. Commit
git add lib/your_gem/version.rb CHANGELOG.md
git commit -m "Bump version to 1.2.3"
git push

# 4. Tag and push
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3

# 5. Monitor
# https://github.com/USERNAME/REPO/actions
```

## Quick Commands

```bash
# Create release script: bin/release.sh
#!/bin/bash
VERSION=$1
git tag -a v${VERSION} -m "Release v${VERSION}"
git push origin v${VERSION}
echo "✅ Releasing v${VERSION} - check GitHub Actions"

# Use it:
chmod +x bin/release.sh
./bin/release.sh 1.2.3
```

## Common Issues

**Access Denied?**
- Check `RUBYGEMS_API_KEY` secret exists
- Verify API key has "Push rubygems" scope

**Version Mismatch?**
- Update `lib/your_gem/version.rb`
- Delete tag: `git tag -d v1.2.3 && git push origin :refs/tags/v1.2.3`

**Workflow Not Running?**
- Verify `.github/workflows/release.yml` exists
- Check tag format: `v1.2.3` (with v prefix)

## Links

- **Full Guide:** [GEM_RELEASE_GUIDE.md](GEM_RELEASE_GUIDE.md)
- **Your Actions:** https://github.com/USERNAME/REPO/actions
- **RubyGems:** https://rubygems.org/profile/edit
- **GitHub Secrets:** https://github.com/USERNAME/REPO/settings/secrets/actions
