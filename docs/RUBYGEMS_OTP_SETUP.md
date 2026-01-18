# RubyGems OTP Setup for Automated Releases

This guide explains how to configure OTP (One-Time Password) authentication for automated gem releases with MFA enabled.

## Why This Is Needed

When `rubygems_mfa_required = "true"` is set in your gemspec, RubyGems requires MFA verification for all gem pushes, including automated CI/CD releases. This guide shows how to configure GitHub Actions to generate OTP codes automatically.

## Prerequisites

- RubyGems account with MFA enabled
- Admin access to your GitHub repository (to add secrets)
- Authenticator app (Google Authenticator, Authy, 1Password, etc.)

## Step 1: Get Your RubyGems OTP Secret

### Option A: From Existing MFA Setup

If you already have MFA enabled on RubyGems:

1. **Log in to RubyGems.org**
2. **Go to Edit Profile** → **Multi-factor Authentication**
3. **Click "Show QR Code"** or **"Regenerate Recovery Codes"**
4. When you see the QR code, look for the **secret key** (usually shown below the QR code)
5. Copy the secret key (it's a long alphanumeric string like `JBSWY3DPEHPK3PXP`)

### Option B: Enable MFA Fresh

If you're setting up MFA for the first time:

1. **Log in to RubyGems.org**
2. **Go to Edit Profile** → **Multi-factor Authentication**
3. **Click "Enable MFA"**
4. You'll see a QR code and a **secret key** below it
5. **Copy the secret key** before scanning the QR code
6. Scan the QR code with your authenticator app
7. Enter the 6-digit code to verify

**⚠️ IMPORTANT:** Save the secret key securely. You'll need it for GitHub Actions.

### What the Secret Looks Like

```
Example: JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
- All uppercase letters and numbers
- Typically 32 characters long
- Base32 encoded
```

## Step 2: Add Secrets to GitHub

### 2.1: Add API Key Secret

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `RUBYGEMS_API_KEY`
5. Value: Your RubyGems API key (get from https://rubygems.org/profile/api_keys)
6. Click **Add secret**

### 2.2: Add OTP Secret

1. Still in **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Name: `RUBYGEMS_OTP_SECRET`
4. Value: Your OTP secret key (from Step 1)
5. Click **Add secret**

## Step 3: Verify GitHub Secrets

Your repository should now have two secrets:

```
✅ RUBYGEMS_API_KEY
✅ RUBYGEMS_OTP_SECRET
```

## Step 4: Test the Setup

### Test Locally First

You can test OTP generation locally before pushing:

```bash
# Install rotp gem
gem install rotp

# Generate an OTP code (replace with your actual secret)
ruby -r rotp -e "puts ROTP::TOTP.new('YOUR_SECRET_HERE').now"
```

This should output a 6-digit code that matches your authenticator app.

### Test in CI/CD

1. Bump your gem version in `lib/ollama/version.rb`
2. Commit and push
3. Create and push a matching tag:

```bash
git tag v0.2.4
git push origin v0.2.4
```

4. Check GitHub Actions to see the release workflow run

## How It Works

The GitHub Actions workflow:

1. **Installs `rotp` gem** - Ruby library for generating TOTP codes
2. **Generates OTP code** - Uses your secret to generate a 6-digit code
3. **Pushes gem** - Runs `gem push --otp <code>` with the generated code

```yaml
- name: Install OTP generator
  run: gem install rotp

- name: Publish gem with OTP
  env:
    GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }}
    RUBYGEMS_OTP_SECRET: ${{ secrets.RUBYGEMS_OTP_SECRET }}
  run: |
    otp_code=$(ruby -r rotp -e "puts ROTP::TOTP.new(ENV['RUBYGEMS_OTP_SECRET']).now")
    gem push "ollama-client-${gem_version}.gem" --otp "$otp_code"
```

## Troubleshooting

### "Invalid OTP code" Error

**Cause:** Time synchronization issue or wrong secret

**Solutions:**
1. Verify your secret is correct
2. Check server time is synchronized:
   ```bash
   date
   ```
3. Try regenerating the secret on RubyGems

### "OTP code expired" Error

**Cause:** Code expired before being used (they last 30 seconds)

**Solution:** The workflow generates the code immediately before use, so this shouldn't happen. If it does, there may be a network delay. The workflow will need to retry.

### "unauthorized" Error

**Cause:** API key is invalid or doesn't have push permissions

**Solutions:**
1. Verify `RUBYGEMS_API_KEY` is correct
2. Create a new API key with push permissions
3. Update the secret in GitHub

### Missing Secrets

**Error:** `RUBYGEMS_OTP_SECRET not found`

**Solution:** Ensure both secrets are added to GitHub (Settings → Secrets and variables → Actions)

## Security Considerations

### ✅ Pros
- MFA protection on gem releases
- OTP secret encrypted in GitHub Secrets
- No manual intervention needed
- Audit trail in GitHub Actions

### ⚠️ Considerations
- OTP secret stored in GitHub increases attack surface
- If GitHub is compromised, attacker has both API key and OTP secret
- Alternative: Remove `rubygems_mfa_required` and rely on account-level MFA

### Best Practices

1. **Rotate API keys** regularly
2. **Use scoped API keys** (push-only if possible)
3. **Enable GitHub branch protection** on main branch
4. **Require PR reviews** for sensitive changes
5. **Monitor release logs** for unauthorized pushes
6. **Regenerate OTP secret** if you suspect compromise

## Alternative: Account-Level MFA Only

If you want simpler automation:

1. Remove `rubygems_mfa_required` from gemspec
2. Keep account-level MFA enabled on RubyGems
3. Use API key only (no OTP needed)

This is the recommended approach for most projects as it provides good security with less complexity.

## Reference

- [RubyGems MFA Documentation](https://guides.rubygems.org/setting-up-multifactor-authentication/)
- [ROTP Gem Documentation](https://github.com/mdp/rotp)
- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
