# Gem Release Guide

Complete guide for automated gem releases with MFA security via GitHub Actions.

## Table of Contents

- [Quick Start](#quick-start)
- [One-Time Setup](#one-time-setup)
- [Release Process](#release-process)
- [Troubleshooting](#troubleshooting)
- [How It Works](#how-it-works)

---

## Quick Start

**Already configured?** Just bump version and push a tag:

```bash
# 1. Update version in lib/ollama/version.rb
VERSION = "0.2.4"

# 2. Commit and tag
git add lib/ollama/version.rb
git commit -m "Bump version to 0.2.4"
git tag v0.2.4
git push origin main
git push origin v0.2.4

# 3. Done! GitHub Actions will automatically release to RubyGems
```

Check progress: https://github.com/shubhamtaywade82/ollama-client/actions

---

## One-Time Setup

### Prerequisites

- RubyGems account at https://rubygems.org
- MFA enabled on RubyGems account
- Admin access to GitHub repository

### Step 1: Get RubyGems API Key

1. Log in to https://rubygems.org
2. Go to **Edit Profile** → **API Keys** (or visit https://rubygems.org/profile/api_keys)
3. Click **New API Key**
4. Name: `GitHub Actions - ollama-client`
5. Scopes: Select **Push rubygems**
6. Click **Create**
7. **Copy the API key** (you won't see it again!)

### Step 2: Get RubyGems OTP Secret

This is needed because `rubygems_mfa_required = "true"` in the gemspec requires OTP verification.

#### What You Need

The **OTP secret key** (not the 6-digit codes), which looks like:
```
JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
```

Valid characters: `A-Z` and `2-7` only (Base32 encoding)

#### How to Get It

**Option A: If you saved it when enabling MFA**
- Check your password manager, notes, or screenshots

**Option B: Regenerate MFA (if you can't find it)**

1. Go to https://rubygems.org → **Edit Profile** → **Multi-factor Authentication**
2. Click **"Disable Multi-factor Authentication"**
3. Click **"Enable Multi-factor Authentication"** again
4. **IMPORTANT: Copy the secret key text** (e.g., `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP`)
5. Scan the QR code with your authenticator app
6. Enter the 6-digit code to verify
7. **Update your authenticator app** (old codes won't work after regenerating)

#### Test Your Secret (Optional)

```bash
gem install rotp
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET_HERE').now"
```

This should output a 6-digit number matching your authenticator app.

### Step 3: Add Secrets to GitHub

1. Go to: https://github.com/shubhamtaywade82/ollama-client/settings/secrets/actions
2. Click **New repository secret**
3. Add **first secret**:
   - Name: `RUBYGEMS_API_KEY`
   - Value: Your API key from Step 1
   - Click **Add secret**
4. Add **second secret**:
   - Name: `RUBYGEMS_OTP_SECRET`
   - Value: Your OTP secret from Step 2
   - Click **Add secret**

### Step 4: Verify Setup

Your repository should now have two secrets:
- ✅ `RUBYGEMS_API_KEY`
- ✅ `RUBYGEMS_OTP_SECRET`

**Setup complete!** 🎉

---

## Release Process

### Standard Release

```bash
# 1. Update version
vim lib/ollama/version.rb
# Change VERSION = "0.2.3" to VERSION = "0.2.4"

# 2. Update changelog (optional but recommended)
vim CHANGELOG.md

# 3. Commit changes
git add lib/ollama/version.rb CHANGELOG.md
git commit -m "Bump version to 0.2.4"

# 4. Create and push tag
git tag v0.2.4
git push origin main
git push origin v0.2.4

# 5. Monitor release
# Visit: https://github.com/shubhamtaywade82/ollama-client/actions
```

### What Happens Automatically

When you push a tag (e.g., `v0.2.4`), GitHub Actions will:

1. ✅ **Validate** tag version matches `lib/ollama/version.rb`
2. ✅ **Generate OTP code** automatically from your secret
3. ✅ **Build gem** using `gem build ollama-client.gemspec`
4. ✅ **Push to RubyGems** with OTP authentication
5. ✅ **Publish successfully** - gem is live!

**No manual intervention needed!** ⚡

### Checking Release Status

- **GitHub Actions:** https://github.com/shubhamtaywade82/ollama-client/actions
- **RubyGems:** https://rubygems.org/gems/ollama-client

---

## Troubleshooting

### "Repushing of gem versions is not allowed"

**Problem:** You're trying to push a version that already exists on RubyGems.

**Solution:** Bump the version number in `lib/ollama/version.rb` to a new version.

### "Invalid OTP code"

**Problem:** The OTP secret in GitHub Secrets is incorrect.

**Solutions:**
1. Verify `RUBYGEMS_OTP_SECRET` matches your authenticator app's secret
2. Test locally: `ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET').now"`
3. If still failing, regenerate MFA on RubyGems and update the secret

### "unauthorized" or "Access Denied"

**Problem:** API key is invalid or missing permissions.

**Solutions:**
1. Verify `RUBYGEMS_API_KEY` is set in GitHub Secrets
2. Check the API key has **"Push rubygems"** scope
3. Generate a new API key on RubyGems and update the secret

### "Tag version does not match gem version"

**Problem:** The git tag doesn't match the version in `lib/ollama/version.rb`.

**Solution:**
```bash
# If tag is v0.2.4 but version.rb says 0.2.3:

# Option 1: Update version.rb and create new tag
vim lib/ollama/version.rb  # Change to 0.2.4
git add lib/ollama/version.rb
git commit -m "Fix version"
git tag -d v0.2.4  # Delete local tag
git push origin :refs/tags/v0.2.4  # Delete remote tag
git tag v0.2.4  # Create new tag
git push origin main v0.2.4  # Push both

# Option 2: Create tag matching current version
# If version.rb says 0.2.3, use v0.2.3 tag instead
```

### "Invalid Base32 Character"

**Problem:** Your OTP secret contains invalid characters.

**Cause:** You're using the placeholder `'YOUR_SECRET_HERE'` or the 6-digit OTP code instead of the actual secret.

**Solution:** Get the real Base32 secret from RubyGems (see Step 2 in Setup).

Valid secret format:
- ✅ `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP`
- ❌ `123456` (that's the OTP code, not the secret)
- ❌ `YOUR_SECRET_HERE` (that's the placeholder)

### Workflow Not Running

**Problem:** You pushed a tag but GitHub Actions didn't trigger.

**Check:**
1. Tag format is correct: `v1.2.3` (with `v` prefix)
2. Workflow file exists: `.github/workflows/release.yml`
3. Check Actions tab for errors: https://github.com/shubhamtaywade82/ollama-client/actions

---

## How It Works

### GitHub Actions Workflow

The workflow (`.github/workflows/release.yml`) runs when you push a tag:

```yaml
on:
  push:
    tags:
      - "v*"  # Triggers on any tag starting with 'v'
```

### Key Steps

1. **Tag Validation**
   ```bash
   # Ensures tag matches gem version
   tag_version="${GITHUB_REF#refs/tags/v}"
   gem_version=$(ruby -e "require_relative 'lib/ollama/version'; puts Ollama::VERSION")
   [ "$tag_version" = "$gem_version" ] || exit 1
   ```

2. **OTP Generation**
   ```bash
   # Automatically generates OTP code from secret
   gem install rotp
   otp_code=$(ruby -r rotp -e "puts ROTP::TOTP.new(ENV['RUBYGEMS_OTP_SECRET']).now")
   ```

3. **Gem Build**
   ```bash
   gem build ollama-client.gemspec
   ```

4. **Publish with OTP**
   ```bash
   gem push "ollama-client-${gem_version}.gem" --otp "$otp_code"
   ```

### Security Features

- 🔒 **MFA Required** - `rubygems_mfa_required = "true"` in gemspec
- 🔐 **Encrypted Secrets** - API key and OTP secret stored securely in GitHub
- ✅ **Tag Validation** - Prevents accidental version mismatches
- 🔍 **Audit Trail** - All releases logged in GitHub Actions

### Why OTP is Needed

The gemspec has:
```ruby
spec.metadata["rubygems_mfa_required"] = "true"
```

This requires OTP verification for **all** gem pushes, including automated CI/CD. The workflow solves this by:
1. Storing your OTP secret in GitHub Secrets
2. Generating fresh OTP codes automatically on each release
3. Passing the code to `gem push --otp`

**Result:** Fully automated releases with MFA security! 🚀

---

## Best Practices

### Version Naming

Follow [Semantic Versioning](https://semver.org/):
- **Major** (X.0.0): Breaking changes
- **Minor** (0.X.0): New features, backward compatible
- **Patch** (0.0.X): Bug fixes, backward compatible

### Changelog

Update `CHANGELOG.md` with each release:
```markdown
## [0.2.4] - 2026-01-18

### Added
- New feature X

### Fixed
- Bug fix Y

### Changed
- Updated Z
```

### Git Tags

- Always use annotated tags: `git tag -a v1.2.3 -m "Release v1.2.3"`
- Include `v` prefix: `v1.2.3` not `1.2.3`
- Tag message should be descriptive

### Security

- 🔄 **Rotate API keys** periodically
- 📝 **Review release logs** in GitHub Actions
- 🔒 **Keep secrets secure** - never commit them to git
- 🛡️ **Enable branch protection** on main branch

---

## Quick Reference

### Commands Cheat Sheet

```bash
# Check current version
ruby -e "require_relative 'lib/ollama/version'; puts Ollama::VERSION"

# Build gem locally
gem build ollama-client.gemspec

# Test OTP generation
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET').now"

# List all tags
git tag -l

# Delete tag (if needed)
git tag -d v1.2.3                      # Delete locally
git push origin :refs/tags/v1.2.3      # Delete remotely

# Create release
git tag v1.2.3 && git push origin v1.2.3
```

### Important Links

- **GitHub Actions:** https://github.com/shubhamtaywade82/ollama-client/actions
- **GitHub Secrets:** https://github.com/shubhamtaywade82/ollama-client/settings/secrets/actions
- **RubyGems Gem:** https://rubygems.org/gems/ollama-client
- **RubyGems API Keys:** https://rubygems.org/profile/api_keys
- **RubyGems MFA:** https://rubygems.org/profile/edit (Multi-factor Authentication section)

---

## Summary

✅ **One-time setup:** Add two GitHub Secrets
✅ **Every release:** Bump version + push tag
✅ **Fully automated:** No manual gem push needed
✅ **MFA secured:** OTP authentication on every release
✅ **Production ready:** Used for all ollama-client releases

Questions or issues? Check the [Troubleshooting](#troubleshooting) section above.
